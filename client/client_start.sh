#!/bin/bash
set -e

SERVER_NAME="podServer"
BT_MAC=""       # We auto-detect this
DOCKER_IMAGE="metrics-client:latest"

echo "[INFO] Starting client on host: $(hostname)"

# -----------------------------------------------------
# 1. Find Bluetooth MAC of podServer via name lookup
# -----------------------------------------------------
echo "[INFO] Scanning for server..."
for i in {1..20}; do
    BT_MAC=$(bluetoothctl devices | grep "$SERVER_NAME" | awk '{print $2}')
    if [ -n "$BT_MAC" ]; then
        echo "[INFO] Found server MAC: $BT_MAC"
        break
    fi

    echo "[WARN] Server not found, rescanning..."
    bluetoothctl scan on >/dev/null 2>&1 &
    sleep 5
    bluetoothctl scan off >/dev/null 2>&1
done

if [ -z "$BT_MAC" ]; then
    echo "[ERROR] Could not find server after repeated attempts."
    exit 1
fi

# -----------------------------------------------------
# 2. Pair + trust + connect
# -----------------------------------------------------
echo "[INFO] Pairing with server..."
bluetoothctl trust "$BT_MAC"
bluetoothctl pair "$BT_MAC" || true
bluetoothctl connect "$BT_MAC" || true

# -----------------------------------------------------
# 3. Start network over Bluetooth PAN
# -----------------------------------------------------
echo "[INFO] Bringing up Bluetooth PAN (bnep0)..."
sleep 2

# Automatically create interface
sudo bash -c 'if ! ip link show bnep0 >/dev/null 2>&1; then
    echo "Attempting to create bnep0 via pand..."
    pand --connect $BT_MAC --service NAP || true
fi'

# Wait for interface
for i in {1..10}; do
    if ip link show bnep0 >/dev/null 2>&1; then
        echo "[INFO] bnep0 is up"
        break
    fi
    sleep 1
done

if ! ip link show bnep0 >/dev/null 2>&1; then
    echo "[ERROR] Bluetooth PAN failed"
    exit 1
fi

# DHCP — client gets IP from server DHCP
echo "[INFO] Requesting DHCP IP..."
sudo dhclient bnep0 || true

IP=$(ip -4 addr show bnep0 | grep -oP '(?<=inet ).*(?=/)')
echo "[INFO] Client IP on bnep0: $IP"

# -----------------------------------------------------
# 4. Run the gRPC client container
# -----------------------------------------------------
echo "[INFO] Starting gRPC client container..."

docker rm -f metrics-client >/dev/null 2>&1 || true

docker run -d \
    --name metrics-client \
    --network host \
    -e NODE_ID="$(hostname)" \
    "$DOCKER_IMAGE"

echo "[INFO] Client container launched!"
echo "[READY] Client is connected to podServer via Bluetooth PAN."