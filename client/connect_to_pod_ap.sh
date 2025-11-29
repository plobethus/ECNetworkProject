#!/usr/bin/env bash
# Connect a Raspberry Pi client (podOne/podTwo/podThree) to the podServer Wi-Fi AP
# and start the Python metrics sender once connected.
# Usage: sudo ./connect_to_pod_ap.sh
# Tunables (env vars):
#   SSID, PSK, WLAN_IFACE, SERVER_IP, CONFIG_PATH, NODE_ID, START_METRICS,
#   SCAN_RETRIES, SCAN_DELAY_SEC, VENV_DIR, INTERVAL_SECONDS, PING_TARGET,
#   SKIP_PIP, PIP_FIND_LINKS

set -euo pipefail

SSID="${SSID:-podNet}"
PSK="${PSK:-podPass123}"
WLAN_IFACE="${WLAN_IFACE:-wlan0}"
SERVER_IP="${SERVER_IP:-10.42.0.1}"
CONFIG_PATH="${CONFIG_PATH:-$(cd "$(dirname "$0")" && pwd)/config.json}"
NODE_ID="${NODE_ID:-$(hostname)}"
START_METRICS="${START_METRICS:-1}"
SCAN_RETRIES="${SCAN_RETRIES:-6}"
SCAN_DELAY_SEC="${SCAN_DELAY_SEC:-3}"
VENV_DIR="${VENV_DIR:-$(cd "$(dirname "$0")/.." && pwd)/client/.venv}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-}"
PING_TARGET="${PING_TARGET:-${SERVER_IP}}"
SKIP_PIP="${SKIP_PIP:-0}"
PIP_FIND_LINKS="${PIP_FIND_LINKS:-}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Connect to podServer AP ==="
echo "SSID: ${SSID}"
echo "Node ID: ${NODE_ID}"
echo "Server IP for gRPC/iPerf: ${SERVER_IP}"

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root (use sudo)." >&2
  exit 1
fi

if ! command -v iw >/dev/null 2>&1; then
  echo "The 'iw' tool is missing. Install it with: sudo apt-get install -y iw" >&2
  exit 1
fi

echo "[0/4] Ensuring Python deps (grpc) are installed..."
if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi
# shellcheck disable=SC1090
source "${VENV_DIR}/bin/activate"
if ! python - <<'PY' >/dev/null 2>&1
import importlib.util, sys
sys.exit(0 if importlib.util.find_spec("grpc") else 1)
PY
then
  if [[ "${SKIP_PIP}" == "1" ]]; then
    echo "Dependencies missing (grpc). SKIP_PIP=1 set; install requirements before rerunning." >&2
    exit 1
  fi
  pip install --upgrade pip --retries 1 --timeout 10
  if [[ -n "${PIP_FIND_LINKS}" ]]; then
    pip install --no-index --find-links "${PIP_FIND_LINKS}" -r "${PROJECT_ROOT}/client/requirements.txt"
  else
    pip install --retries 1 --timeout 10 -r "${PROJECT_ROOT}/client/requirements.txt"
  fi
fi

echo "[1/4] Scanning for SSID ${SSID} on ${WLAN_IFACE} (retries=${SCAN_RETRIES}, delay=${SCAN_DELAY_SEC}s)..."
found=0
for attempt in $(seq 1 "${SCAN_RETRIES}"); do
  scan_out="$(iw dev "${WLAN_IFACE}" scan 2>/dev/null || true)"
  lc_ssid="$(echo "${SSID}" | tr '[:upper:]' '[:lower:]')"
  seen_list="$(echo "${scan_out}" | sed -n 's/^[[:space:]]*SSID:[[:space:]]*//Ip' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]*$//' )"
  if echo "${seen_list}" | grep -Fxq "${lc_ssid}"; then
    echo "  found ${SSID} on attempt ${attempt}"
    found=1
    break
  fi
  seen="$(echo "${scan_out}" | grep -i 'SSID:' | head -n 6 | tr '\n' ';' | sed 's/;/, /g')"
  echo "  attempt ${attempt}/${SCAN_RETRIES}: not found; nearby: ${seen}"
  echo "  sleeping ${SCAN_DELAY_SEC}s..."
  sleep "${SCAN_DELAY_SEC}"
done

if [[ "${found}" -ne 1 ]]; then
  echo "SSID ${SSID} not found after ${SCAN_RETRIES} attempts. Is the AP up and nearby?" >&2
  exit 1
fi

echo "[2/4] Writing Wi-Fi credentials to /etc/wpa_supplicant/wpa_supplicant.conf..."
cat <<EOF > /etc/wpa_supplicant/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="${SSID}"
    psk="${PSK}"
    key_mgmt=WPA-PSK
}
EOF

wpa_cli -i "${WLAN_IFACE}" reconfigure >/dev/null 2>&1 \
  || systemctl restart "wpa_supplicant@${WLAN_IFACE}.service" >/dev/null 2>&1 \
  || systemctl restart wpa_supplicant >/dev/null 2>&1 \
  || wpa_supplicant -B -i "${WLAN_IFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf

# Force wpa_supplicant to only use the target network
wpa_cli -i "${WLAN_IFACE}" remove_network all >/dev/null 2>&1 || true
net_id="$(wpa_cli -i "${WLAN_IFACE}" add_network | tr -d '\r')"
if [[ -z "${net_id}" ]]; then
  echo "Failed to add wpa_supplicant network for ${SSID}" >&2
  exit 1
fi
wpa_cli -i "${WLAN_IFACE}" set_network "${net_id}" ssid "\"${SSID}\"" >/dev/null
wpa_cli -i "${WLAN_IFACE}" set_network "${net_id}" psk "\"${PSK}\"" >/dev/null
wpa_cli -i "${WLAN_IFACE}" set_network "${net_id}" key_mgmt WPA-PSK >/dev/null
wpa_cli -i "${WLAN_IFACE}" set_network "${net_id}" priority 10 >/dev/null
wpa_cli -i "${WLAN_IFACE}" enable_network "${net_id}" >/dev/null
wpa_cli -i "${WLAN_IFACE}" select_network "${net_id}" >/dev/null
wpa_cli -i "${WLAN_IFACE}" save_config >/dev/null

# Renew DHCP after selecting network
if command -v dhclient >/dev/null 2>&1; then
  dhclient -r "${WLAN_IFACE}" 2>/dev/null || true
  dhclient "${WLAN_IFACE}" 2>/dev/null || true
elif command -v dhcpcd >/dev/null 2>&1; then
  dhcpcd -k "${WLAN_IFACE}" 2>/dev/null || true
  dhcpcd -n "${WLAN_IFACE}"
else
  echo "Neither dhclient nor dhcpcd found; renew your IP manually." >&2
fi

echo "[2b] Waiting for association on ${WLAN_IFACE}..."
for attempt in $(seq 1 6); do
  if iw dev "${WLAN_IFACE}" link | grep -q "Connected to"; then
    echo "  connected."
    break
  fi
  echo "  waiting... (${attempt}/6)"
  sleep 2
done

current_ip="$(ip -4 addr show "${WLAN_IFACE}" | awk '/inet /{print $2}')"
if [[ "${current_ip}" != 10.42.* ]]; then
  echo "  warning: IP is ${current_ip:-none}, expected 10.42.x.x — renewing DHCP..."
  if command -v dhclient >/dev/null 2>&1; then
    dhclient -r "${WLAN_IFACE}" 2>/dev/null || true
    dhclient "${WLAN_IFACE}" 2>/dev/null || true
  elif command -v dhcpcd >/dev/null 2>&1; then
    dhcpcd -k "${WLAN_IFACE}" 2>/dev/null || true
    dhcpcd -n "${WLAN_IFACE}"
  fi
  sleep 2
  current_ip="$(ip -4 addr show "${WLAN_IFACE}" | awk '/inet /{print $2}')"
fi

if [[ "${current_ip}" != 10.42.* ]]; then
  echo "ERROR: still not on podNet; wlan0 IP is ${current_ip:-none}. Check AP and try again." >&2
  exit 1
fi
echo "  acquired IP ${current_ip}"

echo "[3/4] Updating client/config.json with server IP and node ID..."
export CONFIG_PATH
export SERVER_IP
export NODE_ID
export INTERVAL_SECONDS
export PING_TARGET
python3 - <<'PY'
import json
import os
import pathlib
import sys

config_path = pathlib.Path(os.environ["CONFIG_PATH"])
if not config_path.exists():
    sys.exit(f"Config file {config_path} not found. Expected to be in the project root client directory.")

with config_path.open() as f:
    data = json.load(f)

data["grpc_server_host"] = os.environ["SERVER_IP"]
data["iperf_server_host"] = os.environ["SERVER_IP"]
data["node_id"] = os.environ["NODE_ID"]
data["ping_target"] = os.environ["PING_TARGET"]
interval = os.environ.get("INTERVAL_SECONDS")
if interval:
    try:
        data["interval_seconds"] = int(interval)
    except ValueError:
        print(f"Skipping interval_seconds override (invalid int: {interval})")

config_path.write_text(json.dumps(data, indent=2))
print(f"Wrote updated client config to {config_path}")
PY

echo "[4/4] Bringing up metrics sender..."
if [[ "${START_METRICS}" == "1" ]]; then
  cd "${PROJECT_ROOT}"
  export PYTHONPATH="${PROJECT_ROOT}:${PROJECT_ROOT}/client"

  # Reuse the same venv prepared earlier; dependencies already verified
  # shellcheck disable=SC1090
  source "${VENV_DIR}/bin/activate"

  sudo -u "${SUDO_USER:-$(whoami)}" env PYTHONPATH="${PYTHONPATH}" VIRTUAL_ENV="${VENV_DIR}" PATH="${VENV_DIR}/bin:${PATH}" python -m client.scheduler
else
  echo "START_METRICS=0, skipping automatic launch."
  echo "Manual run: (cd ${PROJECT_ROOT} && PYTHONPATH=${PROJECT_ROOT}:${PROJECT_ROOT}/client python3 -m client.scheduler)"
fi

