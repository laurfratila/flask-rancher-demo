# Flask Rancher Demo

Small Flask app for Docker + Kubernetes (Rancher Desktop) exercises:
- `/health` endpoint for container HEALTHCHECK and k8s probes
- Background writer appends a counter to a file every X seconds (`APP_WRITE_INTERVAL_SECONDS`)
- File path configurable via `APP_FILE_PATH` (will later be a PVC mount)

## Env Vars
- `APP_MESSAGE` (ConfigMap)
- `APP_FILE_PATH` (ConfigMap) — default `/tmp/counter.txt`
- `APP_WRITE_INTERVAL_SECONDS` (ConfigMap) — default `30`
- `APP_SECRET_TOKEN` (Secret)

## Local run
```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app/main.py
