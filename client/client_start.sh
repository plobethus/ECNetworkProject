#!/bin/bash
set -euo pipefail

SERVER_NAME="${SERVER_NAME:-podServer}"
BT_MAC=""
DOCKER_IMAGE="${DOCKER_IMAGE:-metrics-client:latest}"
SCAN_ATTEMPTS=15

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[FATAL] Missing dependency: $1 (install bluez/bluez-tools/docker)."
        exit 1
    fi
}

install_if_missing() {
    local pkg=$1
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "[INFO] Installing $pkg ..."
        sudo apt-get update -y
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
    fi
}

# Auto-install core Bluetooth tools if missing (Debian/Raspberry Pi OS).
if command -v apt-get >/dev/null 2>&1; then
    # Bluetooth tools
    if ! command -v bt-network >/dev/null 2>&1; then
        install_if_missing bluez
        install_if_missing bluez-tools
        install_if_missing rfkill
    fi

    # DHCP client
    if ! command -v dhclient >/dev/null 2>&1; then
        install_if_missing isc-dhcp-client
    fi

    # ip utility (iproute2)
    if ! command -v ip >/dev/null 2>&1; then
        install_if_missing iproute2
    fi
else
    if ! command -v bt-network >/dev/null 2>&1; then
        echo "[FATAL] bt-network missing and apt-get not available to install bluez-tools."
        exit 1
    fi
    if ! command -v dhclient >/dev/null 2>&1; then
        echo "[FATAL] dhclient missing and apt-get not available to install isc-dhcp-client."
        exit 1
    fi
    if ! command -v ip >/dev/null 2>&1; then
        echo "[FATAL] ip (iproute2) missing and apt-get not available to install it."
        exit 1
    fi
fi

require_cmd bluetoothctl
require_cmd bt-network
require_cmd ip
require_cmd dhclient
require_cmd docker

echo "[INFO] Starting client on host: $(hostname)"
echo "[INFO] Preparing Bluetooth hardware..."

sudo rfkill unblock bluetooth || true
sudo systemctl restart bluetooth || true
sleep 2

echo "[INFO] Powering on hci0..."
sudo hciconfig hci0 up || true

if ! sudo bluetoothctl show | grep -q "Powered: yes"; then
    echo "[WARN] Bluetooth adapter reported as off; powering on via bluetoothctl..."
    sudo bluetoothctl power on || true
fi

if ! sudo bluetoothctl show | grep -q "Powered: yes"; then
    echo "[ERROR] Bluetooth adapter hci0 is not powered."
    exit 1
fi

echo "[INFO] Bluetooth adapter is up."

# -----------------------------------------------------
# 1. Scan for the server
# -----------------------------------------------------
echo "[INFO] Scanning for server named: $SERVER_NAME"

for i in $(seq 1 "$SCAN_ATTEMPTS"); do
    BT_MAC=$(sudo bluetoothctl devices | awk -v name="$SERVER_NAME" '$0 ~ name {print $2; exit}')

    if [ -n "$BT_MAC" ]; then
        echo "[INFO] Found server MAC: $BT_MAC"
        break
    fi

    echo "[WARN] Server not found, rescanning (attempt $i/$SCAN_ATTEMPTS)..."
    set +e
    sudo bluetoothctl --timeout 5 scan on >/tmp/bt-scan.log 2>&1
    SCAN_STATUS=$?
    sudo bluetoothctl scan off >/dev/null 2>&1
    set -e

    if [ "$SCAN_STATUS" -ne 0 ]; then
        echo "[WARN] bluetoothctl scan on failed with status $SCAN_STATUS (see /tmp/bt-scan.log)."
    fi
done

if [ -z "$BT_MAC" ]; then
    echo "[ERROR] Could not find server after repeated attempts."
    exit 1
fi

# -----------------------------------------------------
# 2. Pair, trust, and connect
# -----------------------------------------------------
echo "[INFO] Pairing/trusting server ($BT_MAC)..."
set +e
sudo bluetoothctl <<EOF
power on
trust $BT_MAC
pair $BT_MAC
connect $BT_MAC
EOF
set -e

# -----------------------------------------------------
# 3. Start Bluetooth PAN (bnep0)
# -----------------------------------------------------
echo "[INFO] Starting PAN network (bnep0) via bt-network..."
set +e
sudo bt-network -c "$BT_MAC" nap
BT_STATUS=$?
set -e

if [ "$BT_STATUS" -ne 0 ]; then
    echo "[WARN] bt-network returned status $BT_STATUS, waiting to see if bnep0 appears..."
fi

for i in $(seq 1 12); do
    if ip link show bnep0 >/dev/null 2>&1; then
        echo "[INFO] PAN interface bnep0 is up."
        sudo ip link set bnep0 up || true
        break
    fi
    sleep 1
done

if ! ip link show bnep0 >/dev/null 2>&1; then
    echo "[ERROR] Failed to create Bluetooth PAN interface."
    exit 1
fi

# -----------------------------------------------------
# 4. DHCP request
# -----------------------------------------------------
echo "[INFO] Requesting IP address via DHCP..."
sudo dhclient -r bnep0 >/dev/null 2>&1 || true
sudo dhclient bnep0 || true

IP=$(ip -4 addr show bnep0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)

if [ -z "$IP" ]; then
    echo "[WARN] No DHCP lease yet. Waiting 3s..."
    sleep 3
    IP=$(ip -4 addr show bnep0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
fi

echo "[INFO] Assigned IP: ${IP:-none}"

# -----------------------------------------------------
# 5. Launch client container
# -----------------------------------------------------
echo "[INFO] Starting metrics client container via Docker (image: $DOCKER_IMAGE)..."

docker rm -f metrics-client >/dev/null 2>&1 || true

docker run -d \
    --name metrics-client \
    --network host \
    -e NODE_ID="$(hostname)" \
    "$DOCKER_IMAGE"

echo "[READY] Client is connected to $SERVER_NAME over Bluetooth PAN."
echo "[READY] Metrics client container is running."
