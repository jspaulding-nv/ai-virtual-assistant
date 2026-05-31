#!/bin/bash
set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-${HOME}/launchable-startup.log}"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

export PATH="${PATH}:${HOME}/.local/bin"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-}"

if [[ -z "${REPO_DIR}" ]]; then
  for candidate in \
    "${HOME}/ai-virtual-assistant" \
    "/home/ubuntu/ai-virtual-assistant" \
    "$(cd -- "${SCRIPT_DIR}/.." && pwd)"; do
    if [[ -f "${candidate}/deploy/compose/docker-compose.yaml" ]]; then
      REPO_DIR="${candidate}"
      break
    fi
  done
fi

if [[ -z "${REPO_DIR}" || ! -f "${REPO_DIR}/deploy/compose/docker-compose.yaml" ]]; then
  log "Could not find the ai-virtual-assistant repository. Set REPO_DIR and rerun this script."
  exit 1
fi

cd "${REPO_DIR}"
log "Using repository: ${REPO_DIR}"

apt_install() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get is not available; install missing dependency manually: $*"
    return 1
  fi

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_python_tools() {
  log "Installing Jupyter and notebook helper packages."

  if ! command -v python3 >/dev/null 2>&1; then
    apt_install python3 python3-pip
  fi

  if ! python3 -m pip --version >/dev/null 2>&1; then
    apt_install python3-pip
  fi

  python3 -m pip install --user --upgrade pip jupyter jupyterlab openai pandas psycopg2-binary \
    || python3 -m pip install --user --break-system-packages --upgrade pip jupyter jupyterlab openai pandas psycopg2-binary
}

stop_influxdb_if_present() {
  if command -v systemctl >/dev/null 2>&1 \
    && systemctl list-unit-files --type=service 2>/dev/null | grep -q '^influxdb.service'; then
    log "Stopping the preinstalled influxdb service."
    sudo systemctl stop influxdb || true
  fi
}

start_jupyter() {
  if [[ -f "${REPO_DIR}/deploy/ai_virtual_assistant_notebook.ipynb" ]]; then
    cp -f "${REPO_DIR}/deploy/ai_virtual_assistant_notebook.ipynb" "${HOME}/ai_virtual_assistant_notebook.ipynb"
  fi

  if pgrep -f "jupyter.*8889" >/dev/null 2>&1; then
    log "Jupyter Lab is already running on port 8889."
    return
  fi

  log "Starting Jupyter Lab on port 8889."
  nohup jupyter lab \
    --no-browser \
    --allow-root \
    --ip=0.0.0.0 \
    --port=8889 \
    --notebook-dir="${HOME}" \
    --ServerApp.token='' \
    --ServerApp.password='' \
    > "${HOME}/jupyterlab.log" 2>&1 &
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    sudo systemctl start docker >/dev/null 2>&1 || true
    return
  fi

  log "Installing Docker Engine and Docker Compose plugin."
  apt_install ca-certificates curl gnupg

  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  . /etc/os-release
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "${VERSION_CODENAME}" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker >/dev/null 2>&1 || true
}

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

load_existing_env() {
  if [[ -f "${REPO_DIR}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_DIR}/.env"
    set +a
  fi
}

is_placeholder_value() {
  [[ "$1" == "your NVIDIA Inference Microservices API key" || "$1" == "your NGC API key" ]]
}

prepare_launchable_env() {
  load_existing_env

  local nvidia_key="${NVIDIA_API_KEY:-}"
  local ngc_key="${NGC_API_KEY:-}"

  if is_placeholder_value "${nvidia_key}"; then
    nvidia_key=""
  fi
  if is_placeholder_value "${ngc_key}"; then
    ngc_key=""
  fi

  if [[ -z "${nvidia_key}" && -n "${ngc_key}" ]]; then
    nvidia_key="${ngc_key}"
  fi
  if [[ -z "${ngc_key}" && -n "${nvidia_key}" ]]; then
    ngc_key="${nvidia_key}"
    log "NGC_API_KEY is not set; using NVIDIA_API_KEY for nvcr.io login. This only works if that key is an NGC personal key."
  fi

  if [[ -z "${nvidia_key}" ]]; then
    log "NVIDIA_API_KEY is not set. Jupyter is running, but Docker Compose startup was skipped."
    log "Add NVIDIA_API_KEY and NGC_API_KEY as Brev Launchable secrets, then rerun: docker compose --env-file .env.launchable -f deploy/compose/docker-compose.yaml up -d --build"
    return 1
  fi

  umask 077
  {
    printf 'NVIDIA_API_KEY=%s\n' "${nvidia_key}"
    printf 'NGC_API_KEY=%s\n' "${ngc_key}"
    printf 'APP_LLM_MODELNAME=nvidia/nemotron-3-nano-30b-a3b\n'
    printf 'APP_VECTORSTORE_INDEXTYPE=IVF_FLAT\n'
  } > "${REPO_DIR}/.env.launchable"

  export NVIDIA_API_KEY="${nvidia_key}"
  export NGC_API_KEY="${ngc_key}"
}

start_compose_stack() {
  if ! prepare_launchable_env; then
    return 1
  fi

  log "Authenticating Docker with nvcr.io."
  if ! printf '%s' "${NGC_API_KEY}" | docker_cmd login nvcr.io -u '$oauthtoken' --password-stdin; then
    log "Docker login failed. Jupyter is running, but Docker Compose startup was skipped."
    return 1
  fi

  log "Starting the hosted-NIM Docker Compose stack with CPU Milvus."
  if ! docker_cmd compose --env-file "${REPO_DIR}/.env.launchable" \
    -f "${REPO_DIR}/deploy/compose/docker-compose.yaml" \
    up -d --build; then
    log "Docker Compose startup failed. Check ${LOG_FILE} and Docker logs for details."
    return 1
  fi

  docker_cmd compose --env-file "${REPO_DIR}/.env.launchable" \
    -f "${REPO_DIR}/deploy/compose/docker-compose.yaml" \
    ps || true
}

main() {
  log "Starting NVIDIA Brev Launchable setup."
  stop_influxdb_if_present
  ensure_python_tools
  start_jupyter
  ensure_docker
  if ! start_compose_stack; then
    log "The Docker Compose stack is not running yet. Jupyter remains available for manual setup."
  fi
  log "Startup complete. Jupyter: port 8889. UI: port 3001 when Docker Compose services are healthy."
}

main "$@"
