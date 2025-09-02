# Flask Rancher Demo - Optional Homework

A minimal, production-lean Flask service containerized with Docker and deployed to Kubernetes via **Rancher Desktop (k3s)**. It showcases:

- Non‑root container, multi‑stage build, and Docker **HEALTHCHECK**
- Kubernetes **ConfigMap** + **Secret** injected as env vars
- **Readiness**/**Liveness** probes
- **PersistentVolumeClaim (PVC)** for durable app data
- **Ingress** with Traefik (plus localhost port‑forward fallback)
- **Horizontal Pod Autoscaler (HPA)** (2–5 replicas @ 50% CPU)

---

## What was built

**What:** A small Flask API that:
- Serves `/` returning a JSON payload
- Serves `/health` for probes/health checks
- Runs a background thread that appends `timestamp,counter` to a file every X seconds (configurable)

**Why this helps:**
- **Cloud‑native patterns** (probes, config, secret, autoscaling) in one place.
- **Persistence demo**: The counter file persists through pod restarts via PVC.
- **Operational readiness**: HEALTHCHECK + probes = safer rollouts & self‑healing.
- **Security posture**: Non‑root user, least privilege, no secret echoing.

---

## Repo structure

```
flask-rancher-demo/
├─ app/
│  └─ main.py                 # Flask app (/ and /health, background writer)
├─ k8s/
│  ├─ namespace.yaml          # Namespace: flask-demo
│  ├─ configmap.yaml          # Non‑secret config (message, interval, file path)
│  ├─ secret.yaml             # Secret (APP_SECRET_TOKEN)
│  ├─ pvc.yaml                # Persistent volume claim
│  ├─ deployment.yaml         # Deployment + probes + volume + securityContext
│  ├─ service.yaml            # ClusterIP service on 8000
│  ├─ ingress.yaml            # Traefik Ingress (host rule)
│  └─ hpa.yaml                # Horizontal Pod Autoscaler (2–5 pods @ 50% CPU)
├─ Dockerfile                 # Multi‑stage, non‑root, HEALTHCHECK
├─ .dockerignore              # Keep image small
├─ requirements.txt           # Flask + Gunicorn
├─ README.md                  # (this file)
└─ rd-data/                   # (optional) host bind‑mount for local container runs
```

---

## Requirements

- **Rancher Desktop** with Kubernetes enabled (k3s) and **Traefik** Ingress on
- **kubectl** (bundled with Rancher Desktop)
- **Docker** or **nerdctl** (Rancher Desktop provides either)
- **Windows PowerShell** or Bash

---

## App configuration (env vars)

| Variable | Purpose | Default |
|---|---|---|
| `APP_MESSAGE` | Message shown on `/` | `"Hello from Flask on Rancher Desktop"` (container) / set via ConfigMap (k8s) |
| `APP_WRITE_INTERVAL_SECONDS` | Write frequency | `10` (container) / set via ConfigMap |
| `APP_FILE_PATH` | Path to counter file | `/data/counter.txt` (container) / set via ConfigMap |
| `APP_SECRET_TOKEN` | Secret token (not echoed) | `not-set` locally; provided by Secret in k8s |

---

## Quick start — Local Python (optional)

```powershell
python -m venv .venv
. .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:APP_WRITE_INTERVAL_SECONDS = "5"
$env:APP_FILE_PATH = "C:\\Temp\\counter.txt"
python .\app\main.py
# New terminal:
curl.exe http://127.0.0.1:5000/health
```

---

## Quick start — Docker

### Build
```powershell
docker build -t flask-rancher-demo:dev .
```

### Run (Windows; bind‑mount to persist locally)
```powershell
mkdir rd-data -Force | Out-Null

docker run --rm -d `
  --name flask-demo `
  -p 8000:8000 `
  -e APP_WRITE_INTERVAL_SECONDS=5 `
  -v "$PWD/rd-data:/data" `
  flask-rancher-demo:dev

curl.exe http://127.0.0.1:8000/health
```

> Why: non‑root container writes to `/data` so you can watch `rd-data/counter.txt` grow.

---

## Kubernetes on Rancher Desktop — Step by step

> Namespace used: `flask-demo`

### 1) Apply core manifests
```powershell
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Verify pod readiness:
```powershell
kubectl -n flask-demo wait --for=condition=available deploy/flask-demo --timeout=120s
kubectl -n flask-demo get pods -o wide
```

### 2) Ingress

Rancher Desktop often exposes Traefik on a VM IP (e.g., `192.168.127.2`). Two ways to reach your Ingress:

**A) Localhost via port‑forward (works everywhere)**
```powershell
kubectl -n kube-system port-forward svc/traefik 18080:80  # keep this running
# In a new terminal, use the Host header configured in k8s/ingress.yaml:
curl.exe -H "Host: <your-ingress-host>" http://127.0.0.1:18080/health
```

**B) DNS host that encodes the IP**

If your Ingress `ADDRESS` is `192.168.127.2`, set `host: flask.192.168.127.2.sslip.io` in `k8s/ingress.yaml` and re‑apply. Then you can call:
```powershell
curl.exe http://flask.192.168.127.2.sslip.io/health
```

> If you can’t reach Traefik IP directly, use option A with the Host header.

Apply Ingress:
```powershell
kubectl apply -f k8s/ingress.yaml
kubectl get ingress -n flask-demo
```

### 3) HPA (autoscaling)
```powershell
kubectl apply -f k8s/hpa.yaml
kubectl -n flask-demo get hpa
```
Requirements for HPA to show `%/50%` instead of `<unknown>`:
- Set **resources** on the container (already in `deployment.yaml`):
  ```yaml
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 256Mi }
  ```
- Ensure **metrics-server** is running in `kube-system`.

---

## How to **verify** everything (the important part)

### A) Ingress works
```powershell
kubectl -n kube-system port-forward svc/traefik 18080:80
curl.exe -H "Host: <your-ingress-host>" http://127.0.0.1:18080/health   # expect: ok
curl.exe -H "Host: <your-ingress-host>" http://127.0.0.1:18080/          # expect: JSON
```

### B) ConfigMap update → rollout → verify
```powershell
# Update message (PowerShell‑safe patch)
@'
{
  "data": { "APP_MESSAGE": "Hello from ConfigMap via Ingress" }
}
'@ | Out-File -FilePath .\k8s\patch-config.json -Encoding ascii

kubectl -n flask-demo patch configmap app-config --type merge --patch-file .\k8s\patch-config.json
kubectl -n flask-demo rollout restart deploy/flask-demo
kubectl -n flask-demo rollout status deploy/flask-demo

curl.exe -s -H "Host: <your-ingress-host>" http://127.0.0.1:18080/ | ConvertFrom-Json | Format-List
# Expect: message = "Hello from ConfigMap via Ingress"
```

### C) PVC persistence
```powershell
$POD = kubectl -n flask-demo get pod -l app=flask-demo -o jsonpath="{.items[0].metadata.name}"
kubectl -n flask-demo exec -it $POD -- sh -lc "tail -n 5 /data/counter.txt"

kubectl -n flask-demo delete pod $POD
kubectl -n flask-demo get pods -w  # wait until new pod is Ready

$NEWPOD = kubectl -n flask-demo get pod -l app=flask-demo -o jsonpath="{.items[0].metadata.name}"
kubectl -n flask-demo exec -it $NEWPOD -- sh -lc "tail -n 10 /data/counter.txt"
# Expect: file exists and counter continued (PVC survived)
```

### D) Probes are active
```powershell
kubectl -n flask-demo describe pod -l app=flask-demo | Select-String -Pattern "Readiness probe", "Liveness probe", "Started container"
```
You’ll see readiness/liveness probe events. To simulate a failure, just delete the pod (Kubernetes self‑heals):
```powershell
kubectl -n flask-demo delete pod -l app=flask-demo
```

### E) HPA shows targets & scales
```powershell
kubectl -n flask-demo get hpa  # expect: e.g., 1%/50%
```
Generate a bit of load (with Traefik port‑forward running):
```powershell
for ($i=0; $i -lt 3000; $i++) { curl.exe -s -H "Host: <your-ingress-host>" http://127.0.0.1:18080/ > $null }
```
Watch scale up/down:
```powershell
kubectl -n flask-demo get pods -w
kubectl -n flask-demo get hpa
```

---

## What we obtained (outcomes)

- **Container best practices**: Small image, non‑root user, HEALTHCHECK.
- **12‑factor config**: Env‑driven via ConfigMap/Secret; easy rollouts.
- **Resilience**: Probes + Deployment strategy enable safe, automated recovery.
- **Durability**: PVC retains data between pod restarts.
- **Scalability**: HPA adds pods under CPU pressure and scales down when idle.
- **Portability**: Works with Rancher Desktop locally; the same manifests map to real clusters.

---

## Troubleshooting

- **`Could not resolve host` for Ingress**: Use Traefik **port‑forward** and the **Host** header. Or use an IP‑encoded DNS like `sslip.io` (e.g., `flask.<IP>.sslip.io`).
- **404 from Traefik**: Host mismatch. Use exactly the `host:` set in `ingress.yaml` via `-H "Host: ..."`.
- **Port 8080 busy**: Use another local port for Traefik forward, e.g., `18080:80`.
- **Permission denied writing `/data`**: Ensure `securityContext` in the pod and that the volume is mounted at `/data`.
- **HPA `cpu: <unknown>/50%`**: Add `resources.requests.cpu` to the container and verify metrics‑server is running.
- **Pod metrics not available**: Patch metrics‑server with `--kubelet-insecure-tls` and preferred address types; wait 1–2 minutes, then `kubectl top pods`.

---

## Makefile (optional convenience)

Targets you can add to a `Makefile` for one‑liners:

```make
IMAGE?=flask-rancher-demo:dev

build:
	docker build -t $(IMAGE) .

run:
	docker run --rm -d --name flask-demo -p 8000:8000 -v $(PWD)/rd-data:/data $(IMAGE)

stop:
	-docker rm -f flask-demo

k8s-apply:
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/configmap.yaml
	kubectl apply -f k8s/secret.yaml
	kubectl apply -f k8s/pvc.yaml
	kubectl apply -f k8s/deployment.yaml
	kubectl apply -f k8s/service.yaml
	kubectl apply -f k8s/ingress.yaml
	kubectl apply -f k8s/hpa.yaml

k8s-clean:
	kubectl delete -f k8s/hpa.yaml --ignore-not-found
	kubectl delete -f k8s/ingress.yaml --ignore-not-found
	kubectl delete -f k8s/service.yaml --ignore-not-found
	kubectl delete -f k8s/deployment.yaml --ignore-not-found
	kubectl delete -f k8s/pvc.yaml --ignore-not-found
	kubectl delete -f k8s/secret.yaml --ignore-not-found
	kubectl delete -f k8s/configmap.yaml --ignore-not-found
	kubectl delete -f k8s/namespace.yaml --ignore-not-found
```

---

## Security notes

- The container runs as a **non‑root** user and writes only to `/data`.
- The app never echoes `APP_SECRET_TOKEN`; it only reports whether a secret is present.
- Always treat the `secret.yaml` content as sensitive; in real environments prefer external secret stores.

---

## License
MIT 

