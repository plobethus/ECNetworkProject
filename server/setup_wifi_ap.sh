#!/usr/bin/env bash
# Bootstrap a Wi-Fi access point on the Raspberry Pi 4 (podServer).
# - Brings up wlan0 as an AP (default SSID: podNet, passphrase: podPass123)
# - Hands out IPs in 10.42.0.0/24 and NATs traffic out through eth0
# - Persists hostapd/dnsmasq/system settings so they survive reboot
# Usage: sudo ./setup_wifi_ap.sh
# Tunables (env vars): AP_SSID, AP_PASS, AP_CHANNEL, AP_INTERFACE, WAN_INTERFACE,
#                      AP_NET, AP_GATEWAY, DHCP_START, DHCP_END

set -euo pipefail

AP_SSID="${AP_SSID:-podNet}"
AP_PASS="${AP_PASS:-podPass123}"
AP_CHANNEL="${AP_CHANNEL:-6}"
AP_INTERFACE="${AP_INTERFACE:-wlan0}"
WAN_INTERFACE="${WAN_INTERFACE:-eth0}"
AP_NET="${AP_NET:-10.42.0}"
AP_GATEWAY="${AP_GATEWAY:-10.42.0.1}"
DHCP_START="${DHCP_START:-10.42.0.10}"
DHCP_END="${DHCP_END:-10.42.0.100}"

echo "=== Wi-Fi AP setup (podServer) ==="
echo "SSID: ${AP_SSID}"
echo "Passphrase: ${AP_PASS}"
echo "AP interface: ${AP_INTERFACE}  WAN: ${WAN_INTERFACE}"
echo "Subnet: ${AP_NET}.0/24  Gateway: ${AP_GATEWAY}"

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root (use sudo)." >&2
  exit 1
fi

echo "[1/6] Installing hostapd, dnsmasq, and iptables-persistent..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends hostapd dnsmasq iptables-persistent rfkill
rfkill unblock wlan || true

echo "[2/6] Setting static IP on ${AP_INTERFACE} (${AP_GATEWAY})..."
if command -v dhcpcd >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^dhcpcd.service'; then
  sed -i '/^# PODNET AP BEGIN/,/^# PODNET AP END/d' /etc/dhcpcd.conf
  cat <<EOF >> /etc/dhcpcd.conf
# PODNET AP BEGIN
interface ${AP_INTERFACE}
static ip_address=${AP_GATEWAY}/24
nohook wpa_supplicant
# PODNET AP END
EOF
  systemctl restart dhcpcd
else
  # Fallback for systems without dhcpcd: assign IP directly (non-persistent)
  ip link set "${AP_INTERFACE}" up
  ip addr flush dev "${AP_INTERFACE}" || true
  ip addr add "${AP_GATEWAY}/24" dev "${AP_INTERFACE}"
  echo "dhcpcd not present; assigned ${AP_GATEWAY}/24 to ${AP_INTERFACE} (non-persistent)" >&2
fi

echo "[3/6] Configuring hostapd..."
cat <<EOF > /etc/hostapd/hostapd.conf
interface=${AP_INTERFACE}
driver=nl80211
ssid=${AP_SSID}
hw_mode=g
channel=${AP_CHANNEL}
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${AP_PASS}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
systemctl unmask hostapd
systemctl enable hostapd

echo "[4/6] Configuring dnsmasq DHCP range..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true
cat <<EOF > /etc/dnsmasq.d/podnet.conf
interface=${AP_INTERFACE}
dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,12h
dhcp-option=option:router,${AP_GATEWAY}
dhcp-option=option:dns-server,1.1.1.1,1.0.0.1
EOF
systemctl restart dnsmasq

echo "[5/6] Enabling IP forwarding and NAT..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-podnet.conf
sysctl -p /etc/sysctl.d/99-podnet.conf

iptables -t nat -C POSTROUTING -o "${WAN_INTERFACE}" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o "${WAN_INTERFACE}" -j MASQUERADE
iptables -C FORWARD -i "${WAN_INTERFACE}" -o "${AP_INTERFACE}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i "${WAN_INTERFACE}" -o "${AP_INTERFACE}" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -i "${AP_INTERFACE}" -o "${WAN_INTERFACE}" -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i "${AP_INTERFACE}" -o "${WAN_INTERFACE}" -j ACCEPT

netfilter-persistent save

echo "[6/6] Starting hostapd..."
systemctl restart hostapd

echo "Done. podServer AP \"${AP_SSID}\" is live on ${AP_INTERFACE} (${AP_GATEWAY})."
echo "Clients should point their gRPC/iperf to ${AP_GATEWAY}."
