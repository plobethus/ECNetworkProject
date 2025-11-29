import json
import os
import queue
import socket
import subprocess
import threading
import time
from pathlib import Path

import psycopg2
from flask import Flask, render_template, Response, stream_with_context, jsonify
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

# Simple in-process queues for SSE
chart_event_queue = queue.Queue()
log_queue = queue.Queue()
DB_DSN = os.getenv("DATABASE_URL", "postgresql://admin:admin@db:5432/metrics")
AP_SETUP_SCRIPT = os.getenv("AP_SETUP_SCRIPT", "/app/server/setup_wifi_ap.sh")
AP_TEARDOWN_SCRIPT = os.getenv("AP_TEARDOWN_SCRIPT", "/app/server/teardown_wifi_ap.sh")
AP_USE_SUDO = os.getenv("AP_USE_SUDO", "0") == "1"

POD_LABELS = {
    "podServer": "Server (AP)",
    "podOne": "Pod One",
    "podTwo": "Pod Two",
    "podThree": "Pod Three",
}
ONLINE_THRESHOLD_SECONDS = int(os.getenv("POD_ONLINE_THRESHOLD_SECONDS", "120"))
PODSERVER_HEALTH_HOST = os.getenv("PODSERVER_HEALTH_HOST", "server")
PODSERVER_HEALTH_PORT = int(os.getenv("PODSERVER_HEALTH_PORT", "50051"))
PODSERVER_HEALTH_TIMEOUT = float(os.getenv("PODSERVER_HEALTH_TIMEOUT", "1.0"))
THRESH_LATENCY_MS = float(os.getenv("ALERT_LATENCY_MS", "150"))
THRESH_JITTER_MS = float(os.getenv("ALERT_JITTER_MS", "40"))
THRESH_LOSS_PCT = float(os.getenv("ALERT_PACKET_LOSS_PCT", "5"))
THRESH_BANDWIDTH_MBPS = float(os.getenv("ALERT_MIN_BANDWIDTH_MBPS", "5"))


@app.route("/")
def index():
    # Pass an initial cache-buster so first load gets the latest charts
    return render_template("index.html", ts=int(time.time() * 1000))


def event_stream():
    """Generator that yields SSE events as they arrive."""
    while True:
        event = chart_event_queue.get()  # blocks until something is put()
        app.logger.info("Sending SSE event: %s", event)
        yield f"data: {event}\n\n"


@app.route("/events")
def events():
    """SSE endpoint consumed by EventSource on the browser."""
    headers = {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        # Helps if you ever put this behind a proxy like nginx
        "X-Accel-Buffering": "no",
    }
    return Response(stream_with_context(event_stream()), headers=headers)


@app.route("/event/chart-updated")
def chart_updated():
    """Called by chartgen (C program via curl) when SVGs are regenerated."""
    app.logger.info("chart_updated endpoint hit, enqueueing event")
    try:
        chart_event_queue.put_nowait("chart_update")
    except Exception as e:
        app.logger.exception("Failed to enqueue chart_update: %s", e)
    return "ok"


def push_log(message: str, level: str = "info", source: str = "dashboard"):
    """Push a structured log message into the SSE log queue."""
    payload = {
        "message": message,
        "level": level,
        "source": source,
        "ts": int(time.time() * 1000),
    }
    try:
        log_queue.put_nowait(payload)
    except Exception as exc:
        app.logger.error("Failed to enqueue log message: %s", exc)


def log_stream():
    """Generator that yields log SSE events."""
    while True:
        payload = log_queue.get()
        yield f"data: {json.dumps(payload)}\n\n"


@app.route("/logs")
def logs():
    """SSE endpoint for live terminal-style logs."""
    headers = {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    }
    push_log("Log stream connected", source="logs")
    return Response(stream_with_context(log_stream()), headers=headers)


def _build_cmd(script_path: str):
    """Return the full command list with optional sudo."""
    base = ["bash", script_path]
    if AP_USE_SUDO:
        return ["sudo"] + base
    return base


def _run_script_async(name: str, script_path: str):
    """Run a shell script in a background thread and stream output to SSE logs."""
    path = Path(script_path)
    if not path.exists():
        msg = f"Script not found: {script_path}"
        push_log(msg, level="error", source=name)
        return

    cmd = _build_cmd(str(path))
    push_log(f"Starting {name}: {' '.join(cmd)}", source=name)

    def _runner():
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                push_log(line.rstrip(), source=name)
            proc.wait()
            if proc.returncode == 0:
                push_log(f"{name} completed (rc=0)", level="success", source=name)
            else:
                push_log(f"{name} failed (rc={proc.returncode})", level="error", source=name)
        except Exception as exc:
            push_log(f"{name} errored: {exc}", level="error", source=name)

    threading.Thread(target=_runner, daemon=True).start()


def _normalize_timestamp(raw_ts):
    """Return timestamp in seconds (handles ms or s inputs)."""
    if raw_ts is None:
        return None
    return raw_ts / 1000 if raw_ts > 1_000_000_000_000 else raw_ts


def fetch_pod_snapshot():
    """Return latest metrics per node along with online/offline status."""
    query = """
        WITH latest AS (
            SELECT node_id, MAX(timestamp) AS ts
            FROM metrics
            GROUP BY node_id
        )
        SELECT m.node_id, m.latency, m.jitter, m.packet_loss, m.bandwidth, m.timestamp
        FROM metrics m
        INNER JOIN latest l ON m.node_id = l.node_id AND m.timestamp = l.ts;
    """
    with psycopg2.connect(DB_DSN) as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            rows = cur.fetchall()

    now_sec = time.time()
    by_node = {row["node_id"]: row for row in rows}

    def _check_tcp(hosts, port: int, timeout: float) -> bool:
        for h in hosts:
            if not h:
                continue
            try:
                with socket.create_connection((h, port), timeout=timeout):
                    return True
            except OSError:
                continue
        return False

    def build_entry(node_id: str, label: str):
        row = by_node.get(node_id)
        last_seen_ms = None
        age = None
        status = "offline"
        metrics = None
        alerts = []
        if row:
            ts_sec = _normalize_timestamp(int(row["timestamp"]))
            last_seen_ms = int(ts_sec * 1000)
            age = now_sec - ts_sec
            status = "online" if age <= ONLINE_THRESHOLD_SECONDS else "stale"
            metrics = {
                "latency": row["latency"],
                "jitter": row["jitter"],
                "packet_loss": row["packet_loss"],
                "bandwidth": row["bandwidth"],
            }
            # Threshold alerts
            if metrics["latency"] > THRESH_LATENCY_MS:
                alerts.append(f"Latency {metrics['latency']:.1f} ms > {THRESH_LATENCY_MS} ms")
            if metrics["jitter"] > THRESH_JITTER_MS:
                alerts.append(f"Jitter {metrics['jitter']:.1f} ms > {THRESH_JITTER_MS} ms")
            if metrics["packet_loss"] > THRESH_LOSS_PCT:
                alerts.append(f"Loss {metrics['packet_loss']:.1f}% > {THRESH_LOSS_PCT}%")
            if metrics["bandwidth"] < THRESH_BANDWIDTH_MBPS:
                alerts.append(f"Bandwidth {metrics['bandwidth']:.1f} Mbps < {THRESH_BANDWIDTH_MBPS} Mbps")

        # Special-case podServer: if no metrics yet, consider AP/server reachable via TCP
        if row is None and node_id == "podServer":
            candidates = [
                PODSERVER_HEALTH_HOST,
                "localhost",
                "127.0.0.1",
                "server",
            ]
            if _check_tcp(candidates, PODSERVER_HEALTH_PORT, PODSERVER_HEALTH_TIMEOUT):
                last_seen_ms = int(time.time() * 1000)
                age = 0
                status = "online"

        return {
            "node_id": node_id,
            "label": label,
            "status": status,
            "last_seen_ms": last_seen_ms,
            "age_seconds": age,
            "metrics": metrics,
            "alerts": alerts,
        }

    snapshot = [build_entry(node_id, label) for node_id, label in POD_LABELS.items()]

    # Include any ad-hoc nodes not in POD_LABELS
    for node_id, row in by_node.items():
        if node_id in POD_LABELS:
            continue
        snapshot.append(build_entry(node_id, node_id))

    return snapshot


@app.route("/api/pods")
def pod_status():
    try:
        pods = fetch_pod_snapshot()
    except Exception as exc:
        app.logger.exception("pod_status query failed: %s", exc)
        return jsonify({"error": "db_error"}), 500

    return jsonify(
        {
            "pods": pods,
            "generated_at_ms": int(time.time() * 1000),
            "online_threshold_seconds": ONLINE_THRESHOLD_SECONDS,
        }
    )


@app.route("/api/ap/start", methods=["POST"])
def ap_start():
    _run_script_async("ap_start", AP_SETUP_SCRIPT)
    return jsonify({"status": "started"})


@app.route("/api/ap/stop", methods=["POST"])
def ap_stop():
    _run_script_async("ap_stop", AP_TEARDOWN_SCRIPT)
    return jsonify({"status": "stopping"})


if __name__ == "__main__":
    # For local debugging, but in Docker you're using gunicorn
    app.run(host="0.0.0.0", port=8080, debug=True, threaded=True)
