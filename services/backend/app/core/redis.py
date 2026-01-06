import redis.asyncio as redis
from app.core.config import settings

redis_client = redis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    db=settings.REDIS_DB,
    password=settings.REDIS_PASSWORD,
    socket_connect_timeout=settings.REDIS_CONNECT_TIMEOUT,
    socket_timeout=settings.REDIS_READ_TIMEOUT,
    decode_responses=True,
)
