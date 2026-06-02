#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash launchpad/build-launchpad-ui.sh [--push]

Builds the LaunchPad-specific UI image that supports code-server's
/coder/proxy/3001/ path. The image name is read from .env.launchpad by default:

  ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-ui:${LAUNCHPAD_UI_TAG}

Options:
  --push      Push the image to GHCR after building. Requires GHCR_USER and GHCR_TOKEN.
  -h, --help  Show this help.

Environment:
  ENV_FILE    Compose env file. Defaults to .env.launchpad.
  GHCR_USER   GitHub username for GHCR push.
  GHCR_TOKEN  GitHub token with package write permission for GHCR push.
USAGE
}

PUSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH=1
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
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env.launchpad}"

env_value() {
  local key="$1"
  local default_value="$2"

  if [[ -f "${ENV_FILE}" ]]; then
    local value
    value="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2- || true)"
    value="${value%\"}"
    value="${value#\"}"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return
    fi
  fi

  printf '%s\n' "${default_value}"
}

GHCR_OWNER="$(env_value GHCR_OWNER jspaulding-nv)"
GHCR_IMAGE_PREFIX="$(env_value GHCR_IMAGE_PREFIX aiva-customer-service)"
LAUNCHPAD_UI_TAG="$(env_value LAUNCHPAD_UI_TAG nemotron3-launchpad-proxy)"
NGC_API_KEY="$(env_value NGC_API_KEY "")"
IMAGE="ghcr.io/${GHCR_OWNER}/${GHCR_IMAGE_PREFIX}-ui:${LAUNCHPAD_UI_TAG}"

cd "${REPO_ROOT}"

if [[ -n "${NGC_API_KEY}" && "${NGC_API_KEY}" != "<paste-ngc-api-key>" ]]; then
  printf '%s' "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin
fi

docker build --pull --no-cache \
  -f src/ui/Dockerfile.launchpad \
  -t "${IMAGE}" \
  .

if [[ "${PUSH}" -eq 1 ]]; then
  if [[ -z "${GHCR_USER:-}" || -z "${GHCR_TOKEN:-}" ]]; then
    echo "Set GHCR_USER and GHCR_TOKEN to push ${IMAGE}." >&2
    exit 1
  fi

  printf '%s' "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
  docker push "${IMAGE}"
fi

echo "Built ${IMAGE}"
