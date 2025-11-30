FROM python:3.11-slim

# Install system tools needed by the Python scripts
RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    iperf3 \
    bluetooth \
    bluez \
    python3-bluez \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy client directory
COPY . /app

# Install Python deps
RUN pip install --no-cache-dir -r requirements.txt

# Run the scheduler loop
CMD ["python", "scheduler.py"]
