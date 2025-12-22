# Инструкция по развертыванию приложения в Yandex Cloud Managed Service for Kubernetes

## 0. Предварительные требования

Перед началом убедитесь, что у вас установлены необходимые инструменты:

1.  **YC CLI**: [Инструкция по установке](https://cloud.yandex.ru/docs/cli/operations/install-cli).
    *   После установки выполните `yc init`.
2.  **Docker**: [Docker Desktop](https://www.docker.com/products/docker-desktop) (убедитесь, что он запущен).
3.  **Terraform**: [Скачать Terraform](https://www.terraform.io/downloads).
    *   **Важно для Windows**: 
        1. Скачайте ZIP-архив.
        2. Распакуйте `terraform.exe` в папку (например, `C:\terraform`).
        3. Добавьте путь к этой папке в системную переменную `PATH`:
           * Нажмите `Win + R`, введите `sysdm.cpl`, вкладка **Дополнительно** -> **Переменные среды**.
           * В разделе **Системные переменные** найдите `Path`, нажмите **Изменить** -> **Создать** -> введите `C:\terraform`.
        4. Перезапустите терминал.
4.  **kubectl**: [Установка kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/).
5.  **Helm**: [Установка Helm](https://helm.sh/docs/intro/install/).
    *   **Для Windows (через Winget)**: `winget install Helm.Helm`
    *   **Вручную**: Скачайте бинарный файл, распакуйте и добавьте в `PATH` (аналогично Terraform).

## 1. Подготовка инфраструктуры (Terraform)

### Шаги настройки:
1. Создайте и заполните переменные в файле `terraform.tfvars`:
    - folder_id = "your_folder_id"
    - cloud_id  = "your_cloud_id"
    - service_account_key_file = "sa-key.json"
    
2.  **Создайте временный ключ (Bootstrap):**
    Если у вас еще нет `sa-key.json`, выполните эти команды в PowerShell (заменив `<FOLDER_ID>` на ваш ID из `terraform.tfvars`).
    
    **Важно:** Убедитесь, что вы находитесь в корне проекта. Проверьте `README.md` для понимания структуры проекта.

    ```powershell
    $FOLDER_ID = "<FOLDER_ID>"

    # Создать сервисный аккаунт
    yc iam service-account create --name tf-bootstrap --folder-id $FOLDER_ID

    # Получить ID созданного аккаунта
    $SA_ID = (yc iam service-account get tf-bootstrap --format json | ConvertFrom-Json).id

    # Назначить роль admin
    yc resource-manager folder add-access-binding $FOLDER_ID --role admin --subject "serviceAccount:$SA_ID"

    # Выпустить JSON ключ в папку terraform/
    yc iam key create --service-account-name tf-bootstrap --output terraform/sa-key.json
    ```

    *Примечание: Если вы уже перешли в папку `terraform/`, используйте `--output sa-key.json`.*

3.  **Проверьте `terraform/terraform.tfvars`:**
    Убедитесь, что там раскомментирована строка с ключом и указан ваш домен:
    ```hcl
    service_account_key_file = "sa-key.json"
    domain_name = "tryout.site"
    ```

4.  **Инициализация и запуск:**
    ```powershell
    cd terraform
    terraform init
    terraform plan

    # При выполнении apply Terraform автоматически сгенерирует безопасные пароли (UUID),
    # если они еще не созданы, и сохранит их в Yandex Lockbox.
    terraform apply -auto-approve
    cd ..
    ```
    *После успешного выполнения `terraform apply` в консоли появятся `cluster_id`, `registry_id` и `lockbox_secret_id`. Они будут автоматически использованы на следующем этапе. Теперь создается Regional-кластер (High Availability) с мастерами в трех зонах и группой узлов из 2-х нод в разных зонах (`ru-central1-a`, `ru-central1-b`).*

## 2. Сборка и деплой (Автоматизировано)

Для автоматизации сборки образа и развертывания через **Helm** используйте скрипт `deploy.ps1`.

1. Убедитесь, что `terraform apply` выполнен успешно.
2. Запустите скрипт из корня проекта:
   ```powershell
   .\deploy.ps1
   ```

Скрипт выполняет следующие действия:
- Получает ID ресурсов (Registry, Cluster, External IP, Lockbox) из Terraform.
- Если секреты в Lockbox еще не созданы, он автоматически генерирует надежные пароли (UUID).
- Собирает и пушит Docker-образ в Yandex Container Registry с уникальным тегом (дата-время).
- Настраивает `kubectl` на ваш кластер.
- Устанавливает/обновляет **Ingress NGINX** и **cert-manager**.
- Безопасно извлекает секреты из **Yandex Lockbox** и создает `Secret` объекты в Kubernetes (без передачи в аргументах Helm).
- Выполняет `helm upgrade --install` для приложения, передавая настройки подключения к БД.
- Привязывает статический IP к Ingress-контроллеру.

---

## Если хотите выполнять по шагам вручную (PowerShell):

### 2a. Сборка и загрузка Docker-образа
```powershell
# Получаем Registry ID
$REGISTRY_ID = (terraform -chdir=terraform output -raw registry_id)

# Сборка и Пуш
yc container registry configure-docker
docker build -t "cr.yandex/$REGISTRY_ID/fastapi-app:latest" .
docker push "cr.yandex/$REGISTRY_ID/fastapi-app:latest"
```

### 3a. Развертывание через Helm

Если вы не используете `deploy.ps1`, вам нужно вручную создать секреты в Kubernetes, чтобы приложение могло подключиться к базе данных.

```powershell
# 1. Получаем необходимые данные из Terraform
$CLUSTER_ID = (terraform -chdir=terraform output -raw cluster_id)
$REGISTRY_ID = (terraform -chdir=terraform output -raw registry_id)
$EXTERNAL_IP = (terraform -chdir=terraform output -raw external_ip)
$LOCKBOX_ID = (terraform -chdir=terraform output -raw lockbox_secret_id)
$DOMAIN_NAME = (terraform -chdir=terraform output -raw domain_name)
$DB_HOST = (terraform -chdir=terraform output -raw db_host)
$DB_NAME = (terraform -chdir=terraform output -raw db_name)
$DB_USER = (terraform -chdir=terraform output -raw db_user)

# 2. Настройка kubectl
yc managed-kubernetes cluster get-credentials --id $CLUSTER_ID --external --force

# 3. Создание секретов (извлекаем из Lockbox)
$payload = yc lockbox payload get --id $LOCKBOX_ID --format json | ConvertFrom-Json
$DB_PASS = ($payload.entries | Where-Object { $_.key -eq "db_password" }).text_value
$APP_KEY = ($payload.entries | Where-Object { $_.key -eq "fastapi_key" }).text_value

# Важно: имя секрета должно соответствовать шаблону Helm: <release-name>-<chart-name>-<secret-suffix>
kubectl create secret generic fastapi-release-fastapi-chart-db-secret --from-literal=password="$DB_PASS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic fastapi-release-fastapi-chart-app-secrets --from-literal=fastapi-key="$APP_KEY" --dry-run=client -o yaml | kubectl apply -f -

# 4. Деплой через Helm
helm upgrade --install fastapi-release ./helm/fastapi-chart `
    --set image.repository="cr.yandex/$REGISTRY_ID/fastapi-app" `
    --set externalIp="$EXTERNAL_IP" `
    --set postgresql.server="$DB_HOST" `
    --set postgresql.database="$DB_NAME" `
    --set postgresql.user="$DB_USER" `
    --set domainName="$DOMAIN_NAME" `
    --wait
```
### 4a. Дождитесь создания LoadBalancer и получите внешний IP:
   ```bash
   kubectl get svc fastapi-release-fastapi-chart
   ```

## 3. Проверка
Откройте в браузере:
- По домену: `https://ваша_доменная_зона/` (HTTPS настраивается автоматически через cert-manager)

Чтобы проверить статус выпуска SSL-сертификата:
```powershell
kubectl get certificate
```

## 4. Настройка домена (Важно)
Чтобы ваш домен заработал:
1. Зайдите в панель управления вашего регистратора домена.
2. Установите NS-серверы Yandex Cloud для вашего домена:
   - `ns1.yandexcloud.net`
   - `ns2.yandexcloud.net`
3. Подождите обновления DNS (обычно от 1 до 24 часов).

## 5. Полная очистка ресурсов (Cleanup)

Если вы хотите удалить все созданные ресурсы в облаке и начать развертывание с "чистого листа", используйте скрипт `cleanup.ps1`.

**Что делает скрипт:**
1. Выполняет `terraform destroy` для удаления ресурсов, управляемых Terraform.
2. Принудительно удаляет через `yc CLI` любые оставшиеся ресурсы в папке (кластеры K8s, БД, реестры и образы Container Registry, секреты Lockbox, сети и т.д.).
3. Сохраняет сервисный аккаунт `tf-bootstrap`, если он был создан.

**Запуск:**
```powershell
.\cleanup.ps1
```
*Скрипт запросит подтверждение. Введите `DESTROY` для начала удаления.*

---

## 6. Автоматические SSL-сертификаты
Для автоматизации SSL-сертификатов (Let's Encrypt) используются следующие компоненты:
1. **Ingress NGINX**: Принимает внешний трафик и терминирует SSL.
2. **cert-manager**: Автоматически заказывает и обновляет сертификаты в Let's Encrypt.
3. **ClusterIssuer**: Конфигурация для cert-manager (шаблон `helm/fastapi-chart/templates/cert-manager-issuer.yaml`).

Скрипт `deploy.ps1` автоматически устанавливает эти компоненты и настраивает ваш статический IP для Ingress-контроллера.

## 7. Сетевой балансировщик (Network Load Balancer)
В проекте используется **автоматический** сетевой балансировщик Yandex Cloud, управляемый через Kubernetes:
- Kubernetes-сервис `ingress-nginx-controller` (тип `LoadBalancer`) автоматически создает NLB в облаке.
- К балансировщику привязывается ваш зарезервированный статический IP.
- Kubernetes сам следит за тем, чтобы в балансировщике всегда были актуальные IP-адреса работающих узлов кластера.
- В `terraform/main.tf` для этого настроены права `load-balancer.admin` и `compute.viewer` для сервисного аккаунта кластера.

*Примечание: Ручное создание балансировщика через Terraform для Managed K8s не рекомендуется, так как оно не учитывает динамическое изменение состава узлов кластера.*

---

## Дополнение: Как получить учетные данные для Terraform

Вариант A — Service Account (рекомендуется):

1. Создайте начальный сервисный аккаунт вручную (только для первого запуска):
   ```bash
   yc iam service-account create --name tf-bootstrap-sa --folder-id <FOLDER_ID>
   ```
2. Назначьте ему роль `admin` для возможности создания других ресурсов:
   ```bash
   yc resource-manager folder add-access-binding \
     --id <FOLDER_ID> \
     --role admin \
     --subject serviceAccount:<TF_BOOTSTRAP_SA_ID>
   ```
3. Выпустите ключ:
   ```bash
   yc iam key create --service-account-id <TF_BOOTSTRAP_SA_ID> --output sa-key.json
   ```
4. После первого `terraform apply` в облаке будет создан постоянный сервисный аккаунт `tf-admin-sa`, которым можно будет заменить временный.

Вариант B — OAuth токен пользователя:

1. Сгенерируйте токен:
   ```bash
   yc iam create-token
   ```
2. Добавьте его в `terraform.tfvars` как `token = "<скопированный_токен>"` или экспортируйте в переменную окружения `YC_TOKEN` перед запуском `terraform`.
