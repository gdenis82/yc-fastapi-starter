import pytest
import asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app
import time

@pytest.mark.anyio
async def test_auth_flow():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 0. Register
        email = f"test_{int(time.time())}@example.com"
        reg_data = {
            "username": f"user_{int(time.time())}",
            "email": email,
            "password": "password"
        }
        response = await ac.post("/api/auth/register", json=reg_data)
        assert response.status_code == 200, f"Registration failed: {response.text}"
        
        # 1. Login
        login_data = {
            "username": email,
            "password": "password"
        }
        response = await ac.post("/api/auth/login", data=login_data)
        assert response.status_code == 200, f"Login failed: {response.text}"

        data = response.json()
        access_token = data["access_token"]
        assert access_token is not None
        
        # Check cookies
        assert "refresh_token" in response.cookies, "refresh_token not in cookies"
        refresh_token_cookie = response.cookies.get("refresh_token")

        # 2. Get /me
        headers = {"Authorization": f"Bearer {access_token}"}
        response = await ac.get("/api/auth/me", headers=headers)
        assert response.status_code == 200, "Could not get /me"

        # 3. Refresh
        # Небольшая пауза, чтобы iat (Issued At) в токене изменился, если он измеряется в целых секундах
        await asyncio.sleep(1)
        # Передаем куки вручную или используем куки из клиента (AsyncClient их сохраняет)
        response = await ac.post("/api/auth/refresh")
        assert response.status_code == 200, f"Refresh failed: {response.text}"
        
        new_data = response.json()
        new_access_token = new_data["access_token"]
        assert new_access_token is not None
        assert new_access_token != access_token, "New access token is same as old one"

        # 4. Logout
        response = await ac.post("/api/auth/logout")
        assert response.status_code == 200

        assert "refresh_token" not in ac.cookies or ac.cookies.get("refresh_token") == ""
