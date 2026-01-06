from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_read_main():
    response = client.get("/api/")
    assert response.status_code == 200

def test_health():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_redis_check():
    response = client.get("/api/redis-check")
    # We might not have redis running during tests if not configured, 
    # but the route should exist and return 200 (even with error status in json)
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
