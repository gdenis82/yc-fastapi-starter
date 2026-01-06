import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_redis_check():
    response = client.get("/api/redis-check")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    
    # Тест должен падать, если Redis не доступен, 
    # чтобы CI/CD сигнализировал о проблемах с конфигурацией или связью.
    assert data["status"] == "ok", f"Redis check failed: {data.get('message')}"
    assert "redis_ping" in data
    assert data["redis_ping"] is True
