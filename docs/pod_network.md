# Pod Wi-Fi / Pod IDs

Quick steps to stand up the Raspberry Pi 4 access point (podServer), connect Raspberry Pi 3 clients, and feed data into the existing gRPC + dashboard pipeline.

## 1) Bring up the podServer AP (Pi 4)
- Requirements: Raspberry Pi OS, internet on `eth0`, built-in Wi-Fi on `wlan0`.
- Run as root: `sudo chmod +x server/setup_wifi_ap.sh && sudo ./server/setup_wifi_ap.sh`
- Defaults: SSID `podNet`, password `podPass123`, gateway `10.42.0.1`, DHCP range `10.42.0.10-100`.
- Override with env vars if needed: `AP_SSID`, `AP_PASS`, `AP_CHANNEL`, `AP_INTERFACE`, `WAN_INTERFACE`, `AP_NET`, `AP_GATEWAY`, `DHCP_START`, `DHCP_END`.
- After the script: hostapd + dnsmasq + NAT are enabled and persistent; point gRPC/iPerf clients at `10.42.0.1`.

## 2) Connect podOne / podTwo / podThree (Pi 3)
- Requirements: `iw`, `wpa_supplicant`, and DHCP client installed (default on Raspberry Pi OS).
- Run as root on each Pi 3 from the project root:
  ```
  sudo chmod +x client/connect_to_pod_ap.sh
  sudo SSID=podNet PSK=podPass123 NODE_ID=podOne SERVER_IP=10.42.0.1 ./client/connect_to_pod_ap.sh
  ```
  Swap `NODE_ID` per device (podOne, podTwo, podThree).
- The script:
  - Scans for the SSID and writes `/etc/wpa_supplicant/wpa_supplicant.conf`.
  - Updates `client/config.json` with `grpc_server_host`/`iperf_server_host` set to the AP gateway and the provided `NODE_ID`.
  - Launches `python3 -m client.scheduler` with `PYTHONPATH` set to the repo root (set `START_METRICS=0` to skip auto-launch).

## 3) Dashboard view
- The dashboard (`dashboard` service) now exposes `/api/pods` and renders a "Pod Status" section showing podServer/podOne/podTwo/podThree, last-seen times, and latest metrics.
- A pod is marked `online` if it has posted metrics within 120 seconds (configurable via `POD_ONLINE_THRESHOLD_SECONDS` env var on the dashboard service).
- You can start/stop the AP from the dashboard control panel (buttons at the top) and watch the live log pane for command output plus pod activity. Set env vars `AP_SETUP_SCRIPT`, `AP_TEARDOWN_SCRIPT`, and optionally `AP_USE_SUDO=1` on the dashboard service so it can find/run the scripts. Running these scripts from inside a container requires host access/privileged mode; otherwise run the dashboard on the Pi host.
