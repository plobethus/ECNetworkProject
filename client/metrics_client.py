import grpc
import json
from typing import Dict, Any

from . import metrics_pb2, metrics_pb2_grpc


def load_config(path: str = "client/config.json") -> Dict[str, Any]:
    """Loads configuration file."""
    with open(path, "r") as f:
        return json.load(f)


class MetricsGRPCClient:
    """
    gRPC client that sends metrics from Raspberry Pi 3 -> Raspberry Pi 4.
    Uses the generated metrics_pb2 and metrics_pb2_grpc classes.
    """
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        target = f"{config['grpc_server_host']}:{config['grpc_server_port']}"
        print(f"[gRPC] Connecting to server at {target} ...")
        self.channel = grpc.insecure_channel(target)
        self.stub = metrics_pb2_grpc.MetricsServiceStub(self.channel)

    def submit_metrics(self, node_id: str, latency: float, jitter: float,
                       packet_loss: float, bandwidth: float, timestamp: int) -> bool:
        """Builds and sends a MetricsRequest message."""
        request = metrics_pb2.MetricsRequest(
            node_id=node_id,
            latency=latency,
            jitter=jitter,
            packet_loss=packet_loss,
            bandwidth=bandwidth,
            timestamp=timestamp
        )

        try:
            response: metrics_pb2.MetricsResponse = self.stub.SubmitMetrics(request)
            return response.success
        except grpc.RpcError as e:
            print(f"[gRPC ERROR] {e.code()}: {e.details()}")
            return False
