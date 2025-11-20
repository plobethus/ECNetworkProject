from flask import Flask, render_template, Response, stream_with_context
import queue
import time
import sys

app = Flask(__name__)

# Simple in-process queue for SSE
event_queue = queue.Queue()


@app.route("/")
def index():
    # Pass an initial cache-buster so first load gets the latest charts
    return render_template("index.html", ts=int(time.time() * 1000))


def event_stream():
    """Generator that yields SSE events as they arrive."""
    while True:
        event = event_queue.get()  # blocks until something is put()
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
        event_queue.put_nowait("chart_update")
    except Exception as e:
        app.logger.exception("Failed to enqueue chart_update: %s", e)
    return "ok"


if __name__ == "__main__":
    # For local debugging, but in Docker you're using gunicorn
    app.run(host="0.0.0.0", port=8080, debug=True, threaded=True)