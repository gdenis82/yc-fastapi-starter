from fastapi import FastAPI, Request
import time
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
    
    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        start_time = time.time()
        response = await call_next(request)
        duration = time.time() - start_time
        logger.info(
            f"Method: {request.method} Path: {request.url.path} "
            f"Status: {response.status_code} Duration: {duration:.4f}s"
        )
        return response

    app.include_router(api_router)
    return app

app = create_app()
