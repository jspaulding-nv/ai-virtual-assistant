#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash launchpad/teardown-launchpad-instance.sh [options]

Stops and resets an NVIDIA LaunchPad lab instance after the AI Virtual
Assistant lab. Run this from anywhere inside the cloned repository.

Default behavior:
  - Stops the LaunchPad Docker Compose stack.
  - Removes bind-mounted service data.
  - Removes notebooks/ai_virtual_assistant_notebook_launchpad.ipynb.
  - Resets .env.launchpad from launchpad/.env.example.
  - Logs out of nvcr.io.

Options:
  --yes                 Run without the confirmation prompt.
  --dry-run             Print actions without changing anything.
  --stop-only           Only stop the Compose stack.
  --keep-data           Do not remove bind-mounted service data.
  --keep-env            Do not reset .env.launchpad or docker logout nvcr.io.
  --keep-notebook       Keep notebooks/ai_virtual_assistant_notebook_launchpad.ipynb.
  --remove-nim-cache    Remove /home/nvidia/.cache/nim or $MODEL_DIRECTORY.
  --remove-images       Remove LaunchPad Compose images and known AIVA legacy/local images.
  --remove-repo         Remove the repository clone last. Implies --remove-nim-cache and --remove-images.
  --env-file FILE       Compose env file. Default: .env.launchpad.
  -h, --help            Show this help.

Examples:
  bash launchpad/teardown-launchpad-instance.sh --yes
  bash launchpad/teardown-launchpad-instance.sh --yes --remove-nim-cache --remove-images
  bash launchpad/teardown-launchpad-instance.sh --yes --remove-nim-cache --remove-images --remove-repo
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

quote_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  quote_cmd "$@"
  if (( DRY_RUN == 0 )); then
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ASSUME_YES=0
DRY_RUN=0
STOP_ONLY=0
KEEP_DATA=0
KEEP_ENV=0
KEEP_NOTEBOOK=0
REMOVE_NIM_CACHE=0
REMOVE_IMAGES=0
REMOVE_REPO=0
ENV_FILE=".env.launchpad"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --stop-only)
      STOP_ONLY=1
      KEEP_DATA=1
      KEEP_ENV=1
      KEEP_NOTEBOOK=1
      shift
      ;;
    --keep-data)
      KEEP_DATA=1
      shift
      ;;
    --keep-env)
      KEEP_ENV=1
      shift
      ;;
    --keep-notebook)
      KEEP_NOTEBOOK=1
      shift
      ;;
    --remove-nim-cache)
      REMOVE_NIM_CACHE=1
      shift
      ;;
    --remove-images)
      REMOVE_IMAGES=1
      shift
      ;;
    --remove-repo)
      REMOVE_REPO=1
      REMOVE_NIM_CACHE=1
      REMOVE_IMAGES=1
      shift
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a value."
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if (( STOP_ONLY == 1 )); then
  KEEP_DATA=1
  KEEP_ENV=1
  KEEP_NOTEBOOK=1
  REMOVE_NIM_CACHE=0
  REMOVE_IMAGES=0
  REMOVE_REPO=0
fi

require_command docker
require_command sort

cd "${REPO_ROOT}"

[[ -f "deploy/compose/docker-compose.yaml" ]] || die "Missing deploy/compose/docker-compose.yaml"
[[ -f "deploy/compose/docker-compose.ghcr.yaml" ]] || die "Missing deploy/compose/docker-compose.ghcr.yaml"
[[ -f "launchpad/docker-compose.launchpad.yaml" ]] || die "Missing launchpad/docker-compose.launchpad.yaml"
[[ -f "launchpad/.env.example" ]] || die "Missing launchpad/.env.example"

COMPOSE_ENV_FILE="${ENV_FILE}"
if [[ ! -f "${COMPOSE_ENV_FILE}" ]]; then
  log "Env file ${COMPOSE_ENV_FILE} was not found; using launchpad/.env.example for Compose metadata"
  COMPOSE_ENV_FILE="launchpad/.env.example"
fi

COMPOSE_CMD=(
  docker compose
  --env-file "${COMPOSE_ENV_FILE}"
  -f deploy/compose/docker-compose.yaml
  -f deploy/compose/docker-compose.ghcr.yaml
  -f launchpad/docker-compose.launchpad.yaml
  --profile local-nim
)

DATA_DIRS=(
  deploy/compose/volumes/postgres_data
  deploy/compose/volumes/pgadmin
  deploy/compose/volumes/redis-data
  deploy/compose/volumes/etcd
  deploy/compose/volumes/minio
  deploy/compose/volumes/milvus
)

MODEL_DIRECTORY="/home/nvidia/.cache/nim"
if [[ -f "${ENV_FILE}" ]]; then
  env_model_dir="$(awk -F= '$1 == "MODEL_DIRECTORY" {print $2}' "${ENV_FILE}" | tail -n 1 | sed 's/^"//; s/"$//')"
  if [[ -n "${env_model_dir}" ]]; then
    MODEL_DIRECTORY="${env_model_dir}"
  fi
fi

IMAGE_LIST_FILE="/tmp/aiva-launchpad-images.txt"

env_value() {
  local key="$1"
  local default_value="$2"
  local value=""

  if [[ -f "${ENV_FILE}" ]]; then
    value="$(awk -F= -v key="${key}" '$1 == key {print $2}' "${ENV_FILE}" | tail -n 1 | sed 's/^"//; s/"$//')"
  fi

  if [[ -z "${value}" && -f "launchpad/.env.example" ]]; then
    value="$(awk -F= -v key="${key}" '$1 == key {print $2}' "launchpad/.env.example" | tail -n 1 | sed 's/^"//; s/"$//')"
  fi

  printf '%s\n' "${value:-${default_value}}"
}

append_if_image_exists() {
  local image="$1"

  if docker image inspect "${image}" >/dev/null 2>&1; then
    printf '%s\n' "${image}" >> "${IMAGE_LIST_FILE}"
  fi
}

append_known_aiva_images() {
  local ghcr_owner
  local ghcr_prefix
  local ghcr_tag
  local launchpad_ui_tag

  ghcr_owner="$(env_value GHCR_OWNER jspaulding-nv)"
  ghcr_prefix="$(env_value GHCR_IMAGE_PREFIX aiva-customer-service)"
  ghcr_tag="$(env_value GHCR_TAG nemotron3-milvus-cpu)"
  launchpad_ui_tag="$(env_value LAUNCHPAD_UI_TAG nemotron3-launchpad-proxy)"

  append_if_image_exists "aiva-customer-service-ui-icon-fallback:local"

  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-agent:${ghcr_tag}"
  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-api-gateway:${ghcr_tag}"
  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-ui:${ghcr_tag}"
  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-ui:${launchpad_ui_tag}"
  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-analytics:${ghcr_tag}"
  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-structured-retriever:${ghcr_tag}"
  append_if_image_exists "ghcr.io/${ghcr_owner}/${ghcr_prefix}-unstructured-retriever:${ghcr_tag}"

  append_if_image_exists "nvcr.io/nvidia/blueprint/aiva-customer-service-agent:1.1.0"
  append_if_image_exists "nvcr.io/nvidia/blueprint/aiva-customer-service-api-gateway:1.1.0"
  append_if_image_exists "nvcr.io/nvidia/blueprint/aiva-customer-service-ui:1.1.0"
  append_if_image_exists "nvcr.io/nvidia/blueprint/aiva-customer-service-analytics:1.1.0"
  append_if_image_exists "nvcr.io/nvidia/blueprint/aiva-customer-service-structured-retriever:1.1.0"
  append_if_image_exists "nvcr.io/nvidia/blueprint/aiva-customer-service-unstructured-retriever:1.1.0"
}

confirm() {
  if (( ASSUME_YES == 1 || DRY_RUN == 1 )); then
    return
  fi

  cat <<EOF
This will reset the LaunchPad lab instance at:
  ${REPO_ROOT}

Actions:
  stop Compose stack: yes
  remove bind-mounted service data: $([[ "${KEEP_DATA}" == 0 ]] && echo yes || echo no)
  reset .env.launchpad and logout nvcr.io: $([[ "${KEEP_ENV}" == 0 ]] && echo yes || echo no)
  remove copied LaunchPad notebook: $([[ "${KEEP_NOTEBOOK}" == 0 ]] && echo yes || echo no)
  remove NIM model cache (${MODEL_DIRECTORY}): $([[ "${REMOVE_NIM_CACHE}" == 1 ]] && echo yes || echo no)
  remove Compose Docker images: $([[ "${REMOVE_IMAGES}" == 1 ]] && echo yes || echo no)
  remove repository clone: $([[ "${REMOVE_REPO}" == 1 ]] && echo yes || echo no)

EOF

  read -r -p "Continue? [y/N] " answer
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
}

collect_compose_images() {
  if (( REMOVE_IMAGES == 0 )); then
    return
  fi

  log "Collecting Docker images referenced by the LaunchPad Compose config"
  if (( DRY_RUN == 1 )); then
    quote_cmd "${COMPOSE_CMD[@]}" config --images
    printf '+ collect known AIVA legacy/local images if present\n'
    return
  fi

  "${COMPOSE_CMD[@]}" config --images | sort -u > "${IMAGE_LIST_FILE}"
  append_known_aiva_images
  sort -u -o "${IMAGE_LIST_FILE}" "${IMAGE_LIST_FILE}"
  cat "${IMAGE_LIST_FILE}"
}

remove_compose_images() {
  if (( REMOVE_IMAGES == 0 )); then
    return
  fi

  log "Removing Docker images referenced by the LaunchPad Compose config"
  if (( DRY_RUN == 1 )); then
    printf '+ xargs -r docker image rm < %q\n' "${IMAGE_LIST_FILE}"
    return
  fi

  xargs -r docker image rm < "${IMAGE_LIST_FILE}" || true
  rm -f "${IMAGE_LIST_FILE}"
}

confirm
collect_compose_images

log "Stopping LaunchPad Compose stack"
run "${COMPOSE_CMD[@]}" down --remove-orphans

if (( KEEP_DATA == 0 )); then
  log "Removing bind-mounted service data"
  run sudo rm -rf "${DATA_DIRS[@]}"
fi

if (( KEEP_NOTEBOOK == 0 )); then
  log "Removing copied participant LaunchPad notebook"
  run rm -f notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
fi

if (( KEEP_ENV == 0 )); then
  log "Resetting .env.launchpad and logging out of nvcr.io"
  run cp launchpad/.env.example .env.launchpad
  run chmod 600 .env.launchpad
  run docker logout nvcr.io
fi

if (( REMOVE_NIM_CACHE == 1 )); then
  log "Removing NIM model cache"
  run rm -rf "${MODEL_DIRECTORY}"
fi

remove_compose_images

log "Verifying reset"
run docker ps --format 'table {{.Names}}\t{{.Status}}'
run test -f deploy/ai_virtual_assistant_notebook_launchpad.ipynb
run test -f notebooks/ingest_data.ipynb
if (( KEEP_NOTEBOOK == 0 )); then
  run test ! -f notebooks/ai_virtual_assistant_notebook_launchpad.ipynb
fi

if (( REMOVE_REPO == 1 )); then
  log "Removing repository clone"
  cd "${HOME}"
  run sudo rm -rf "${REPO_ROOT}"
fi

log "LaunchPad teardown complete"
