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
REPO_URL="${REPO_URL:-${GIT_REPO_URL:-}}"
REPO_BRANCH="${REPO_BRANCH:-${GIT_BRANCH:-}}"
if [[ -z "${REPO_URL}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  REPO_URL="https://github.com/${GITHUB_REPOSITORY}.git"
fi
REPO_URL="${REPO_URL:-https://github.com/jspaulding-nv/ai-virtual-assistant.git}"
if [[ "${REPO_URL}" == https://github.com/*/tree/* ]]; then
  branch_from_url="${REPO_URL#*/tree/}"
  branch_from_url="${branch_from_url%%/*}"
  REPO_URL="${REPO_URL%%/tree/*}.git"
  REPO_BRANCH="${REPO_BRANCH:-${branch_from_url}}"
fi
if [[ "${REPO_URL}" == https://github.com/* && "${REPO_URL}" != *.git ]]; then
  REPO_URL="${REPO_URL}.git"
fi
REPO_BRANCH="${REPO_BRANCH:-nemotron3-milvus-cpu}"
REPO_WAIT_SECONDS="${REPO_WAIT_SECONDS:-180}"
USE_GHCR_IMAGES="${USE_GHCR_IMAGES:-1}"
GHCR_OWNER="${GHCR_OWNER:-jspaulding-nv}"
GHCR_IMAGE_PREFIX="${GHCR_IMAGE_PREFIX:-aiva-customer-service}"
GHCR_TAG="${GHCR_TAG:-nemotron3-milvus-cpu}"
export USE_GHCR_IMAGES GHCR_OWNER GHCR_IMAGE_PREFIX GHCR_TAG

apt_install() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get is not available; install missing dependency manually: $*"
    return 1
  fi

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

find_repo_dir() {
  local candidate

  if [[ -n "${REPO_DIR}" && -f "${REPO_DIR}/deploy/compose/docker-compose.yaml" ]]; then
    printf '%s\n' "${REPO_DIR}"
    return 0
  fi

  for candidate in \
    "${HOME}/ai-virtual-assistant" \
    "${HOME}/workspace/ai-virtual-assistant" \
    "${HOME}/workspaces/ai-virtual-assistant" \
    "${HOME}/brev/ai-virtual-assistant" \
    "/home/ubuntu/ai-virtual-assistant" \
    "$(cd -- "${SCRIPT_DIR}/.." && pwd)"; do
    if [[ -f "${candidate}/deploy/compose/docker-compose.yaml" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  local root
  local found

  for root in "${HOME}" /workspace /workspaces; do
    if [[ ! -d "${root}" ]]; then
      continue
    fi

    found="$(find "${root}" -maxdepth 4 \
      -path '*/deploy/compose/docker-compose.yaml' \
      -print -quit 2>/dev/null || true)"
    if [[ -n "${found}" ]]; then
      printf '%s\n' "${found%/deploy/compose/docker-compose.yaml}"
      return 0
    fi
  done
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi

  log "Installing git."
  apt_install git
}

ensure_repo_branch() {
  local current_branch

  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    return 0
  fi

  cd "${REPO_DIR}"
  current_branch="$(git branch --show-current 2>/dev/null || true)"
  if [[ "${current_branch}" == "${REPO_BRANCH}" ]]; then
    return 0
  fi

  log "Checking out repository branch ${REPO_BRANCH}."
  if ! git fetch origin "${REPO_BRANCH}" --depth=1; then
    log "Failed to fetch branch ${REPO_BRANCH} from origin."
    return 1
  fi
  git checkout -B "${REPO_BRANCH}" "origin/${REPO_BRANCH}"
}

resolve_repo_dir() {
  local deadline
  local found

  deadline=$((SECONDS + REPO_WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    found="$(find_repo_dir || true)"
    if [[ -n "${found}" ]]; then
      REPO_DIR="${found}"
      if ! ensure_repo_branch; then
        return 1
      fi
      cd "${REPO_DIR}"
      log "Using repository: ${REPO_DIR}"
      return 0
    fi

    log "Waiting for the ai-virtual-assistant repository checkout..."
    sleep 10
  done

  ensure_git
  REPO_DIR="${REPO_DIR:-${HOME}/ai-virtual-assistant}"
  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log "Repository was not found after ${REPO_WAIT_SECONDS}s; cloning ${REPO_URL} branch ${REPO_BRANCH} into ${REPO_DIR}."
    if ! git clone --branch "${REPO_BRANCH}" --single-branch "${REPO_URL}" "${REPO_DIR}"; then
      log "Git clone failed. Set REPO_DIR or REPO_URL and rerun this script."
      return 1
    fi
  fi

  if [[ ! -f "${REPO_DIR}/deploy/compose/docker-compose.yaml" ]]; then
    log "Could not find deploy/compose/docker-compose.yaml in ${REPO_DIR}."
    return 1
  fi

  if ! ensure_repo_branch; then
    return 1
  fi
  cd "${REPO_DIR}"
  log "Using repository: ${REPO_DIR}"
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

configure_jupyter_workspace() {
  local notebook_path="$1"
  local workspace_file="${HOME}/aiva-jupyterlab-default-workspace.json"
  local widget_id="notebook:${notebook_path}:Notebook"

  cat > "${workspace_file}" <<JSON
{
  "data": {
    "${widget_id}": {
      "data": {
        "path": "${notebook_path}",
        "factory": "Notebook"
      }
    },
    "layout-restorer:data": {
      "main": {
        "dock": {
          "type": "tab-area",
          "currentIndex": 0,
          "widgets": [
            "${widget_id}"
          ]
        },
        "mode": "multiple-document"
      },
      "down": {
        "size": 0,
        "widgets": []
      },
      "left": {
        "collapsed": false,
        "current": "filebrowser",
        "widgets": [
          "filebrowser",
          "running-sessions",
          "table-of-contents"
        ]
      },
      "right": {
        "collapsed": true,
        "widgets": []
      },
      "relativeSizes": [
        0.23,
        0.77,
        0
      ]
    }
  },
  "metadata": {
    "id": "/lab"
  }
}
JSON

  if jupyter lab workspaces import "${workspace_file}" >/dev/null 2>&1; then
    log "Configured JupyterLab default workspace to open ${notebook_path}."
  else
    log "Could not import the JupyterLab default workspace; continuing with URL defaults."
  fi
}

start_jupyter() {
  local default_url="/lab"
  local notebook_root="${HOME}"
  local repo_path_for_jupyter="${REPO_DIR#${HOME}/}"
  local default_notebook=""
  local launchable_notebook="${HOME}/ai_virtual_assistant_notebook.ipynb"

  if [[ "${repo_path_for_jupyter}" == "${REPO_DIR}" ]]; then
    repo_path_for_jupyter=""
  fi

  if [[ -f "${REPO_DIR}/deploy/ai_virtual_assistant_notebook_brev.ipynb" ]]; then
    cp -f "${REPO_DIR}/deploy/ai_virtual_assistant_notebook_brev.ipynb" "${launchable_notebook}"
  elif [[ -f "${REPO_DIR}/deploy/ai_virtual_assistant_notebook.ipynb" ]]; then
    cp -f "${REPO_DIR}/deploy/ai_virtual_assistant_notebook.ipynb" "${HOME}/ai_virtual_assistant_notebook.ipynb"
  fi

  if [[ -f "${launchable_notebook}" ]]; then
    default_notebook="ai_virtual_assistant_notebook.ipynb"
    default_url="/lab/tree/${default_notebook}"
  elif [[ -f "${REPO_DIR}/notebooks/ingest_data.ipynb" ]]; then
    default_notebook="${repo_path_for_jupyter:+${repo_path_for_jupyter}/}notebooks/ingest_data.ipynb"
    default_url="/lab/tree/${default_notebook}"
  fi

  if [[ -n "${default_notebook}" ]]; then
    configure_jupyter_workspace "${default_notebook}"
  fi

  if pgrep -f "jupyter.*8889" >/dev/null 2>&1; then
    log "Restarting Jupyter Lab on port 8889 with the launchable notebook as the default URL."
    pkill -f "jupyter.*8889" || true
    sleep 2
  fi

  log "Starting Jupyter Lab on port 8889."
  nohup jupyter lab \
    --no-browser \
    --allow-root \
    --ip=0.0.0.0 \
    --port=8889 \
    --ServerApp.root_dir="${notebook_root}" \
    --ServerApp.default_url="${default_url}" \
    --LabApp.default_url="${default_url}" \
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
  if [[ -z "${ngc_key}" && -n "${nvidia_key}" && "${USE_GHCR_IMAGES:-0}" != "1" ]]; then
    ngc_key="${nvidia_key}"
    log "NGC_API_KEY is not set; using NVIDIA_API_KEY for nvcr.io login. This only works if that key is an NGC personal key."
  fi

  if [[ -z "${nvidia_key}" ]]; then
    log "NVIDIA_API_KEY is not set. Jupyter is running, but Docker Compose startup was skipped."
    log "Open ai_virtual_assistant_notebook.ipynb in Jupyter, enter NVIDIA_API_KEY, and the notebook will pull public GHCR images and start Compose."
    return 1
  fi

  umask 077
  {
    printf 'NVIDIA_API_KEY=%s\n' "${nvidia_key}"
    printf 'NGC_API_KEY=%s\n' "${ngc_key}"
    printf 'APP_LLM_MODELNAME=nvidia/nemotron-3-nano-30b-a3b\n'
    printf 'APP_VECTORSTORE_INDEXTYPE=IVF_FLAT\n'
    if [[ "${USE_GHCR_IMAGES:-0}" == "1" ]]; then
      printf 'GHCR_OWNER=%s\n' "${GHCR_OWNER:-jspaulding-nv}"
      printf 'GHCR_IMAGE_PREFIX=%s\n' "${GHCR_IMAGE_PREFIX:-aiva-customer-service}"
      printf 'GHCR_TAG=%s\n' "${GHCR_TAG:-nemotron3-milvus-cpu}"
    fi
  } > "${REPO_DIR}/.env.launchable"

  export NVIDIA_API_KEY="${nvidia_key}"
  export NGC_API_KEY="${ngc_key}"
}

start_compose_stack() {
  if ! prepare_launchable_env; then
    return 1
  fi

  local compose_files=(
    -f "${REPO_DIR}/deploy/compose/docker-compose.yaml"
  )
  local compose_up_args=(
    up -d --build
  )

  if [[ "${USE_GHCR_IMAGES:-0}" == "1" && -f "${REPO_DIR}/deploy/compose/docker-compose.ghcr.yaml" ]]; then
    compose_files+=(
      -f "${REPO_DIR}/deploy/compose/docker-compose.ghcr.yaml"
    )
    compose_up_args=(
      up -d --no-build
    )

    if [[ -n "${GHCR_USER:-}" && -n "${GHCR_TOKEN:-}" ]]; then
      log "Authenticating Docker with ghcr.io."
      if ! printf '%s' "${GHCR_TOKEN}" | docker_cmd login ghcr.io -u "${GHCR_USER}" --password-stdin; then
        log "GHCR login failed. Jupyter is running, but Docker Compose startup was skipped."
        return 1
      fi
    else
      log "GHCR credentials are not set; assuming the GHCR images are public or Docker is already authenticated."
    fi

    log "Pulling prebuilt GHCR app images."
    if ! docker_cmd compose --env-file "${REPO_DIR}/.env.launchable" "${compose_files[@]}" pull; then
      log "GHCR image pull failed. Jupyter is running, but Docker Compose startup was skipped."
      return 1
    fi
  else
    log "Authenticating Docker with nvcr.io."
    if ! printf '%s' "${NGC_API_KEY}" | docker_cmd login nvcr.io -u '$oauthtoken' --password-stdin; then
      log "Docker login failed. Jupyter is running, but Docker Compose startup was skipped."
      return 1
    fi
  fi

  log "Starting the hosted-NIM Docker Compose stack with CPU Milvus."
  if ! docker_cmd compose --env-file "${REPO_DIR}/.env.launchable" \
    "${compose_files[@]}" \
    "${compose_up_args[@]}"; then
    log "Docker Compose startup failed. Check ${LOG_FILE} and Docker logs for details."
    return 1
  fi

  docker_cmd compose --env-file "${REPO_DIR}/.env.launchable" \
    "${compose_files[@]}" \
    ps || true
}

main() {
  log "Starting NVIDIA Brev Launchable setup."
  stop_influxdb_if_present
  if ! resolve_repo_dir; then
    log "Repository setup failed. Jupyter will still be started for troubleshooting."
    ensure_python_tools
    start_jupyter
    log "Startup incomplete. Once the repo is available, rerun: REPO_DIR=/path/to/ai-virtual-assistant ${SCRIPT_DIR}/startup.sh"
    return 0
  fi
  ensure_python_tools
  start_jupyter
  ensure_docker
  if ! start_compose_stack; then
    log "The Docker Compose stack is not running yet. Jupyter remains available for manual setup."
  fi
  log "Startup complete. Jupyter: port 8889. UI: port 3001 when Docker Compose services are healthy."
}

main "$@"
