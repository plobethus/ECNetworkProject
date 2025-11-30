import time
import socket

from .network_tests import collect_metrics
from .metrics_client import MetricsGRPCClient, load_config


def main():
    # Load config from client/config.json
    config = load_config("client/config.json")

    node_id = config.get("node_id") or socket.gethostname()
    ping_target = config["ping_target"]
    iperf_server_host = config["iperf_server_host"]
    iperf_server_port = int(config.get("iperf_server_port", 5201))
    interval = int(config["interval_seconds"])

    grpc_client = MetricsGRPCClient(config)

    print(f"\n=== Network Scheduler Started for Node: {node_id} ===")
    print(f"Ping target: {ping_target}")
    print(f"iPerf3 server: {iperf_server_host}")
    print(f"Send interval: {interval} seconds\n")

    while True:
        loop_start = time.time()
        timestamp = int(loop_start)

        # Run tests
        metrics = collect_metrics(ping_target, iperf_server_host, iperf_port=iperf_server_port)

        print(f"[{timestamp}] Metrics collected:")
        print(f"  Latency:      {metrics['latency']:.2f} ms")
        print(f"  Jitter:       {metrics['jitter']:.2f} ms")
        print(f"  Packet Loss:  {metrics['packet_loss']:.2f} %")
        print(f"  Bandwidth:    {metrics['bandwidth']:.2f} Mbps")

        # Send to gRPC server
        success = grpc_client.submit_metrics(
            node_id=node_id,
            latency=metrics["latency"],
            jitter=metrics["jitter"],
            packet_loss=metrics["packet_loss"],
            bandwidth=metrics["bandwidth"],
            timestamp=timestamp
        )

        if success:
            print("  [OK] Submitted successfully\n")
        else:
            print("  [X] Submission failed\n")

        elapsed = time.time() - loop_start
        sleep_for = max(0, interval - elapsed)
        time.sleep(sleep_for)


if __name__ == "__main__":
    main()
