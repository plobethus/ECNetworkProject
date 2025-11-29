#!/usr/bin/env bash
# Start the pod metrics agent on a Raspberry Pi client.
# - Optionally updates client/config.json (SERVER_IP, NODE_ID, PING_TARGET, INTERVAL_SECONDS).
# - Ensures Python deps are installed (venv) and runs client.scheduler.
# Requirements: python3, pip, iperf3, ping.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${ROOT}/client/config.json}"
VENV_DIR="${VENV_DIR:-${ROOT}/client/.venv}"

SERVER_IP="${SERVER_IP:-}"
NODE_ID="${NODE_ID:-}"
PING_TARGET="${PING_TARGET:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

if ! command -v iperf3 >/dev/null 2>&1; then
  echo "iperf3 is required (sudo apt-get install -y iperf3)" >&2
  exit 1
fi

if ! command -v ping >/dev/null 2>&1; then
  echo "ping is required (sudo apt-get install -y iputils-ping)" >&2
  exit 1
fi

echo "Using config at ${CONFIG_PATH}"

# Optionally mutate config.json with provided env overrides
if [[ -n "${SERVER_IP}${NODE_ID}${PING_TARGET}${INTERVAL_SECONDS}" ]]; then
  python3 - <<'PY'
import json, os, sys, pathlib

config_path = pathlib.Path(os.environ["CONFIG_PATH"])
data = json.loads(config_path.read_text())

def maybe_set(key, env):
    val = os.environ.get(env)
    if val:
        data[key] = int(val) if key == "interval_seconds" else val

maybe_set("grpc_server_host", "SERVER_IP")
maybe_set("iperf_server_host", "SERVER_IP")
maybe_set("node_id", "NODE_ID")
maybe_set("ping_target", "PING_TARGET")
maybe_set("interval_seconds", "INTERVAL_SECONDS")

config_path.write_text(json.dumps(data, indent=2))
print(f"Updated config.json with overrides: {config_path}")
PY
fi

# Create/activate venv and install deps
if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi
source "${VENV_DIR}/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "${ROOT}/client/requirements.txt"

export PYTHONPATH="${ROOT}"
cd "${ROOT}"
echo "Starting metrics scheduler..."
exec python -m client.scheduler
