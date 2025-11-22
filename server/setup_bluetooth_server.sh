#!/bin/bash
set -euo pipefail

SERVER_NAME="podServer"
SERVER_IP="10.1.1.1"
BRIDGE_IFACE="br0"
DHCP_RANGE_START="10.1.1.50"
DHCP_RANGE_END="10.1.1.200"

echo "[1/9] Installing Bluetooth + DHCP packages..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bluez \
    bluez-tools \
    bridge-utils \
    dnsmasq \
    rfkill \
    iproute2

echo "[2/9] Enabling and powering Bluetooth..."
sudo rfkill unblock bluetooth || true
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
sudo hciconfig hci0 up || true

echo "[3/9] Configuring Bluetooth adapter name and discoverability..."
sudo bluetoothctl <<EOF
power on
system-alias $SERVER_NAME
pairable on
discoverable on
discoverable-timeout 0
agent NoInputNoOutput
default-agent
EOF

echo "[4/9] Setting hostname to $SERVER_NAME..."
sudo hostnamectl set-hostname "$SERVER_NAME"

echo "[5/9] Creating network bridge ($BRIDGE_IFACE)..."
sudo brctl addbr "$BRIDGE_IFACE" || true
sudo ip addr flush dev "$BRIDGE_IFACE" || true
sudo ip addr add "$SERVER_IP/24" dev "$BRIDGE_IFACE" || true
sudo ip link set "$BRIDGE_IFACE" up

echo "[6/9] Configuring dnsmasq for DHCP over PAN..."
sudo mkdir -p /etc/dnsmasq.d
sudo tee /etc/dnsmasq.d/bt-pan.conf > /dev/null <<EOF
# DHCP for Bluetooth PAN
interface=$BRIDGE_IFACE
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,12h
dhcp-option=3,$SERVER_IP
dhcp-option=6,8.8.8.8,1.1.1.1
EOF

echo "[7/9] Restarting dnsmasq..."
sudo systemctl restart dnsmasq

echo "[8/9] Enabling Bluetooth Network Access Point (NAP)..."
sudo pkill -f "bt-network -s nap $BRIDGE_IFACE" >/dev/null 2>&1 || true
sudo bt-network -s nap "$BRIDGE_IFACE" >/tmp/bt-nap.log 2>&1 &
sleep 2

echo "[9/9] Enabling IP forwarding (Pi OS style)..."
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/98-rpi.conf >/dev/null
sudo systemctl restart systemd-sysctl

echo "podServer is discoverable as $SERVER_NAME and running a Bluetooth PAN with DHCP on $SERVER_IP."
echo "Clients will auto-connect, receive IP via dnsmasq, and reach services on $SERVER_IP."
