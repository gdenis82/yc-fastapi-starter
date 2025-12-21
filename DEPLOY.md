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
    Убедитесь, что там раскомментирована строка:
    ```hcl
    service_account_key_file = "sa-key.json"
    ```

4.  **Инициализация и запуск:**
    ```powershell
    cd terraform
    terraform init
    terraform plan
    terraform apply -auto-approve
    cd ..
    ```
    *После успешного выполнения `terraform apply` в консоли появятся `cluster_id` и `registry_id`. Они будут автоматически использованы на следующем этапе. Теперь создается Regional-кластер (High Availability) с мастерами в трех зонах (`ru-central1-a`, `ru-central1-b`, `ru-central1-d`).*

## 2. Сборка и деплой (Автоматизировано)

Для автоматизации подстановки `<REGISTRY_ID>` и `<CLUSTER_ID>` используйте скрипт `deploy.ps1`.

1. Убедитесь, что `terraform apply` выполнен успешно.
2. Запустите скрипт из корня проекта:
   ```powershell
   .\deploy.ps1
   ```

Скрипт сам:
- Получит ID ресурсов из Terraform.
- Соберит и запушит Docker-образ.
- Подставит нужный ID в манифест Kubernetes.
- Применит изменения в кластер.

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

### 3a. Развертывание в Kubernetes
```powershell
# Получаем ID
$CLUSTER_ID = (terraform -chdir=terraform output -raw cluster_id)
$REGISTRY_ID = (terraform -chdir=terraform output -raw registry_id)

# Настройка kubectl
yc managed-kubernetes cluster get-credentials --id $CLUSTER_ID --external

# Деплой с подстановкой (временный файл)
(Get-Content k8s/deployment.yaml).Replace('<REGISTRY_ID>', $REGISTRY_ID) | Set-Content k8s/deployment_patched.yaml
kubectl apply -f k8s/deployment_patched.yaml
Remove-Item k8s/deployment_patched.yaml
```
### 4a. Дождитесь создания LoadBalancer и получите внешний IP:
   ```bash
   kubectl get svc fastapi-service
   ```

## 3. Проверка
Откройте в браузере:
- По домену: `https://tryout.site/` (HTTPS настраивается автоматически через cert-manager)

Чтобы проверить статус выпуска SSL-сертификата:
```powershell
kubectl get certificate tryout-site-tls
kubectl describe certificate tryout-site-tls
```

## 4. Настройка домена (Важно)
Чтобы ваш домен `tryout.site` заработал:
1. Зайдите в панель управления вашего регистратора домена.
2. Установите NS-серверы Yandex Cloud для вашего домена:
   - `ns1.yandexcloud.net`
   - `ns2.yandexcloud.net`
3. Подождите обновления DNS (обычно от 1 до 24 часов).

## 6. Автоматические SSL-сертификаты
Для автоматизации SSL-сертификатов (Let's Encrypt) используются следующие компоненты:
1. **Ingress NGINX**: Принимает внешний трафик и терминирует SSL.
2. **cert-manager**: Автоматически заказывает и обновляет сертификаты в Let's Encrypt.
3. **ClusterIssuer**: Конфигурация для cert-manager (файл `k8s/cert-manager-issuer.yaml`).

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
