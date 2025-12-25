# FastAPI Kubernetes Project

![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Yandex_Cloud](https://img.shields.io/badge/Yandex_Cloud-white?logo=yandexcloud&logoColor=black)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)

Мини-сервис разработан **исключительно в образовательных целях** для демонстрации развертывания масштабируемого приложения в **Yandex Cloud (YC)**. Проект использует управляемые сервисы (Managed Kubernetes, Managed PostgreSQL) и обеспечивает безопасности через Yandex Lockbox.

## Архитектура проекта

```text
.
├── app/                  # Основной код приложения (FastAPI)
│   ├── api/              # Маршрутизация и обработчики (Endpoints)
│   ├── core/             # Конфигурация, логирование, настройки
│   ├── models/           # Модели базы данных (SQLAlchemy)
│   └── main.py           # Точка входа в приложение
├── alembic/              # Миграции базы данных
├── helm/                 # Helm-чарт для развертывания в Kubernetes
├── terraform/            # Инфраструктура как код (Yandex Cloud)
├── Dockerfile            # Инструкция для сборки Docker-образа
├── entrypoint.sh         # Скрипт запуска приложения в контейнере
├── deploy.ps1            # Основной скрипт автоматизированного деплоя
├── prepare-infra.ps1     # Поэтапная подготовка облачной инфраструктуры
├── cleanup.ps1           # Скрипт для удаления всех ресурсов
├── requirements.txt      # Зависимости Python
└── DEPLOY.md             # Подробная инструкция по развертыванию
```

## Развертывание
Подробная инструкция находится в файле [DEPLOY.md](DEPLOY.md).
