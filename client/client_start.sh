#!/bin/bash
set -e

SERVER_NAME="podServer"
BT_MAC=""
DOCKER_IMAGE="metrics-client:latest"

echo "[INFO] Starting client on host: $(hostname)"
echo "[INFO] Preparing Bluetooth hardware..."

# -----------------------------------------------------
# 0. Fix Bluetooth on Raspberry Pi
# -----------------------------------------------------

echo "[INFO] Unblocking Bluetooth via rfkill..."
sudo rfkill unblock bluetooth || true

echo "[INFO] Restarting Bluetooth service..."
sudo systemctl restart bluetooth || true
sleep 2

echo "[INFO] Powering on hci0..."
sudo hciconfig hci0 up || true

# Verify it's working
if ! hciconfig hci0 | grep -q "UP RUNNING"; then
    echo "[ERROR] Bluetooth adapter hci0 is DOWN."
    echo "Trying to power cycle Bluetooth ..."
    sudo hciconfig hci0 down || true
    sleep 1
    sudo hciconfig hci0 up || true
fi

if ! hciconfig hci0 | grep -q "UP RUNNING"; then
    echo "[FATAL] Cannot bring up Bluetooth adapter hci0."
    echo "Please check Pi firmware or hardware."
    exit 1
fi

echo "[INFO] Bluetooth adapter is up."

# -----------------------------------------------------
# 1. Scan for the server
# -----------------------------------------------------
echo "[INFO] Scanning for server named: $SERVER_NAME"

for i in {1..20}; do
    BT_MAC=$(bluetoothctl devices | grep "$SERVER_NAME" | awk '{print $2}')

    if [ -n "$BT_MAC" ]; then
        echo "[INFO] Found server MAC: $BT_MAC"
        break
    fi

    echo "[WARN] Server not found, rescanning..."
    bluetoothctl scan on >/dev/null 2>&1 &
    sleep 4
    bluetoothctl scan off >/dev/null 2>&1
done

if [ -z "$BT_MAC" ]; then
    echo "[ERROR] Could not find server after repeated attempts."
    exit 1
fi

# -----------------------------------------------------
# 2. Pair & trust & connect
# -----------------------------------------------------
echo "[INFO] Pairing with server ($BT_MAC)..."

bluetoothctl trust "$BT_MAC"
bluetoothctl pair "$BT_MAC" || true
bluetoothctl connect "$BT_MAC" || true

# -----------------------------------------------------
# 3. Start Bluetooth PAN (bnep0)
# -----------------------------------------------------
echo "[INFO] Starting PAN network (bnep0)..."
sleep 2

sudo bash -c '
if ! ip link show bnep0 >/dev/null 2>&1; then
    echo "[INFO] Attempting to create bnep0 using pand..."
    pand --connect '"$BT_MAC"' --service NAP || true
fi
'

# Wait for bnep0
for i in {1..10}; do
    if ip link show bnep0 >/dev/null 2>&1; then
        echo "[INFO] PAN interface bnep0 is up."
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
sudo dhclient bnep0 || true

IP=$(ip -4 addr show bnep0 | grep -oP '(?<=inet ).*(?=/)' || true)

if [ -z "$IP" ]; then
    echo "[WARN] No DHCP lease yet. Waiting 3s..."
    sleep 3
    IP=$(ip -4 addr show bnep0 | grep -oP '(?<=inet ).*(?=/)' || true)
fi

echo "[INFO] Assigned IP: $IP"

# -----------------------------------------------------
# 5. Launch client container
# -----------------------------------------------------
echo "[INFO] Starting metrics client container via Docker..."

docker rm -f metrics-client >/dev/null 2>&1 || true

docker run -d \
    --name metrics-client \
    --network host \
    -e NODE_ID="$(hostname)" \
    "$DOCKER_IMAGE"

echo "[READY] Client is fully connected to podServer over Bluetooth PAN."
echo "[READY] Metrics client container is running."