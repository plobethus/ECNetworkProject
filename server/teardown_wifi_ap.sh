#!/usr/bin/env bash
# Stop/cleanup the podServer Wi-Fi AP services (hostapd/dnsmasq) and routing.
# Usage: sudo ./teardown_wifi_ap.sh
# Tunables (env vars): AP_INTERFACE, WAN_INTERFACE

set -euo pipefail

AP_INTERFACE="${AP_INTERFACE:-wlan0}"
WAN_INTERFACE="${WAN_INTERFACE:-eth0}"

echo "=== Stopping podServer Wi-Fi AP ==="
echo "AP interface: ${AP_INTERFACE}  WAN: ${WAN_INTERFACE}"

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root (use sudo)." >&2
  exit 1
fi

echo "[1/4] Stopping hostapd and dnsmasq..."
systemctl stop hostapd || true
systemctl stop dnsmasq || true

echo "[2/4] Removing static IP override from /etc/dhcpcd.conf..."
sed -i '/^# PODNET AP BEGIN/,/^# PODNET AP END/d' /etc/dhcpcd.conf
systemctl restart dhcpcd || true

echo "[3/4] Removing iptables NAT/forward rules..."
iptables -t nat -D POSTROUTING -o "${WAN_INTERFACE}" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i "${WAN_INTERFACE}" -o "${AP_INTERFACE}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "${AP_INTERFACE}" -o "${WAN_INTERFACE}" -j ACCEPT 2>/dev/null || true
netfilter-persistent save || true

echo "[4/4] Disabling IP forwarding (runtime)..."
sysctl -w net.ipv4.ip_forward=0 >/dev/null || true

echo "Done. AP services stopped; wlan0 released back to client mode."
