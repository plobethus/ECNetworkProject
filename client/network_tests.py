import subprocess
import re
import json
import statistics
from typing import Dict, Any


def run_ping(target: str = "8.8.8.8", count: int = 2, timeout: int = 2) -> Dict[str, float]:
    try:
        result = subprocess.run(
            ["ping", "-c", str(count), "-W", str(timeout), target],
            capture_output=True,
            text=True,
            check=False  # we still want output even if some loss occurs
        )
        output = result.stdout

        times = re.findall(r"time=(\d+\.\d+)", output)
        times = [float(t) for t in times]

        m_loss = re.search(r"(\d+)% packet loss", output)
        packet_loss = float(m_loss.group(1)) if m_loss else 100.0

        if times:
            avg_latency = statistics.mean(times)
            jitter = statistics.pstdev(times)
        else:
            avg_latency = 0.0
            jitter = 0.0

        return {
            "latency": avg_latency,
            "jitter": jitter,
            "packet_loss": packet_loss
        }

    except Exception:
        return {
            "latency": 0.0,
            "jitter": 0.0,
            "packet_loss": 100.0
        }


def run_iperf3(server_host: str, duration: int = 1) -> float:
    try:
        result = subprocess.run(
            ["iperf3", "-c", server_host, "-t", str(duration), "-J"],
            capture_output=True,
            text=True,
            check=True,
            timeout=duration + 2,
        )
        data = json.loads(result.stdout)

        bps = data["end"]["sum_received"]["bits_per_second"]
        return bps / 1_000_000.0
    except Exception:
        return 0.0


def collect_metrics(ping_target: str, iperf_server_host: str) -> Dict[str, Any]:
    ping_results = run_ping(ping_target)
    bandwidth_mbps = run_iperf3(iperf_server_host)

    return {
        "latency": ping_results["latency"],
        "jitter": ping_results["jitter"],
        "packet_loss": ping_results["packet_loss"],
        "bandwidth": bandwidth_mbps
    }
