#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash launchpad/prepare-launchpad-instance.sh [options] --api-key <temporary-ngc-personal-key>

Automates the repetitive LaunchPad staff setup steps after the repository has
already been cloned or refreshed.

Options:
  --api-key KEY              Temporary NVIDIA/NGC personal API key for this lab.
  --ngc-api-key KEY          Alias for --api-key.
  --nvidia-api-key KEY       Alias for --api-key.
  --warm                     Start the full stack once to warm local NIM assets.
  --stop-after-warm          Stop the stack after warm-up succeeds.
  --skip-pull                Skip docker compose pull.
  --skip-manuals             Skip sample manual download.
  --skip-kernel              Skip AIVA LaunchPad kernel setup.
  --timeout SECONDS          Per-service warm-up timeout. Default: 3600.
  -h, --help                 Show this help.

Environment:
  NGC_API_KEY                Used when --api-key is omitted.
  LAB_NGC_API_KEY            Used when --api-key and NGC_API_KEY are omitted.
  AIVA_BUILD_LAUNCHPAD_UI    Set to 1 to rebuild the LaunchPad UI locally.

Notes:
  The LaunchPad path uses local NIM containers, so the supplied key is written
  to .env.launchpad as NGC_API_KEY. NVIDIA_API_KEY remains local-nim.
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

wait_for_url() {
  local name="$1"
  local url="$2"
  local timeout="$3"
  local start
  local now

  start="$(date +%s)"
  printf 'Waiting for %s at %s\n' "${name}" "${url}"

  until curl -fsS "${url}" >/dev/null 2>&1; do
    now="$(date +%s)"
    if (( now - start > timeout )); then
      printf 'Timed out waiting for %s after %s seconds.\n' "${name}" "${timeout}" >&2
      return 1
    fi
    sleep 15
  done

  printf '%s is ready.\n' "${name}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

API_KEY="${NGC_API_KEY:-${LAB_NGC_API_KEY:-}}"
WARM_STACK=0
STOP_AFTER_WARM=0
SKIP_PULL=0
SKIP_MANUALS=0
SKIP_KERNEL=0
HEALTH_TIMEOUT=3600

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key|--ngc-api-key|--nvidia-api-key)
      [[ $# -ge 2 ]] || die "$1 requires a value."
      API_KEY="$2"
      shift 2
      ;;
    --warm|--warm-stack)
      WARM_STACK=1
      shift
      ;;
    --stop-after-warm)
      WARM_STACK=1
      STOP_AFTER_WARM=1
      shift
      ;;
    --skip-pull)
      SKIP_PULL=1
      shift
      ;;
    --skip-manuals)
      SKIP_MANUALS=1
      shift
      ;;
    --skip-kernel)
      SKIP_KERNEL=1
      shift
      ;;
    --timeout)
      [[ $# -ge 2 ]] || die "--timeout requires a value."
      HEALTH_TIMEOUT="$2"
      [[ "${HEALTH_TIMEOUT}" =~ ^[0-9]+$ ]] || die "--timeout must be an integer number of seconds."
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

if [[ -z "${API_KEY}" ]]; then
  read -rsp "Temporary NVIDIA/NGC personal API key: " API_KEY
  printf '\n'
fi

[[ -n "${API_KEY}" ]] || die "A temporary NVIDIA/NGC personal API key is required."
[[ "${API_KEY}" != "<paste-ngc-api-key>" ]] || die "Replace the placeholder API key before running setup."

require_command awk
require_command bash
require_command curl
require_command docker

cd "${REPO_ROOT}"

[[ -f "deploy/ai_virtual_assistant_notebook_launchpad.ipynb" ]] || die "Missing deploy/ai_virtual_assistant_notebook_launchpad.ipynb"
[[ -f "notebooks/ingest_data.ipynb" ]] || die "Missing notebooks/ingest_data.ipynb"
[[ -f "launchpad/.env.example" ]] || die "Missing launchpad/.env.example"

COMPOSE_CMD=(
  docker compose
  --env-file .env.launchpad
  -f deploy/compose/docker-compose.yaml
  -f deploy/compose/docker-compose.ghcr.yaml
  -f launchpad/docker-compose.launchpad.yaml
  --profile local-nim
)

log "Copying LaunchPad deployment notebook into notebooks/"
cp deploy/ai_virtual_assistant_notebook_launchpad.ipynb \
  notebooks/ai_virtual_assistant_notebook_launchpad.ipynb

if (( SKIP_KERNEL == 0 )); then
  log "Preparing AIVA LaunchPad notebook kernel"
  bash launchpad/setup-notebook-kernel.sh
else
  log "Skipping notebook kernel setup"
fi

log "Writing .env.launchpad"
tmp_env="$(mktemp .env.launchpad.XXXXXX)"
awk -v key="${API_KEY}" '
  BEGIN { replaced = 0 }
  /^NGC_API_KEY=/ {
    print "NGC_API_KEY=" key
    replaced = 1
    next
  }
  { print }
  END {
    if (!replaced) {
      print "NGC_API_KEY=" key
    }
  }
' launchpad/.env.example > "${tmp_env}"
mv "${tmp_env}" .env.launchpad
chmod 600 .env.launchpad
mkdir -p "${HOME}/.cache/nim"

log "Authenticating Docker to nvcr.io"
printf '%s' "${API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin

log "Validating Docker Compose configuration"
"${COMPOSE_CMD[@]}" config >/dev/null

if (( SKIP_PULL == 0 )); then
  log "Pulling missing Docker images"
  "${COMPOSE_CMD[@]}" pull --policy missing
else
  log "Skipping Docker image pull"
fi

if (( WARM_STACK == 1 )); then
  log "Starting the full stack to warm local NIM assets"
  if [[ "${AIVA_BUILD_LAUNCHPAD_UI:-0}" == "1" ]]; then
    bash launchpad/build-launchpad-ui.sh
  fi
  "${COMPOSE_CMD[@]}" up -d --no-build

  log "Waiting for warm-up health checks"
  wait_for_url "Nemotron 3 Nano" "http://127.0.0.1:8000/v1/health/ready" "${HEALTH_TIMEOUT}"
  wait_for_url "Embedding NIM" "http://127.0.0.1:9080/v1/health/ready" "${HEALTH_TIMEOUT}"
  wait_for_url "Reranking NIM" "http://127.0.0.1:1976/v1/health/ready" "${HEALTH_TIMEOUT}"
  wait_for_url "GPU Milvus" "http://127.0.0.1:9091/healthz" "${HEALTH_TIMEOUT}"
  wait_for_url "Unstructured retriever" "http://127.0.0.1:18086/health" "${HEALTH_TIMEOUT}"

  "${COMPOSE_CMD[@]}" ps

  if (( STOP_AFTER_WARM == 1 )); then
    log "Stopping the stack after warm-up"
    "${COMPOSE_CMD[@]}" down
  fi
else
  log "Skipping full-stack warm-up"
fi

if (( SKIP_MANUALS == 0 )); then
  log "Downloading sample manuals"
  bash data/download.sh data/list_manuals.txt
else
  log "Skipping sample manual download"
fi

log "Prepared LaunchPad instance"
printf '%s\n' \
  "Participant notebook: notebooks/ai_virtual_assistant_notebook_launchpad.ipynb" \
  "Next notebook: notebooks/ingest_data.ipynb" \
  "Kernel: AIVA LaunchPad" \
  "UI port after startup: 3001"
