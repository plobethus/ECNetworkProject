package api

import (
	"context"

	pb "ECNetworkProject/server/pkg/api/proto"
	"ECNetworkProject/server/pkg/ingest"
)

type MetricsHandler struct {
	pb.UnimplementedMetricsServiceServer
}

func (h *MetricsHandler) SubmitMetrics(ctx context.Context, req *pb.MetricsRequest) (*pb.MetricsResponse, error) {
	err := ingest.StoreMetrics(req)
	if err != nil {
		return &pb.MetricsResponse{Success: false}, err
	}
	return &pb.MetricsResponse{Success: true}, nil
}