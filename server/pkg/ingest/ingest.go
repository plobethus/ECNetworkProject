package ingest

import (
	"ECNetworkProject/server/pkg/db"
	pb "ECNetworkProject/server/pkg/api/proto"
)

func StoreMetrics(req *pb.MetricsRequest) error {
	conn, err := db.Connect()
	if err != nil {
		return err
	}
	defer conn.Close()

	_, err = conn.Exec(
		`INSERT INTO metrics (node_id, latency, jitter, packet_loss, bandwidth, timestamp)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		req.NodeId, req.Latency, req.Jitter, req.PacketLoss, req.Bandwidth, req.Timestamp,
	)

	return err
}