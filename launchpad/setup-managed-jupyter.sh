#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf '%s\n' \
    "Usage:" \
    "  bash launchpad/setup-managed-jupyter.sh" \
    "" \
    "Prepares the LaunchPad-managed Jupyter Notebook resource for this lab." \
    "It copies the repo into the Jupyter workspace, exposes a LaunchPad-specific" \
    "ai_virtual_assistant_notebook.ipynb at the top level, registers an AIVA" \
    "kernel inside the Jupyter container, and enables Docker CLI access from" \
    "Jupyter terminals through the host Docker socket." \
    "" \
    "Environment:" \
    "  LAUNCHPAD_JUPYTER_ROOT       Host workspace. Defaults to /opt/nvidia/launchpad/jupyter-notebook." \
    "  LAUNCHPAD_JUPYTER_CONTAINER  Container name. Defaults to jupyter-notebook."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[launchpad-jupyter] %s\n' "$*"
}

die() {
  printf '[launchpad-jupyter] ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

JUPYTER_ROOT="${LAUNCHPAD_JUPYTER_ROOT:-/opt/nvidia/launchpad/jupyter-notebook}"
JUPYTER_CONTAINER="${LAUNCHPAD_JUPYTER_CONTAINER:-jupyter-notebook}"
JUPYTER_REPO="${JUPYTER_ROOT}/ai-virtual-assistant"
NOTEBOOK_NAME="ai_virtual_assistant_notebook.ipynb"
NOTEBOOK_SOURCE="${REPO_ROOT}/launchpad/${NOTEBOOK_NAME}"
PROXY_SOCKET="${JUPYTER_ROOT}/docker.sock"
PROXY_PID="${JUPYTER_ROOT}/docker-socket-proxy.pid"
PROXY_LOG="${JUPYTER_ROOT}/docker-socket-proxy.log"
AIVA_BIN_DIR="${JUPYTER_ROOT}/.aiva/bin"
AIVA_PLUGIN_DIR="${JUPYTER_ROOT}/.aiva/docker-cli-plugins"

command -v docker >/dev/null 2>&1 || die "docker is not installed on the LaunchPad host."
docker info >/dev/null 2>&1 || die "docker is not reachable from this host shell."
[[ -f "${NOTEBOOK_SOURCE}" ]] || die "missing notebook source: ${NOTEBOOK_SOURCE}"

if ! docker inspect "${JUPYTER_CONTAINER}" >/dev/null 2>&1; then
  while IFS=$'\t' read -r name image; do
    if [[ "${name}" == "jupyter-notebook" || "${image}" == lp-jupyter-notebook:* ]]; then
      JUPYTER_CONTAINER="${name}"
      break
    fi
  done < <(docker ps --format '{{.Names}}\t{{.Image}}')
fi

docker inspect "${JUPYTER_CONTAINER}" >/dev/null 2>&1 \
  || die "could not find the LaunchPad Jupyter container. Open Resources > Jupyter Notebook once, then rerun this script."

log "Using Jupyter container: ${JUPYTER_CONTAINER}"
log "Using Jupyter host workspace: ${JUPYTER_ROOT}"

mkdir -p "${JUPYTER_REPO}" "${AIVA_BIN_DIR}" "${AIVA_PLUGIN_DIR}"
mkdir -p /home/nvidia/.cache/nim

if [[ "$(cd "${REPO_ROOT}" && pwd)" != "$(cd "${JUPYTER_REPO}" && pwd)" ]]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude '.git/' \
      --exclude '.venv/' \
      --exclude '.venv-*/' \
      --exclude '.venv-notebooks/' \
      --exclude '__pycache__/' \
      --exclude 'logs/' \
      "${REPO_ROOT}/" "${JUPYTER_REPO}/"
  else
    cp -R "${REPO_ROOT}/." "${JUPYTER_REPO}/"
  fi
fi

cp -f "${NOTEBOOK_SOURCE}" "${JUPYTER_ROOT}/${NOTEBOOK_NAME}"
log "Copied notebook to ${JUPYTER_ROOT}/${NOTEBOOK_NAME}"

container_jupyter_root=""
while IFS='|' read -r source destination; do
  [[ -n "${source}" && -n "${destination}" ]] || continue
  if [[ "${JUPYTER_ROOT}" == "${source}" || "${JUPYTER_ROOT}" == "${source}/"* ]]; then
    suffix="${JUPYTER_ROOT#${source}}"
    container_jupyter_root="${destination}${suffix}"
    break
  fi
done < <(docker inspect --format '{{range .Mounts}}{{printf "%s|%s\n" .Source .Destination}}{{end}}' "${JUPYTER_CONTAINER}")

container_jupyter_root="${container_jupyter_root:-${JUPYTER_ROOT}}"

if [[ "${container_jupyter_root}" != "${JUPYTER_ROOT}" ]]; then
  log "Jupyter workspace is mounted at ${container_jupyter_root} inside the container."
  log "Creating an in-container symlink so Docker Compose paths match the host."
  docker exec "${JUPYTER_CONTAINER}" sh -lc \
    "mkdir -p '$(dirname "${JUPYTER_ROOT}")' && { [ -e '${JUPYTER_ROOT}' ] || ln -s '${container_jupyter_root}' '${JUPYTER_ROOT}'; }"
fi

docker exec "${JUPYTER_CONTAINER}" sh -lc \
  "test -f '${JUPYTER_ROOT}/${NOTEBOOK_NAME}' && test -d '${JUPYTER_REPO}'" \
  || die "the Jupyter container cannot see ${JUPYTER_ROOT}. Check the container mount configuration."

workspace_file="${JUPYTER_ROOT}/.aiva/aiva-jupyterlab-default-workspace.json"
cat > "${workspace_file}" <<JSON
{
  "data": {
    "layout-restorer:data": {
      "main": {
        "dock": {
          "type": "tab-area",
          "currentIndex": 0,
          "widgets": [
            "notebook:${NOTEBOOK_NAME}:Notebook"
          ]
        },
        "mode": "multiple-document"
      }
    },
    "notebook:${NOTEBOOK_NAME}:Notebook": {
      "data": {
        "path": "${NOTEBOOK_NAME}",
        "factory": "Notebook"
      }
    }
  },
  "metadata": {
    "id": "/lab"
  }
}
JSON

if docker exec "${JUPYTER_CONTAINER}" sh -lc "jupyter lab workspaces import '${workspace_file}' >/dev/null 2>&1"; then
  log "Configured JupyterLab's default workspace to open ${NOTEBOOK_NAME}."
else
  log "Could not import the JupyterLab workspace; ${NOTEBOOK_NAME} is still available at the file-browser root."
fi

find_compose_plugin() {
  local from_docker_info
  from_docker_info="$(docker info --format '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}' 2>/dev/null || true)"
  if [[ -n "${from_docker_info}" && -x "${from_docker_info}" ]]; then
    printf '%s\n' "${from_docker_info}"
    return 0
  fi

  local candidate
  for candidate in \
    "${HOME}/.docker/cli-plugins/docker-compose" \
    "/usr/local/lib/docker/cli-plugins/docker-compose" \
    "/usr/local/libexec/docker/cli-plugins/docker-compose" \
    "/usr/lib/docker/cli-plugins/docker-compose" \
    "/usr/libexec/docker/cli-plugins/docker-compose"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if command -v docker-compose >/dev/null 2>&1; then
    command -v docker-compose
    return 0
  fi

  return 1
}

install -m 0755 "$(command -v docker)" "${AIVA_BIN_DIR}/docker"
if compose_plugin="$(find_compose_plugin)"; then
  install -m 0755 "${compose_plugin}" "${AIVA_PLUGIN_DIR}/docker-compose"
else
  log "Could not find the Docker Compose plugin on the host; docker compose may need to be installed inside the Jupyter container."
fi

if docker exec "${JUPYTER_CONTAINER}" sh -lc 'test -S /var/run/docker.sock'; then
  container_docker_host="unix:///var/run/docker.sock"
  log "Jupyter container already has /var/run/docker.sock."
else
  [[ -S /var/run/docker.sock ]] || die "host Docker socket /var/run/docker.sock does not exist."

  if ! command -v socat >/dev/null 2>&1; then
    log "Installing socat on the LaunchPad host for the Docker socket proxy."
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y socat
    else
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y socat
    fi
  fi

  if [[ -f "${PROXY_PID}" ]] && kill -0 "$(cat "${PROXY_PID}")" >/dev/null 2>&1; then
    log "Docker socket proxy is already running."
  else
    rm -f "${PROXY_SOCKET}"
    nohup socat "UNIX-LISTEN:${PROXY_SOCKET},fork,unlink-early,mode=666" \
      "UNIX-CONNECT:/var/run/docker.sock" >"${PROXY_LOG}" 2>&1 &
    printf '%s\n' "$!" > "${PROXY_PID}"
    sleep 1
  fi

  docker -H "unix://${PROXY_SOCKET}" info >/dev/null 2>&1 \
    || die "Docker socket proxy did not become usable. See ${PROXY_LOG}."
  container_docker_host="unix://${JUPYTER_ROOT}/docker.sock"
  log "Docker socket proxy is available at ${PROXY_SOCKET}"
fi

docker exec "${JUPYTER_CONTAINER}" sh -lc \
  "mkdir -p /usr/local/bin /usr/local/lib/docker/cli-plugins && \
   ln -sf '${JUPYTER_ROOT}/.aiva/bin/docker' /usr/local/bin/docker && \
   if [ -x '${JUPYTER_ROOT}/.aiva/docker-cli-plugins/docker-compose' ]; then \
     ln -sf '${JUPYTER_ROOT}/.aiva/docker-cli-plugins/docker-compose' /usr/local/lib/docker/cli-plugins/docker-compose; \
   fi"

host_gateway="$(docker exec "${JUPYTER_CONTAINER}" sh -lc "ip route 2>/dev/null | awk '/default/ {print \$3; exit}'" || true)"
host_gateway="${host_gateway:-172.17.0.1}"

docker exec \
  -e AIVA_DOCKER_HOST="${container_docker_host}" \
  -e AIVA_REPO="${JUPYTER_REPO}" \
  -e AIVA_INGEST_HOST="${host_gateway}" \
  -e AIVA_UNSTRUCTURED_DATA_PORT="18086" \
  "${JUPYTER_CONTAINER}" sh -s <<'SH'
set -e
cat > /etc/profile.d/aiva-launchpad.sh <<EOF
export DOCKER_HOST="${AIVA_DOCKER_HOST}"
export AIVA_REPO="${AIVA_REPO}"
export AIVA_INGEST_HOST="${AIVA_INGEST_HOST}"
export AIVA_UNSTRUCTURED_DATA_PORT="${AIVA_UNSTRUCTURED_DATA_PORT}"
export PATH="/usr/local/bin:\${PATH}"
EOF

if [ -f /etc/bash.bashrc ] && ! grep -q '/etc/profile.d/aiva-launchpad.sh' /etc/bash.bashrc; then
  printf '\n[ -f /etc/profile.d/aiva-launchpad.sh ] && . /etc/profile.d/aiva-launchpad.sh\n' >> /etc/bash.bashrc
fi
SH

log "Installing notebook dependencies and registering the AIVA LaunchPad kernel in the Jupyter container."
docker exec \
  -e AIVA_INGEST_HOST="${host_gateway}" \
  -e AIVA_UNSTRUCTURED_DATA_PORT="18086" \
  "${JUPYTER_CONTAINER}" sh -lc "
    python3 -m pip install --user --break-system-packages ipykernel requests pandas psycopg2-binary >/tmp/aiva-jupyter-pip.log 2>&1 \
      || python3 -m pip install --user ipykernel requests pandas psycopg2-binary >/tmp/aiva-jupyter-pip.log 2>&1
    python3 -m ipykernel install --user --name aiva-launchpad --display-name 'AIVA LaunchPad'
    python3 - <<'PY'
import json
import os
from pathlib import Path

kernel_json = Path.home() / '.local/share/jupyter/kernels/aiva-launchpad/kernel.json'
kernel_data = json.loads(kernel_json.read_text())
kernel_env = kernel_data.setdefault('env', {})
kernel_env['AIVA_INGEST_HOST'] = os.environ['AIVA_INGEST_HOST']
kernel_env['AIVA_UNSTRUCTURED_DATA_PORT'] = os.environ['AIVA_UNSTRUCTURED_DATA_PORT']
kernel_json.write_text(json.dumps(kernel_data, indent=2) + '\n')
PY
  " || die "failed to install/register the Jupyter kernel. Check /tmp/aiva-jupyter-pip.log inside ${JUPYTER_CONTAINER}."

docker exec "${JUPYTER_CONTAINER}" sh -lc \
  ". /etc/profile.d/aiva-launchpad.sh && docker compose version >/dev/null && docker ps --format '{{.Names}}' >/dev/null" \
  || die "docker is still not usable inside the Jupyter container."

log "Managed Jupyter setup complete."
log "Open Resources > Jupyter Notebook, then open ${NOTEBOOK_NAME}."
log "In a Jupyter terminal, docker and docker compose should now work."
log "The ingestion kernel talks to the host-published retriever at ${host_gateway}:18086."
