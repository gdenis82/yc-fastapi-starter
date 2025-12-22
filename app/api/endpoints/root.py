from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from sqlalchemy import text
import os

router = APIRouter()

@router.get("/")
async def read_root():
    return {"message": "Hello from FastAPI on Kubernetes!"}

@router.get("/health")
async def health(db: AsyncSession = Depends(get_db)):
    try:
        # Check DB connection
        await db.execute(text("SELECT 1"))
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        return {"status": "error", "db": str(e)}

@router.get("/pod")
async def get_pod_name():
    return {"pod_name": os.getenv("POD_NAME", "local-development")}
