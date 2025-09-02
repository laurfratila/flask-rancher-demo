import os
import time
import threading
from pathlib import Path
from flask import Flask, jsonify

app = Flask(__name__)

# Config via env (we'll wire these from ConfigMap/Secret later)
FILE_PATH = os.getenv("APP_FILE_PATH", "/tmp/counter.txt")
WRITE_INTERVAL = int(os.getenv("APP_WRITE_INTERVAL_SECONDS", "30"))
APP_MESSAGE = os.getenv("APP_MESSAGE", "Hello from Flask on Rancher Desktop")
SECRET_TOKEN = os.getenv("APP_SECRET_TOKEN", "not-set")

_counter = 0
_ready = False

def _writer_loop():
    global _counter, _ready
    Path(FILE_PATH).parent.mkdir(parents=True, exist_ok=True)
    _ready = True  # Ready once storage path exists
    while True:
        _counter += 1
        with open(FILE_PATH, "a", encoding="utf-8") as f:
            f.write(f"{int(time.time())},{_counter}\n")
        time.sleep(WRITE_INTERVAL)

# Start the background writer thread
threading.Thread(target=_writer_loop, daemon=True).start()

@app.get("/")
def index():
    # Never echo secrets; just indicate presence
    return jsonify(
        message=APP_MESSAGE,
        counter=_counter,
        file_path=FILE_PATH,
        secret_present=SECRET_TOKEN != "not-set",
    )

@app.get("/health")
def health():
    # 200 only after the app has created/validated the write path
    return ("ok" if _ready else "starting"), (200 if _ready else 503)

if __name__ == "__main__":
    # Local dev run; container will use gunicorn later
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
