from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_ready_when_healthy():
    assert client.get("/ready").status_code == 200


def test_not_ready_when_broken(monkeypatch):
    monkeypatch.setenv("APP_BROKEN", "1")
    assert client.get("/ready").status_code == 503
    # liveness stays green: the pod is alive, it just must not get traffic
    assert client.get("/health").status_code == 200


def test_index_reads_config_and_hides_secret(monkeypatch):
    monkeypatch.setenv("GREETING", "hi")
    monkeypatch.setenv("APP_ENV", "dev")
    monkeypatch.setenv("API_KEY", "super-secret")
    body = client.get("/").json()
    assert body["message"] == "hi"
    assert body["environment"] == "dev"
    assert body["api_key_set"] is True
    assert "super-secret" not in str(body)


def test_metrics_counts_requests():
    client.get("/")
    text = client.get("/metrics").text
    assert 'app_requests_total{path="/"}' in text
