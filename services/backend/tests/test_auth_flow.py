import pytest
from fastapi.testclient import TestClient
from app.main import app
import time

client = TestClient(app)

def test_auth_flow():
    # 0. Register
    email = f"test_{int(time.time())}@example.com"
    reg_data = {
        "username": f"user_{int(time.time())}",
        "email": email,
        "password": "password"
    }
    response = client.post("/api/auth/register", json=reg_data)
    assert response.status_code == 200, f"Registration failed: {response.text}"
    
    # 1. Login
    # FastAPI OAuth2PasswordRequestForm ожидает данные в формате form-data
    login_data = {
        "username": email,
        "password": "password"
    }
    response = client.post("/api/auth/login", data=login_data)
    assert response.status_code == 200, f"Login failed: {response.text}"

    data = response.json()
    access_token = data["access_token"]
    assert access_token is not None
    
    # Check cookies
    assert "refresh_token" in client.cookies, "refresh_token not in cookies"

    # 2. Get /me
    headers = {"Authorization": f"Bearer {access_token}"}
    response = client.get("/api/auth/me", headers=headers)
    assert response.status_code == 200, "Could not get /me"

    # 3. Refresh
    # TestClient сохраняет куки между запросами
    response = client.post("/api/auth/refresh")
    assert response.status_code == 200, f"Refresh failed: {response.text}"
    
    new_data = response.json()
    new_access_token = new_data["access_token"]
    assert new_access_token is not None
    assert new_access_token != access_token, "New access token is same as old one"

    # 4. Logout
    response = client.post("/api/auth/logout")
    assert response.status_code == 200

    assert "refresh_token" not in client.cookies or client.cookies.get("refresh_token") == ""
