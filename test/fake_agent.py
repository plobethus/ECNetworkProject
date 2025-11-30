import grpc
import time
import random
import metrics_pb2
import metrics_pb2_grpc

SERVER_ADDRESS = "server:50051"   # inside Docker compose network

def generate_fake_metrics():
    return {
        "node_id": "test-node-python",
        "latency": random.uniform(10, 150),
        "jitter": random.uniform(0, 20),
        "packet_loss": random.uniform(0, 5),
        "bandwidth": random.uniform(5, 150),
        "timestamp": time.time_ns() // 1_000_000,   # <-- REALTIME timestamps
    }

def main():
    channel = grpc.insecure_channel(SERVER_ADDRESS)
    client = metrics_pb2_grpc.MetricsServiceStub(channel)

print("Python Test Agent started. Sending metrics every 100ms...")

    while True:
        data = generate_fake_metrics()

        req = metrics_pb2.MetricsRequest(
            node_id=data["node_id"],
            latency=data["latency"],
            jitter=data["jitter"],
            packet_loss=data["packet_loss"],
            bandwidth=data["bandwidth"],
            timestamp=data["timestamp"],
        )

        try:
            resp = client.SubmitMetrics(req)
            print(f"[OK] sent: {data['timestamp']} success={resp.success}")
        except Exception as e:
            print(f"[X] grpc error: {e}")

        time.sleep(0.1)   # <-- send 10 metrics/sec

if __name__ == "__main__":
    main()
