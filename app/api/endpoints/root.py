from fastapi import APIRouter
import os

router = APIRouter()

@router.get("/")
async def read_root():
    return {"message": "Hello from FastAPI on Kubernetes!"}

@router.get("/health")
async def health():
    return {"status": "ok"}

@router.get("/pod")
async def get_pod_name():
    return {"pod_name": os.getenv("POD_NAME", "local-development")}
