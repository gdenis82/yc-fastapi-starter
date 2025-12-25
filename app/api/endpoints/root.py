from fastapi import APIRouter, HTTPException
from app.core.logger import logger
from app.core.config import settings
import os
import psycopg2

router = APIRouter()

@router.get("/")
async def read_root():
    logger.debug("Root endpoint called")
    return {"message": "Hello from FastAPI on Kubernetes!"}

@router.get("/health")
async def health():
    return {"status": "ok"}

@router.get("/db-check")
async def db_check():
    if not settings.DATABASE_URL:
        return {"status": "error", "message": "DATABASE_URL is not set"}
    
    try:
        # For psycopg2 connection string from settings
        conn = psycopg2.connect(settings.DATABASE_URL)
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()
        cur.close()
        conn.close()
        return {"status": "ok", "db_version": version[0]}
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        return {"status": "error", "message": str(e)}

@router.get("/pod")
async def get_pod_name():
    pod_name = os.getenv("POD_NAME", "local-development")
    logger.debug(f"Pod name requested: {pod_name}")
    return {"pod_name": pod_name}
