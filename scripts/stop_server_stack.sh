#!/usr/bin/env bash
# Stop the server stack started by run_server_stack.sh.
# Usage:
#   ./scripts/stop_server_stack.sh             # stop containers
#   ./scripts/stop_server_stack.sh --volumes   # also drop named volumes (db_data)
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

EXTRA=()
if [[ "${1:-}" == "--volumes" ]]; then
  EXTRA+=(--volumes)
fi

HOST_DASH_PID_FILE="${ROOT}/.dashboard_host.pid"

echo "Stopping services: db migrate server chartgen dashboard"
${COMPOSE_BIN} -f docker-compose.yml down "${EXTRA[@]}"

# Stop host-run dashboard if present
if [[ -f "${HOST_DASH_PID_FILE}" ]]; then
  PID="$(cat "${HOST_DASH_PID_FILE}")"
  if kill -0 "${PID}" >/dev/null 2>&1; then
    echo "Stopping host dashboard (PID ${PID})"
    kill "${PID}" >/dev/null 2>&1 || true
  fi
  rm -f "${HOST_DASH_PID_FILE}"
fi
