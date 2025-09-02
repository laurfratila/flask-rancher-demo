# ---------- builder stage ----------
FROM python:3.12-slim AS builder

# Avoid prompts; speed up installs
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# System deps for building wheels if needed later
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m venv /opt/venv && /opt/venv/bin/pip install -r requirements.txt

# ---------- runtime stage ----------
FROM python:3.12-slim AS runtime

# Create non-root user and app/data dirs
RUN groupadd -r app && useradd -r -g app appuser \
    && mkdir -p /app /data \
    && chown -R appuser:app /app /data

# Copy virtualenv from builder
COPY --from=builder /opt/venv /opt/venv

# Put venv on PATH
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app ./app

# Expose gunicorn port
EXPOSE 8000

# Healthcheck hits our Flask /health endpoint
# curl is tiny on slim; safe to use for clarity
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/health || exit 1

# Run as non-root
USER appuser

# Default env: write to a bind/PVC mount we’ll add later
ENV APP_FILE_PATH=/data/counter.txt \
    APP_WRITE_INTERVAL_SECONDS=10 \
    APP_MESSAGE="Hello from container"

# Gunicorn server (production-safe)
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "app.main:app"]
