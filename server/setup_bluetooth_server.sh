#!/bin/bash
set -e

SERVER_IP="10.1.1.1"
BRIDGE_IFACE="br0"
DHCP_RANGE_START="10.1.1.50"
DHCP_RANGE_END="10.1.1.200"

echo "[1/9] Installing Bluetooth + DHCP packages..."
sudo apt-get update
sudo apt-get install -y bluez bluez-tools bridge-utils dnsmasq

echo "[2/9] Enabling Bluetooth..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

echo "[3/9] Setting hostname to podServer..."
sudo hostnamectl set-hostname podServer

echo "[4/9] Creating network bridge..."
sudo brctl addbr $BRIDGE_IFACE || true
sudo ip addr flush dev $BRIDGE_IFACE || true
sudo ip addr add $SERVER_IP/24 dev $BRIDGE_IFACE || true
sudo ip link set $BRIDGE_IFACE up

echo "[5/9] Configuring dnsmasq DHCP server for PAN..."
sudo tee /etc/dnsmasq.d/bt-pan.conf > /dev/null <<EOF
# DHCP settings for Bluetooth PAN
interface=$BRIDGE_IFACE
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,12h
dhcp-option=3,$SERVER_IP     # gateway
dhcp-option=6,8.8.8.8,1.1.1.1 # DNS
EOF

echo "[6/9] Restarting dnsmasq..."
sudo systemctl restart dnsmasq

echo "[7/9] Starting Bluetooth NAP (Network Access Point)..."
sudo bt-pan nop $BRIDGE_IFACE || sudo bt-pan nap $BRIDGE_IFACE &
sleep 2

echo "[8/9] Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
sudo sed -i 's/^#net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf

echo "[9/9] DONE!"
echo "podServer is now a full Bluetooth router with DHCP assignments."
echo "Clients will auto-connect and receive IP addresses automatically."