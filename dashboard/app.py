from flask import Flask, render_template
import time

app = Flask(__name__)

@app.route("/")
def dashboard():
    return render_template("index.html", ts=int(time.time()), refresh=5)
    # refresh = seconds between SVG reloads (you can change this)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)