DROP TABLE IF EXISTS metrics;

CREATE TABLE metrics (
  id SERIAL PRIMARY KEY,
  node_id TEXT,
  latency DOUBLE PRECISION,
  jitter DOUBLE PRECISION,
  packet_loss DOUBLE PRECISION,
  bandwidth DOUBLE PRECISION,
  timestamp BIGINT NOT NULL
);