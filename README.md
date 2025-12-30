# FastAPI Kubernetes Project

![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Yandex_Cloud](https://img.shields.io/badge/Yandex_Cloud-white?logo=yandexcloud&logoColor=black)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![GitLab CI/CD](https://img.shields.io/badge/GitLab_CI%2FCD-FC6D26?logo=gitlab&logoColor=white)

Мини-сервис разработан **исключительно в образовательных целях** для демонстрации развертывания масштабируемого приложения в **Yandex Cloud (YC)**. Проект использует управляемые сервисы (Managed Kubernetes, Managed PostgreSQL) и обеспечивает безопасность через Yandex Lockbox.

## Структура проекта

```text
.
├── services/
│   ├── backend/            # Микросервис Backend (FastAPI)
│   │   ├── app/
│   │   │   ├── api/        # Эндпоинты (теперь с префиксом /api)
│   │   │   ├── core/       # Конфигурация (Pydantic Settings), логирование
│   │   │   ├── models/     # Модели базы данных (SQLAlchemy)
│   │   │   ├── schemas/    # Pydantic схемы
│   │   │   ├── db/         # Подключение к БД (использует отдельные параметры)
│   │   │   └── main.py     # Точка входа
│   │   ├── alembic/        # Миграции (Alembic)
│   │   ├── Dockerfile      # Сборка с поддержкой SSL-сертификатов YC
│   │   └── entrypoint.sh   # Скрипт запуска
│   └── frontend/           # Frontend (Next.js)
│       ├── src/            # Исходный код
│       └── Dockerfile      # Сборка с вшиванием NEXT_PUBLIC_API_URL
├── helm/                   # Helm-чарты для Kubernetes (Backend & Frontend)
├── terraform/              # Инфраструктура как код (Yandex Cloud)
├── deploy.ps1              # Основной скрипт автоматизированного деплоя
├── prepare-infra.ps1       # Скрипт подготовки инфраструктуры
├── cleanup.ps1             # Скрипт удаления ресурсов
└── DEPLOY.md               # Инструкция по развертыванию
```

## Развертывание
1. **Локальное развертывание (Terraform + PowerShell)**: Инструкция в файле [DEPLOY.md](DEPLOY.md).
2. **Автоматизация через GitLab CI/CD**: Инструкция в файле [GITLAB_CI_SETUP.md](GITLAB_CI_SETUP.md).

