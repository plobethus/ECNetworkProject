#!/bin/bash
set -e

SERVER_NAME="podServer"
DOCKER_IMAGE="metrics-client:latest"

echo "[INFO] Starting client on host: $(hostname)"

# -----------------------------------------------------
# 1. Locate server Bluetooth MAC
# -----------------------------------------------------
echo "[INFO] Scanning for server Bluetooth device..."

BT_MAC=""

for i in {1..20}; do
    bluetoothctl --timeout 5 scan on >/dev/null 2>&1
    BT_MAC=$(bluetoothctl devices | grep "$SERVER_NAME" | awk '{print $2}')

    if [ -n "$BT_MAC" ]; then
        echo "[INFO] Found server MAC: $BT_MAC"
        break
    fi

    echo "[WARN] Server not found yet..."
done

if [ -z "$BT_MAC" ]; then
    echo "[ERROR] Could not find podServer after multiple scans."
    exit 1
fi

# -----------------------------------------------------
# 2. Pair / trust / connect
# -----------------------------------------------------
echo "[INFO] Pairing..."
bluetoothctl trust "$BT_MAC"
bluetoothctl pair "$BT_MAC" || true
bluetoothctl connect "$BT_MAC" || true

# -----------------------------------------------------
# 3. Create Bluetooth PAN interface (bnep0)
# -----------------------------------------------------
echo "[INFO] Starting PAN client mode..."
sudo bt-network -c "$BT_MAC" nap &

sleep 3

# Wait for interface
for i in {1..15}; do
    if ip link show bnep0 >/dev/null 2>&1; then
        echo "[INFO] bnep0 created!"
        break
    fi
    echo "[INFO] Waiting for bnep0..."
    sleep 1
done

if ! ip link show bnep0 >/dev/null 2>&1; then
    echo "[ERROR] Bluetooth PAN did not come up."
    exit 1
fi

# -----------------------------------------------------
# 4. Request DHCP from server
# -----------------------------------------------------
echo "[INFO] Requesting DHCP IP from podServer..."
sudo dhclient -v bnep0 || true

IP=$(ip -4 addr show bnep0 | grep -oP '(?<=inet ).*(?=/)' || true)

if [ -z "$IP" ]; then
    echo "[ERROR] No IP received from server!"
    exit 1
fi

echo "[INFO] Assigned IP on bnep0: $IP"

# -----------------------------------------------------
# 5. Launch client container
# -----------------------------------------------------
echo "[INFO] Starting client Docker container..."

docker rm -f metrics-client >/dev/null 2>&1 || true

docker run -d \
    --name metrics-client \
    --network host \
    -e NODE_ID="$(hostname)" \
    "$DOCKER_IMAGE"

echo "[READY] Client connected via Bluetooth PAN → podServer"
echo "[READY] gRPC client container running."