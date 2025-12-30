# Инструкция по развертыванию приложения в Yandex Cloud Managed Service for Kubernetes

## 0. Предварительные требования

Перед началом убедитесь, что у вас установлены необходимые инструменты:

1.  **YC CLI**: [Инструкция по установке](https://cloud.yandex.ru/docs/cli/operations/install-cli).
    *   После установки выполните `yc init`.
2.  **Docker**: [Docker Desktop](https://www.docker.com/products/docker-desktop) (убедитесь, что он запущен).
3.  **Terraform**: [Скачать Terraform](https://www.terraform.io/downloads).
4.  **kubectl**: [Установка kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/).
5.  **Helm**: [Установка Helm](https://helm.sh/docs/intro/install/).

---

## 1. Подготовка инфраструктуры (Terraform)

### Шаги настройки:
1. Создайте и заполните переменные в файле `terraform/terraform.tfvars`:
    - `folder_id` = "your_folder_id"
    - `cloud_id`  = "your_cloud_id"
    - `domain_name` = "your-domain.com"
    - `service_account_key_file` = "sa-key.json"

2.  **Создайте сервисный аккаунт для Terraform (Bootstrap):**
    Если у вас еще нет `sa-key.json`, выполните команды из корня проекта:
    ```powershell
    $FOLDER_ID = (Get-Content terraform/terraform.tfvars | Select-String "folder_id" | ForEach-Object { $_.ToString().Split('"')[1] })
    yc iam service-account create --name tf-bootstrap --folder-id $FOLDER_ID
    $SA_ID = (yc iam service-account get tf-bootstrap --format json | ConvertFrom-Json).id
    yc resource-manager folder add-access-binding $FOLDER_ID --role admin --subject "serviceAccount:$SA_ID"
    yc iam key create --service-account-name tf-bootstrap --output terraform/sa-key.json
    ```

---

## 2. Поэтапное развертывание
### 2.1 Локальное (через PowerShell)
Для надежного развертывания используется скрипт `deploy.ps1`, который вызывает `prepare-infra.ps1` для поэтапной подготовки облачных ресурсов.
### 2.2 Автоматическое (через GitLab CI/CD)
В проекте настроен монорепозиторный пайплайн. При пуше в `main` GitLab автоматически определяет измененный сервис и запускает его деплой. Подробнее в [GITLAB_CI_SETUP.md](GITLAB_CI_SETUP.md).

### Запуск локального деплоя:
```powershell
.\deploy.ps1
```

### Что происходит при запуске:

**Этап 0: Подготовка инфраструктуры (`prepare-infra.ps1`)**
- Скрипт проверяет готовность Registry, K8s Cluster и PostgreSQL Cluster.
- Если PostgreSQL еще создается (статус `CREATING`), скрипт будет ждать его готовности (`RUNNING`).
- Выполняется финальный `terraform apply` для синхронизации всех данных (включая FQDN базы данных) в **Yandex Lockbox**.

**Этап 1: Сборка и загрузка образов**
- Docker-образы (backend и frontend) собираются с тегом времени (`yyyyMMdd-HHmmss`) и пушатся в Container Registry.
- **Важно**: При сборке фронтенда публичный адрес API (`https://<domain>/api`) вшивается в билд через `--build-arg NEXT_PUBLIC_API_URL`.

**Этап 2: Настройка Kubernetes и секретов**
- Конфигурируется `kubectl`.
- Устанавливаются **Ingress NGINX** и **cert-manager**.
- Из **Lockbox** извлекаются секреты: `SECRET_KEY` и отдельные параметры базы данных (`db_host`, `db_user`, `db_password` и др.).
- Создается K8s Secret `fastapi-app-secrets`, который используется и приложением, и миграциями.

**Этап 3: Миграции базы данных (Alembic)**
- Перед обновлением основного приложения запускается **Kubernetes Job** для выполнения миграций (`alembic upgrade head`).
- Образ для миграций совпадает с образом бэкенда.
- Деплой приложения продолжается только после **успешного** завершения Job.

**Этап 4: Деплой приложения**
- Helm обновляет приложение. Используются 2 реплики для обеспечения отказоустойчивости.
- Настраивается Ingress с автоматическим получением SSL-сертификата от Let's Encrypt.

---

## 3. Настройка базы данных и безопасность

Для надежной работы с базой данных (особенно при наличии спецсимволов в паролях) проект перешел на использование **раздельных переменных** в Yandex Lockbox:

- `db_host`: FQDN хоста базы данных.
- `db_port`: Порт (по умолчанию 6432 для Odyssey).
- `db_user`: Имя пользователя.
- `db_password`: Пароль (используется напрямую, без парсинга строки).
- `db_name`: Имя базы данных.
- `db_ssl_mode`: Режим SSL (например, `verify-full`).

**Преимущества этого подхода:**
1. **Безопасность**: Пароли со знаками `@`, `:`, `?` больше не ломают парсинг `DATABASE_URL`.
2. **Гибкость**: Приложение само собирает строку подключения, используя `sqlalchemy.engine.URL.create`.
3. **SSL**: Соединение защищено. Корневой сертификат Yandex Cloud (`root.crt`) автоматически скачивается в Docker-образ по пути `/root/.postgresql/root.crt`.

---

## 4. Проверка статуса

После завершения скрипта:
- Проверьте доступность: `https://your-domain.com/`
- Проверьте соединение с БД: `https://your-domain.com/db-check`
- Проверьте сертификат: `kubectl get certificate`

## 5. Очистка ресурсов

Для удаления всей инфраструктуры (будьте осторожны!):
```powershell
.\cleanup.ps1
```
Введите `DESTROY` при запросе.

---

## 6. Решение проблем (Troubleshooting)

### Ошибка "Database connection error"
1. Проверьте логи пода: `kubectl logs -l app.kubernetes.io/name=fastapi-chart`
2. Убедитесь, что Security Groups разрешают доступ от K8s к Postgres (настраивается автоматически в `main.tf`).
3. Проверьте статус секрета: `kubectl get secret fastapi-app-secrets -o yaml`

### Ошибка миграций
Если Job миграций упал, проверьте его логи:
```powershell
kubectl logs job/fastapi-migrate-<revision>
```
Скрипт `deploy.ps1` автоматически выводит логи при ошибке миграции.
