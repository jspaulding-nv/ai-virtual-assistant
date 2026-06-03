#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf '%s\n' \
    "Usage:" \
    "  bash launchpad/setup-notebook-kernel.sh" \
    "" \
    "Installs the ingestion notebook dependencies and registers the AIVA" \
    "LaunchPad Jupyter kernel. Uses a repo-local venv when Python venv support" \
    "is available, otherwise falls back to a user-local Python install." \
    "" \
    "Environment:" \
    "  PYTHON_BIN                    Python executable to use. Defaults to python3." \
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
SYSTEM_PYTHON="$(command -v "${PYTHON_BIN}")"
REQUIREMENTS_FILE="${REPO_ROOT}/src/ingest_service/requirements.txt"

cd "${REPO_ROOT}"

KERNEL_PYTHON=""

if "${SYSTEM_PYTHON}" - <<'PY' >/dev/null 2>&1 && "${SYSTEM_PYTHON}" -m venv "${VENV_DIR}"; then
import ensurepip
PY
  KERNEL_PYTHON="${VENV_PYTHON}"
  "${KERNEL_PYTHON}" -m pip install --upgrade pip
  "${KERNEL_PYTHON}" -m pip install ipykernel -r "${REQUIREMENTS_FILE}"
else
  printf '%s\n' \
    "Python venv support is unavailable. Falling back to a user-local Python install." \
    "To force a venv later, install python3.12-venv and rerun this script."

  KERNEL_PYTHON="${SYSTEM_PYTHON}"
  PIP_SYSTEM_FLAGS=()
  if "${KERNEL_PYTHON}" -m pip install --help 2>/dev/null | grep -q -- "--break-system-packages"; then
    PIP_SYSTEM_FLAGS+=(--break-system-packages)
  fi

  "${KERNEL_PYTHON}" -m pip install \
    --user \
    "${PIP_SYSTEM_FLAGS[@]}" \
    ipykernel \
    -r "${REQUIREMENTS_FILE}"
fi

"${KERNEL_PYTHON}" -m ipykernel install \
  --user \
  --name "${KERNEL_NAME}" \
  --display-name "${KERNEL_DISPLAY_NAME}"

KERNEL_JSON="${HOME}/.local/share/jupyter/kernels/${KERNEL_NAME}/kernel.json"

export REPO_ROOT
export KERNEL_PYTHON
export KERNEL_JSON
export KERNEL_NAME
export KERNEL_DISPLAY_NAME
export AIVA_INGEST_HOST
export AIVA_UNSTRUCTURED_DATA_PORT

"${KERNEL_PYTHON}" - <<'PY'
import json
import os
import subprocess
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

settings_data["python.defaultInterpreterPath"] = os.environ["KERNEL_PYTHON"]
settings_data["jupyter.notebookFileRoot"] = "${workspaceFolder}"
settings_path.write_text(json.dumps(settings_data, indent=2) + "\n")

try:
    python_version = subprocess.check_output(
        [os.environ["KERNEL_PYTHON"], "-c", "import platform; print(platform.python_version())"],
        text=True,
    ).strip()
except Exception:
    python_version = ""

for notebook_path in [
    Path(os.environ["REPO_ROOT"]) / "notebooks" / "ai_virtual_assistant_notebook_launchpad.ipynb",
]:
    if not notebook_path.exists():
        continue

    notebook = json.loads(notebook_path.read_text())
    metadata = notebook.setdefault("metadata", {})
    metadata["kernelspec"] = {
        "display_name": os.environ["KERNEL_DISPLAY_NAME"],
        "language": "python",
        "name": os.environ["KERNEL_NAME"],
    }
    language_info = metadata.setdefault("language_info", {})
    language_info.setdefault("name", "python")
    language_info.setdefault("codemirror_mode", {"name": "ipython", "version": 3})
    language_info.setdefault("file_extension", ".py")
    language_info.setdefault("mimetype", "text/x-python")
    language_info.setdefault("pygments_lexer", "ipython3")
    if python_version:
        language_info["version"] = python_version

    notebook_path.write_text(json.dumps(notebook, indent=2) + "\n")
PY

printf 'Registered Jupyter kernel: %s (%s)\n' "${KERNEL_DISPLAY_NAME}" "${KERNEL_NAME}"
printf 'Kernel Python: %s\n' "${KERNEL_PYTHON}"
printf 'Kernel spec: %s\n' "${KERNEL_JSON}"
printf '%s\n' \
  "Stamped copied LaunchPad notebook metadata for this kernel when the notebook exists."
printf 'Notebook ingestion endpoint: http://%s:%s\n' \
  "${AIVA_INGEST_HOST}" \
  "${AIVA_UNSTRUCTURED_DATA_PORT}"
printf '%s\n' \
  "In VS Code, choose ${KERNEL_DISPLAY_NAME}; it may appear under Jupyter Kernel... or Python Environments...."
printf '%s\n' \
  "If VS Code does not show this kernel immediately, reload the browser tab or run Developer: Reload Window."
