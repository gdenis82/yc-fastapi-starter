from fastapi import APIRouter
from app.api.endpoints import root, auth, admin, password

api_router = APIRouter()
api_router.include_router(root.router, tags=["root"])
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
api_router.include_router(password.router, prefix="/auth", tags=["auth"])
