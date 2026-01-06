from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.logger import logger
from app.core.config import settings
from app.db.session import get_db
import os
import psycopg2

router = APIRouter()

@router.get("/")
async def read_root():
    logger.debug("Root endpoint called")
    return {"message": f"Hello from {settings.PROJECT_NAME}!"}

@router.get("/health")
async def health():
    return {"status": "ok"}

@router.get("/db-check")
async def db_check(db: AsyncSession = Depends(get_db)):
    if not settings.DATABASE_URL:
        return {"status": "error", "message": "DATABASE_URL is not set"}
    
    try:
        # Check using SQLAlchemy session
        from sqlalchemy import text
        result = await db.execute(text("SELECT version();"))
        version = result.fetchone()
        return {"status": "ok", "db_version": version[0]}
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        return {"status": "error", "message": str(e)}

@router.get("/pod")
async def get_pod_name():
    pod_name = os.getenv("POD_NAME", "local-development")
    logger.debug(f"Pod name requested: {pod_name}")
    return {"pod_name": pod_name}

@router.get("/redis-check")
async def redis_check():
    from app.core.redis import redis_client
    try:
        ping = await redis_client.ping()
        return {"status": "ok", "redis_ping": ping}
    except Exception as e:
        logger.error(f"Redis connection error: {e}")
        return {"status": "error", "message": str(e)}
