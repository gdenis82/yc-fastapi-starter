from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
import time
from contextlib import asynccontextmanager
from app.core.config import settings
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
        try:
            response = await call_next(request)
        except Exception as e:
            logger.exception(f"Unhandled exception during request: {e}")
            from fastapi.responses import JSONResponse
            response = JSONResponse(
                status_code=500,
                content={"detail": "Internal Server Error"}
            )
        
        duration = time.time() - start_time
        logger.info(
            f"Method: {request.method} Path: {request.url.path} "
            f"Status: {response.status_code} Duration: {duration:.4f}s"
        )
        return response

    # Configure CORS - added AFTER other middlewares to be processed FIRST for responses
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    app.include_router(api_router, prefix="/api")
    return app

app = create_app()
