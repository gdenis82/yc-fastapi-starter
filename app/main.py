from fastapi import FastAPI
from contextlib import asynccontextmanager
from app.core.logger import logger
from app.api.api import api_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup logic
    logger.info("Application startup complete.")
    yield
    # Shutdown logic
    logger.info("Shutting down gracefully...")

def create_app() -> FastAPI:
    app = FastAPI(
        title="FastAPI Kubernetes Project",
        lifespan=lifespan
    )
    app.include_router(api_router)
    return app

app = create_app()
