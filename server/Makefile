PROTO_SRC=pkg/api/proto/metrics.proto
PROTO_OUT=pkg/api/proto

all: proto build

proto:
	protoc --go_out=. --go-grpc_out=. $(PROTO_SRC)

build:
	go build -o bin/server cmd/server/main.go

run:
	go run cmd/server/main.go

clean:
	rm -rf bin
	rm -f $(PROTO_OUT)/*.pb.go

docker:
	docker build -t grpc-server .

tidy:
	go mod tidy