import logging
import sys
import os

# Настраиваем логгер приложения
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logger = logging.getLogger("app")
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# Если обработчиков еще нет, добавляем их
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
    )
    logger.addHandler(handler)

# Настройка логирования для uvicorn/gunicorn, если нужно
logging.getLogger("uvicorn.access").handlers = logger.handlers
logging.getLogger("uvicorn.error").handlers = logger.handlers
logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)

