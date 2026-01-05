# FastAPI Kubernetes Project

![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-black?logo=next.js&logoColor=white)
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
│   │   │   ├── api/        # API эндпоинты
│   │   │   │   └── endpoints/ # Реализация конкретных роутов (auth, admin и др.)
│   │   │   ├── core/       # Конфигурация, безопасность, логирование
│   │   │   ├── models/     # Модели базы данных (SQLAlchemy)
│   │   │   ├── schemas/    # Pydantic схемы (валидация данных)
│   │   │   ├── db/         # Подключение к БД и сессии
│   │   │   └── main.py     # Точка входа в приложение
│   │   ├── alembic/        # Миграции базы данных
│   │   ├── tests/          # Тесты (pytest)
│   │   └── Dockerfile      # Образ для бэкенда
│   └── frontend/           # Frontend (Next.js)
│       ├── src/
│       │   ├── app/        # Роутинг и страницы (App Router)
│       │   ├── components/ # React компоненты (UI, Auth, Layout)
│       │   ├── store/      # Управление состоянием (Zustand)
│       │   ├── lib/        # Утилиты и конфигурация API (Axios)
│       │   └── proxy.ts    # Конфигурация проксирования
│       └── Dockerfile      # Образ для фронтенда
├── helm/                   # Helm-чарты для деплоя в Kubernetes
├── terraform/              # Infrastructure as Code (Yandex Cloud)
├── deploy.ps1              # Скрипт автоматизированного деплоя
├── prepare-infra.ps1       # Скрипт подготовки инфраструктуры
├── cleanup.ps1             # Скрипт удаления ресурсов
├── Makefile                # Команды для локальной разработки и сборки
└── DEPLOY.md               # Подробная инструкция по развертыванию
```

## Развертывание
1. **Локальное развертывание (Terraform + PowerShell)**: Инструкция в файле [DEPLOY.md](DEPLOY.md).
2. **Автоматизация через GitLab CI/CD**: Инструкция в файле [GITLAB_CI_SETUP.md](GITLAB_CI_SETUP.md).

