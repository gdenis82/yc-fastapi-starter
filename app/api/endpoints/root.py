from fastapi import APIRouter
from app.core.logger import logger
import os

router = APIRouter()

@router.get("/")
async def read_root():
    logger.debug("Root endpoint called")
    return {"message": "Hello from FastAPI on Kubernetes!"}

@router.get("/health")
async def health():
    return {"status": "ok"}

@router.get("/pod")
async def get_pod_name():
    pod_name = os.getenv("POD_NAME", "local-development")
    logger.debug(f"Pod name requested: {pod_name}")
    return {"pod_name": pod_name}
