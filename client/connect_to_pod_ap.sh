#!/usr/bin/env bash
# Connect a Raspberry Pi 3 (podOne/podTwo/podThree) to the podServer Wi-Fi AP
# and start the Python metrics sender once connected.
# Usage: sudo ./connect_to_pod_ap.sh
# Tunables (env vars):
#   SSID, PSK, WLAN_IFACE, SERVER_IP, CONFIG_PATH, NODE_ID, START_METRICS

set -euo pipefail

SSID="${SSID:-podNet}"
PSK="${PSK:-podPass123}"
WLAN_IFACE="${WLAN_IFACE:-wlan0}"
SERVER_IP="${SERVER_IP:-10.42.0.1}"
CONFIG_PATH="${CONFIG_PATH:-$(cd "$(dirname "$0")" && pwd)/config.json}"
NODE_ID="${NODE_ID:-$(hostname)}"
START_METRICS="${START_METRICS:-1}"

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

echo "[1/4] Scanning for SSID ${SSID} on ${WLAN_IFACE}..."
if ! iw dev "${WLAN_IFACE}" scan | grep -q "SSID: ${SSID}"; then
  echo "SSID ${SSID} not found. Is the AP up and nearby?" >&2
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

wpa_cli -i "${WLAN_IFACE}" reconfigure || systemctl restart wpa_supplicant
if command -v dhclient >/dev/null 2>&1; then
  dhclient -r "${WLAN_IFACE}" 2>/dev/null || true
  dhclient "${WLAN_IFACE}" || true
elif command -v dhcpcd >/dev/null 2>&1; then
  dhcpcd -k "${WLAN_IFACE}" 2>/dev/null || true
  dhcpcd -n "${WLAN_IFACE}"
else
  echo "Neither dhclient nor dhcpcd found; renew your IP manually." >&2
fi

echo "[3/4] Updating client/config.json with server IP and node ID..."
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

config_path.write_text(json.dumps(data, indent=2))
print(f"Wrote updated client config to {config_path}")
PY

echo "[4/4] Bringing up metrics sender..."
if [[ "${START_METRICS}" == "1" ]]; then
  PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  cd "${PROJECT_ROOT}"
  export PYTHONPATH="${PROJECT_ROOT}"
  sudo -u "${SUDO_USER:-$(whoami)}" python3 -m client.scheduler
else
  echo "START_METRICS=0, skipping automatic launch."
  echo "Manual run: (cd /path/to/ECNetworkProject && PYTHONPATH=. python3 -m client.scheduler)"
fi
