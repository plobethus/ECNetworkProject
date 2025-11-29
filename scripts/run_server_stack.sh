#!/usr/bin/env bash
# Start the minimal server stack: db + migrate + server + chartgen + dashboard.
# Usage:
#   ./scripts/run_server_stack.sh          # up with existing images
#   ./scripts/run_server_stack.sh --build  # build images first
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
if [[ "${1:-}" == "--build" ]]; then
  BUILD_FLAG=(--build)
fi

echo "Starting services: ${STACK_SERVICES}"
${COMPOSE_BIN} -f docker-compose.yml up -d "${BUILD_FLAG[@]}" ${STACK_SERVICES}

echo "Tail logs with:"
echo "  ${COMPOSE_BIN} logs -f ${STACK_SERVICES}"
