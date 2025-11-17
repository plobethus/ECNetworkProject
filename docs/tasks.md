# Task Breakdown for Two People

## Person A: Hardware, Networking, and Client Side Systems

### 1. Hardware Setup
- Prepare the Raspberry Pi 4 server and multiple Raspberry Pi 3 client units.
- Connect the Pi 4 to Ethernet and Pi 3 units to Wi Fi.
- Place each Pi 3 in different locations to measure variation in signal quality.

### 2. Data Collection Layer
- Write and deploy Python scripts to perform:
  - Ping tests for latency and packet loss
  - Jitter calculations
  - Bandwidth tests using iperf3
  - Traceroute diagnostics
- Configure automated scheduling for tests on each client.

### 3. Communication Layer
- Implement MQTT or REST based communication from client Pis to the server.
- Ensure secure and reliable data transmission.
- Standardize data payload formats and validate transmission consistency.

### 4. Client Side Reliability and Monitoring
- Monitor reporting frequency and consistency from each client.
- Add local logging on each Pi 3 for debugging interruption or connectivity issues.

---

## Person B: Server Side Processing, Database, and Dashboard

### 1. Central Server Setup
- Configure the Raspberry Pi 4 to serve as the project server.
- Install required backend components such as:
  - InfluxDB or PostgreSQL for time series storage
  - Flask API or MQTT broker for receiving metrics

### 2. Storage and Processing Layer
- Design and implement database schemas for:
  - Latency
  - Jitter
  - Packet loss
  - Bandwidth
  - Node identification with timestamps
- Build ingestion logic to store incoming client data.

### 3. Visualization Layer
- Create dashboards using Grafana or a Flask based web interface.
- Implement visualizations that show:
  - Comparisons between nodes
  - Time series graphs
  - Heatmaps illustrating Wi Fi performance in different rooms

### 4. Anomaly Detection and Reporting
- Implement threshold based anomaly detection or lightweight machine learning methods.
- Produce automated alerts and periodic summary reports.
- Integrate analysis output into the dashboard.

---

## Optional Joint Tasks

### 1. Documentation
- Write setup instructions for hardware and software.
- Create architecture diagrams.
- Document user procedures for operating the system.

### 2. Testing and Calibration
- Benchmark wired versus wireless performance.
- Validate accuracy of results across all nodes.

### 3. Future Scalability Planning
- Explore options for multi router setups.
- Plan for cloud synchronization.
- Discuss expansion to additional or remote monitoring sites.