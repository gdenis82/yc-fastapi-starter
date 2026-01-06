import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_redis_check():
    response = client.get("/api/redis-check")
    # Мы не можем гарантировать, что Redis доступен в среде запуска тестов, 
    # но мы можем проверить, что эндпоинт возвращает ожидаемую структуру.
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    if data["status"] == "ok":
        assert "redis_ping" in data
        assert data["redis_ping"] is True
    else:
        assert "message" in data
