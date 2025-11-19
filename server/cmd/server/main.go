package main

import (
	"log"
	"net"

	"google.golang.org/grpc"

	handler "ECNetworkProject/server/pkg/api"
	pb "ECNetworkProject/server/pkg/api/proto"
)

func main() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterMetricsServiceServer(s, &handler.MetricsHandler{})

	log.Println("gRPC server running on :50051")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}