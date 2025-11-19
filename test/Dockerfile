FROM python:3.11-slim

WORKDIR /app

# Install build tools for grpcio-tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy proto locally (now inside build context)
COPY metrics.proto /app/

# Generate Python gRPC stubs
RUN python -m grpc_tools.protoc \
    --python_out=. \
    --grpc_python_out=. \
    -I /app \
    /app/metrics.proto

COPY fake_agent.py .

CMD ["python", "fake_agent.py"]