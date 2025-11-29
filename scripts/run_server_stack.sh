#!/usr/bin/env bash
# Start the minimal server stack: db + migrate + server + chartgen + dashboard.
# Usage:
#   ./scripts/run_server_stack.sh                # up with existing images
#   ./scripts/run_server_stack.sh --build        # build images first
#   ./scripts/run_server_stack.sh --host-dashboard [--build]
#     ^ starts dashboard on the host (for AP control) instead of in Docker
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPOSE_BIN="docker compose"
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
  else
    echo "docker compose is required." >&2
    exit 1
  fi
fi

STACK_SERVICES="db migrate server chartgen dashboard"
BUILD_FLAG=()
HOST_DASHBOARD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_FLAG=(--build)
      shift
      ;;
    --host-dashboard)
      HOST_DASHBOARD=1
      STACK_SERVICES="db migrate server chartgen"
      shift
      ;;
    *)
      echo "Usage: $0 [--build] [--host-dashboard]" >&2
      exit 1
      ;;
  esac
done

echo "Starting services: ${STACK_SERVICES}"
${COMPOSE_BIN} -f docker-compose.yml up -d "${BUILD_FLAG[@]}" ${STACK_SERVICES}

echo "Tail logs with:"
echo "  ${COMPOSE_BIN} logs -f ${STACK_SERVICES}"

# =======================
# Host dashboard launcher
# =======================
if [[ "${HOST_DASHBOARD}" -eq 1 ]]; then
  HOST_DASH_PID_FILE="${ROOT}/.dashboard_host.pid"
  HOST_DASH_LOG="${ROOT}/dashboard_host.log"
  HOST_DASH_VENV="${ROOT}/.dashboard_venv"

  ensure_py_deps() {
    if [[ ! -d "${HOST_DASH_VENV}" ]]; then
      echo "Creating host dashboard venv at ${HOST_DASH_VENV} ..."
      python3 -m venv "${HOST_DASH_VENV}"
    fi

    PYBIN="${HOST_DASH_VENV}/bin/python"
    PIPBIN="${HOST_DASH_VENV}/bin/pip"

    if "${PYBIN}" - <<'PY'
import importlib.util, sys
mods = ["flask", "psycopg2", "gevent", "gunicorn"]
missing = [m for m in mods if importlib.util.find_spec(m) is None]
sys.exit(0 if not missing else 1)
PY
    then
      return 0
    fi
    echo "Installing host dashboard Python deps into venv ..."
    "${PIPBIN}" install --upgrade pip >/dev/null
    "${PIPBIN}" install flask psycopg2-binary gevent gunicorn >/dev/null
  }

  ensure_py_deps

  if [[ -f "${HOST_DASH_PID_FILE}" ]]; then
    if kill -0 "$(cat "${HOST_DASH_PID_FILE}")" >/dev/null 2>&1; then
      echo "Host dashboard already running (PID $(cat "${HOST_DASH_PID_FILE}"))."
      echo "Log: ${HOST_DASH_LOG}"
      exit 0
    else
      rm -f "${HOST_DASH_PID_FILE}"
    fi
  fi

  # Prefer gunicorn if present; otherwise fall back to python app.py
  PATH="${HOST_DASH_VENV}/bin:${PATH}"
  if command -v gunicorn >/dev/null 2>&1; then
    DASH_CMD=(gunicorn -k gevent --bind 0.0.0.0:8080 dashboard.app:app)
  else
    DASH_CMD=("${HOST_DASH_VENV}/bin/python" -u dashboard/app.py)
  fi

  echo "Starting host dashboard on :8080 (log -> ${HOST_DASH_LOG}) ..."
  AP_SETUP_SCRIPT="${ROOT}/server/setup_wifi_ap.sh" \
  AP_TEARDOWN_SCRIPT="${ROOT}/server/teardown_wifi_ap.sh" \
  AP_USE_SUDO=1 \
  DATABASE_URL="postgresql://admin:admin@localhost:5432/metrics" \
  PYTHONPATH="${ROOT}" \
    "${DASH_CMD[@]}" > "${HOST_DASH_LOG}" 2>&1 &

  DASH_PID=$!
  echo "${DASH_PID}" > "${HOST_DASH_PID_FILE}"
  echo "Host dashboard PID: ${DASH_PID}"
fi
