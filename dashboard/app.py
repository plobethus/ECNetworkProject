from flask import Flask # type: ignore
app = Flask(__name__)

@app.get("/")
def home():
    return "Dashboard Placeholder — Grafana recommended for full visualization"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
