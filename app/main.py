"""A tiny HTTP service with the endpoints Kubernetes and Prometheus expect.

/health   liveness: the process is alive
/ready    readiness: the app can take traffic (503 when it cannot)
/metrics  Prometheus text format
/         a greeting that shows the config coming from the ConfigMap/Secret
"""

import os

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest

app = FastAPI(title="k8s-platform-app")

REQUESTS = Counter("app_requests_total", "Requests served", ["path"])

VERSION = os.getenv("APP_VERSION", "dev")


def is_ready() -> bool:
    # The "broken" image sets APP_BROKEN=1. It starts fine, but never reports
    # ready, which is what the rollback demo in CI relies on.
    return os.getenv("APP_BROKEN", "0") != "1"


@app.get("/")
def index():
    REQUESTS.labels(path="/").inc()
    return {
        "message": os.getenv("GREETING", "hello"),
        "environment": os.getenv("APP_ENV", "local"),
        "version": VERSION,
        "pod": os.getenv("HOSTNAME", "unknown"),
        # Only says whether the secret arrived, never prints it.
        "api_key_set": bool(os.getenv("API_KEY")),
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready(response: Response):
    if not is_ready():
        response.status_code = 503
        return {"status": "not ready"}
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
