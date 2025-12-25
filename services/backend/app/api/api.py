from fastapi import APIRouter
from app.api.endpoints import root

api_router = APIRouter()
api_router.include_router(root.router, tags=["root"])
