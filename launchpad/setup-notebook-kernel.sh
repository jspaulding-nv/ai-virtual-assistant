#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf '%s\n' \
    "Usage:" \
    "  bash launchpad/setup-notebook-kernel.sh" \
    "" \
    "Creates a repo-local notebook virtual environment, installs the ingestion" \
    "notebook dependencies, and registers the AIVA LaunchPad Jupyter kernel." \
    "" \
    "Environment:" \
    "  PYTHON_BIN                    Python executable to seed the venv. Defaults to python3." \
    "  VENV_DIR                      Virtual environment path. Defaults to .venv-notebooks." \
    "  KERNEL_NAME                   Jupyter kernel name. Defaults to aiva-launchpad." \
    "  KERNEL_DISPLAY_NAME           Kernel display name. Defaults to AIVA LaunchPad." \
    "  AIVA_INGEST_HOST              Ingestion host. Defaults to localhost." \
    "  AIVA_UNSTRUCTURED_DATA_PORT   LaunchPad unstructured retriever host port. Defaults to 18086."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-${REPO_ROOT}/.venv-notebooks}"
KERNEL_NAME="${KERNEL_NAME:-aiva-launchpad}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-AIVA LaunchPad}"
AIVA_INGEST_HOST="${AIVA_INGEST_HOST:-localhost}"
AIVA_UNSTRUCTURED_DATA_PORT="${AIVA_UNSTRUCTURED_DATA_PORT:-18086}"
VENV_PYTHON="${VENV_DIR}/bin/python"
REQUIREMENTS_FILE="${REPO_ROOT}/src/ingest_service/requirements.txt"

cd "${REPO_ROOT}"

"${PYTHON_BIN}" -m venv "${VENV_DIR}"
"${VENV_PYTHON}" -m pip install --upgrade pip
"${VENV_PYTHON}" -m pip install ipykernel -r "${REQUIREMENTS_FILE}"
"${VENV_PYTHON}" -m ipykernel install \
  --user \
  --name "${KERNEL_NAME}" \
  --display-name "${KERNEL_DISPLAY_NAME}"

KERNEL_JSON="${HOME}/.local/share/jupyter/kernels/${KERNEL_NAME}/kernel.json"

export REPO_ROOT
export VENV_PYTHON
export KERNEL_JSON
export AIVA_INGEST_HOST
export AIVA_UNSTRUCTURED_DATA_PORT

"${VENV_PYTHON}" - <<'PY'
import json
import os
from pathlib import Path

kernel_json = Path(os.environ["KERNEL_JSON"])
kernel_data = json.loads(kernel_json.read_text())
kernel_env = kernel_data.setdefault("env", {})
kernel_env["AIVA_INGEST_HOST"] = os.environ["AIVA_INGEST_HOST"]
kernel_env["AIVA_UNSTRUCTURED_DATA_PORT"] = os.environ["AIVA_UNSTRUCTURED_DATA_PORT"]
kernel_json.write_text(json.dumps(kernel_data, indent=2) + "\n")

settings_path = Path(os.environ["REPO_ROOT"]) / ".vscode" / "settings.json"
settings_path.parent.mkdir(exist_ok=True)

if settings_path.exists():
    try:
        settings_data = json.loads(settings_path.read_text())
    except json.JSONDecodeError:
        settings_data = {}
else:
    settings_data = {}

settings_data["python.defaultInterpreterPath"] = os.environ["VENV_PYTHON"]
settings_data["jupyter.notebookFileRoot"] = "${workspaceFolder}"
settings_path.write_text(json.dumps(settings_data, indent=2) + "\n")
PY

printf 'Registered Jupyter kernel: %s (%s)\n' "${KERNEL_DISPLAY_NAME}" "${KERNEL_NAME}"
printf 'Kernel Python: %s\n' "${VENV_PYTHON}"
printf 'Notebook ingestion endpoint: http://%s:%s\n' \
  "${AIVA_INGEST_HOST}" \
  "${AIVA_UNSTRUCTURED_DATA_PORT}"
