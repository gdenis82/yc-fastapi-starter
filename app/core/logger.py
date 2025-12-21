import logging
import sys

# 📝 Настраиваем логгер приложения
logger = logging.getLogger("app")
logger.setLevel(logging.INFO)

# Если обработчиков еще нет, добавляем их
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    )
    logger.addHandler(handler)

