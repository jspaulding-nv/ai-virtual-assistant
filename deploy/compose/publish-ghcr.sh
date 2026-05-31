#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  GHCR_USER=<github-user> GHCR_TOKEN=<token> ./deploy/compose/publish-ghcr.sh [options]

Options:
  --prune-all-images  Remove all unused local Docker images and build cache before rebuilding.
  --skip-health       Do not wait for service health endpoints before pushing.
  --skip-push         Rebuild and start the stack, but do not push images to GHCR.
  -h, --help          Show this help.

Environment:
  ENV_FILE            Compose env file. Defaults to .env.launchable, then .env.
  GHCR_OWNER          GHCR owner/org. Defaults to the git remote owner, then jspaulding-nv.
  GHCR_IMAGE_PREFIX   Image prefix. Defaults to aiva-customer-service.
  GHCR_TAG            Image tag. Defaults to the current git branch, then nemotron3-milvus-cpu.
  HEALTH_TIMEOUT      Health wait timeout in seconds. Defaults to 600.
USAGE
}

PRUNE_ALL_IMAGES=0
SKIP_HEALTH=0
SKIP_PUSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prune-all-images)
      PRUNE_ALL_IMAGES=1
      shift
      ;;
    --skip-health)
      SKIP_HEALTH=1
      shift
      ;;
    --skip-push)
      SKIP_PUSH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

if [[ -z "${ENV_FILE:-}" ]]; then
  if [[ -f ".env.launchable" ]]; then
    ENV_FILE=".env.launchable"
  elif [[ -f ".env" ]]; then
    ENV_FILE=".env"
  else
    echo "No .env.launchable or .env file found. Set ENV_FILE to the Compose env file." >&2
    exit 1
  fi
fi

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "Env file not found: ${ENV_FILE}" >&2
  exit 1
fi

if [[ -z "${NVIDIA_API_KEY:-}" ]]; then
  echo "NVIDIA_API_KEY must be set in ${ENV_FILE} or the environment for the hosted NIM smoke test." >&2
  exit 1
fi

host_arch="$(uname -m)"
if [[ "${host_arch}" != "x86_64" && "${ALLOW_NON_AMD64:-0}" != "1" ]]; then
  echo "This publish path is intended for linux/amd64 images. Current host architecture: ${host_arch}." >&2
  echo "Run it on the x86_64 Brev VM, or set ALLOW_NON_AMD64=1 if you intentionally want this architecture." >&2
  exit 1
fi

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "Docker is not available to this user. Start Docker or add the user to the docker group." >&2
  exit 1
fi

remote_owner="$(git config --get remote.origin.url 2>/dev/null | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$#\1#')"
if [[ "${remote_owner}" == *"/"* || "${remote_owner}" == *":"* ]]; then
  remote_owner=""
fi
branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

GHCR_OWNER="${GHCR_OWNER:-${remote_owner:-jspaulding-nv}}"
GHCR_IMAGE_PREFIX="${GHCR_IMAGE_PREFIX:-aiva-customer-service}"
GHCR_TAG="${GHCR_TAG:-${branch_name:-nemotron3-milvus-cpu}}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-600}"
COMPOSE_FILE="${COMPOSE_FILE:-deploy/compose/docker-compose.yaml}"

export UID
export GID="$(id -g)"

compose() {
  "${DOCKER[@]}" compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

require_push_credentials() {
  if [[ "${SKIP_PUSH}" -eq 1 ]]; then
    return
  fi

  if [[ -z "${GHCR_USER:-}" || -z "${GHCR_TOKEN:-}" ]]; then
    echo "Set GHCR_USER and GHCR_TOKEN, or pass --skip-push for a local rebuild only." >&2
    exit 1
  fi
}

login_registries() {
  if [[ -n "${NGC_API_KEY:-}" ]]; then
    printf '%s' "${NGC_API_KEY}" | "${DOCKER[@]}" login nvcr.io -u '$oauthtoken' --password-stdin >/dev/null
    echo "Logged in to nvcr.io."
  else
    echo "NGC_API_KEY is not set; continuing without nvcr.io login."
  fi

  if [[ "${SKIP_PUSH}" -eq 0 ]]; then
    printf '%s' "${GHCR_TOKEN}" | "${DOCKER[@]}" login ghcr.io -u "${GHCR_USER}" --password-stdin >/dev/null
    echo "Logged in to ghcr.io as ${GHCR_USER}."
  fi
}

wait_for_url() {
  local name="$1"
  local url="$2"
  local deadline=$((SECONDS + HEALTH_TIMEOUT))

  printf 'Waiting for %s at %s' "${name}" "${url}"
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo
      echo "Timed out waiting for ${name}." >&2
      compose ps >&2 || true
      compose logs --tail=120 >&2 || true
      exit 1
    fi
    printf '.'
    sleep 5
  done
  echo " ok"
}

smoke_test() {
  if [[ "${SKIP_HEALTH}" -eq 1 ]]; then
    echo "Skipping health checks."
    return
  fi

  wait_for_url "Milvus" "http://localhost:9091/healthz"
  wait_for_url "unstructured retriever" "http://localhost:8086/health"
  wait_for_url "structured retriever" "http://localhost:8087/health"
  wait_for_url "agent" "http://localhost:8081/health"
  wait_for_url "analytics" "http://localhost:8082/health"
  wait_for_url "API gateway" "http://localhost:9000/agent/health"
  wait_for_url "frontend" "http://localhost:3001"
}

declare -A LOCAL_IMAGES=(
  [agent-chain-server]="nvcr.io/nvidia/blueprint/aiva-customer-service-agent:1.1.0"
  [api-gateway-server]="nvcr.io/nvidia/blueprint/aiva-customer-service-api-gateway:1.1.0"
  [agent-frontend]="aiva-customer-service-ui-icon-fallback:local"
  [analytics-server]="nvcr.io/nvidia/blueprint/aiva-customer-service-analytics:1.1.0"
  [structured-retriever]="nvcr.io/nvidia/blueprint/aiva-customer-service-structured-retriever:1.1.0"
  [unstructured-retriever]="nvcr.io/nvidia/blueprint/aiva-customer-service-unstructured-retriever:1.1.0"
)

declare -A GHCR_IMAGES=(
  [agent-chain-server]="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-agent:${GHCR_TAG}"
  [api-gateway-server]="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-api-gateway:${GHCR_TAG}"
  [agent-frontend]="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-ui:${GHCR_TAG}"
  [analytics-server]="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-analytics:${GHCR_TAG}"
  [structured-retriever]="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-structured-retriever:${GHCR_TAG}"
  [unstructured-retriever]="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-unstructured-retriever:${GHCR_TAG}"
)

SERVICES=(
  agent-chain-server
  api-gateway-server
  agent-frontend
  analytics-server
  structured-retriever
  unstructured-retriever
)

require_push_credentials
login_registries

echo "Stopping Docker Compose stack."
compose down --remove-orphans

if [[ "${PRUNE_ALL_IMAGES}" -eq 1 ]]; then
  echo "Pruning unused Docker images and build cache."
  "${DOCKER[@]}" image prune -af
  "${DOCKER[@]}" builder prune -af
else
  echo "Removing project images. Pass --prune-all-images to clear all unused local images and build cache."
  for service in "${SERVICES[@]}"; do
    "${DOCKER[@]}" image rm -f "${LOCAL_IMAGES[${service}]}" "${GHCR_IMAGES[${service}]}" >/dev/null 2>&1 || true
  done
fi

echo "Building app images from scratch for ${GHCR_TAG}."
compose build --pull --no-cache "${SERVICES[@]}"

echo "Starting Compose stack."
compose up -d
smoke_test

if [[ "${SKIP_PUSH}" -eq 1 ]]; then
  echo "Skipping GHCR push."
  exit 0
fi

echo "Tagging and pushing GHCR images."
for service in "${SERVICES[@]}"; do
  "${DOCKER[@]}" tag "${LOCAL_IMAGES[${service}]}" "${GHCR_IMAGES[${service}]}"
  "${DOCKER[@]}" push "${GHCR_IMAGES[${service}]}"
done

cat <<EOF

Published images:
EOF
for service in "${SERVICES[@]}"; do
  echo "  ${service}: ${GHCR_IMAGES[${service}]}"
done

cat <<EOF

Run the prebuilt images with:
  GHCR_OWNER=${GHCR_OWNER} GHCR_TAG=${GHCR_TAG} docker compose --env-file ${ENV_FILE} \\
    -f ${COMPOSE_FILE} -f deploy/compose/docker-compose.ghcr.yaml pull
  GHCR_OWNER=${GHCR_OWNER} GHCR_TAG=${GHCR_TAG} docker compose --env-file ${ENV_FILE} \\
    -f ${COMPOSE_FILE} -f deploy/compose/docker-compose.ghcr.yaml up -d --no-build
EOF
