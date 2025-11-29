# ECNetworkProject

Extra credit networks project for COSC 4377
Done by Henry Moran and Jonathan Cardenas


# gRPC

go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# run project test

docker compose down -vdocker compose up --build

# run server

cd scripts
./run_server_stack.sh --build --host-dashboard

start ap to start network, stop ap to stop it 

## stop server

./stop_server_stack.sh

# connect pod to server

cd client
./connect_to_pod_ap.sh