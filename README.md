# FastAPI Kubernetes Project

![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Yandex_Cloud](https://img.shields.io/badge/Yandex_Cloud-white?logo=yandexcloud&logoColor=black)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)

Мини-сервис разработан **исключительно в образовательных целях** для демонстрации развертывания масштабируемого приложения в **Yandex Cloud (YC)**. Проект использует управляемые сервисы (Managed Kubernetes, Managed PostgreSQL) и обеспечивает безопасность через Yandex Lockbox.

## Архитектура проекта

```text
.
├── services/
│   └── backend/            # Микросервис Backend (FastAPI)
│       ├── app/
│       │   ├── api/        # Эндпоинты
│       │   ├── core/       # Конфигурация, логирование
│       │   ├── models/     # Модели базы данных
│       │   ├── schemas/    # Pydantic схемы
│       │   ├── db/         # Подключение к БД
│       │   └── main.py     # Точка входа
│       ├── alembic/        # Миграции (внутри сервиса)
│       ├── Dockerfile      # Сборка сервиса
│       └── entrypoint.sh   # Скрипт запуска
├── helm/                   # Helm-чарт для Kubernetes
├── terraform/              # Инфраструктура как код (Yandex Cloud)
├── docker-compose.yml      # Локальная разработка
├── Makefile                # Удобные команды (make up, make migrate)
├── .gitlab-ci.yml          # Настройка CI/CD
├── deploy.ps1              # Скрипт автоматизированного деплоя
└── DEPLOY.md               # Инструкция по развертыванию
```

## Развертывание
Подробная инструкция находится в файле [DEPLOY.md](DEPLOY.md).
