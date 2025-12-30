# Automatic deployment script for Yandex Cloud (PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "--- Step 0: Stepwise Infrastructure Preparation ---" -ForegroundColor Cyan
if (Test-Path "prepare-infra.ps1") {
    .\prepare-infra.ps1
}

Write-Host "--- Step 1: Getting data from Terraform ---" -ForegroundColor Cyan
if (-not (Test-Path "terraform")) {
    Write-Error "Terraform directory not found!"
}

Push-Location terraform
try {
    Write-Host "Checking Terraform outputs..."
    $outputs = terraform output -json | ConvertFrom-Json
    
    $REGISTRY_ID = $outputs.registry_id.value
    $CLUSTER_ID = $outputs.k8s_cluster_id.value
    $EXTERNAL_IP = $outputs.external_ip.value
    $DOMAIN_NAME = $outputs.domain_name.value
    $LOCKBOX_ID = $outputs.lockbox_secret_id.value

    # Check if resources actually exist in YC (to prevent "Registry not found" errors)
    $registryExists = $false
    if ($REGISTRY_ID) {
        $check = yc container registry get --id $REGISTRY_ID 2>$null
        if ($LASTEXITCODE -eq 0) { $registryExists = $true }
    }

    if ($null -eq $REGISTRY_ID -or -not $registryExists -or $null -eq $CLUSTER_ID -or $null -eq $EXTERNAL_IP -or $null -eq $LOCKBOX_ID) {
        Write-Host "Some required resources are missing or missing from Terraform state." -ForegroundColor Yellow
        Write-Host "Do you want to run 'terraform apply' to (re)create the infrastructure? (y/n)" -ForegroundColor Yellow
        $choice = Read-Host
        if ($choice -eq 'y') {
            terraform apply -auto-approve
            
            # Re-fetch outputs after apply
            $outputs = terraform output -json | ConvertFrom-Json
            $REGISTRY_ID = $outputs.registry_id.value
            $CLUSTER_ID = $outputs.k8s_cluster_id.value
            $EXTERNAL_IP = $outputs.external_ip.value
            $DOMAIN_NAME = $outputs.domain_name.value
            $LOCKBOX_ID = $outputs.lockbox_secret_id.value
        } else {
            throw "Infrastructure is incomplete. Please run 'terraform apply' manually."
        }
    }

    if (-not $REGISTRY_ID -or -not $CLUSTER_ID -or -not $EXTERNAL_IP -or -not $LOCKBOX_ID) {
        throw "One or more required Terraform outputs are still missing after attempt to apply."
    }
} catch {
    Write-Error "Failed to get outputs from Terraform. Details: $_"
    throw "Deployment aborted due to missing infrastructure data."
} finally {
    Pop-Location
}

Write-Host "REGISTRY_ID: $REGISTRY_ID"
Write-Host "CLUSTER_ID: $CLUSTER_ID"
Write-Host "EXTERNAL_IP: $EXTERNAL_IP"

$DOMAIN_CLEAN = $DOMAIN_NAME.TrimEnd('.')
Write-Host "Domain (cleaned): $DOMAIN_CLEAN"

Write-Host "`n--- Step 2: Build and Push Docker Images ---" -ForegroundColor Cyan
yc container registry configure-docker
$TAG = Get-Date -Format "yyyyMMdd-HHmmss"

# Backend
$BACKEND_IMAGE_NAME = "cr.yandex/$REGISTRY_ID/fastapi-app:$TAG"
$BACKEND_LATEST_NAME = "cr.yandex/$REGISTRY_ID/fastapi-app:latest"

Write-Host "Building backend image $BACKEND_IMAGE_NAME..."
docker build -t $BACKEND_IMAGE_NAME -t $BACKEND_LATEST_NAME ./services/backend
if ($LASTEXITCODE -ne 0) { throw "Backend Docker build failed" }

Write-Host "Pushing backend images to Registry..."
docker push $BACKEND_IMAGE_NAME
if ($LASTEXITCODE -ne 0) { throw "Backend Docker push failed for $BACKEND_IMAGE_NAME" }
docker push $BACKEND_LATEST_NAME
if ($LASTEXITCODE -ne 0) { throw "Backend Docker push failed for $BACKEND_LATEST_NAME" }

# Frontend
$FRONTEND_IMAGE_NAME = "cr.yandex/$REGISTRY_ID/frontend-app:$TAG"
$FRONTEND_LATEST_NAME = "cr.yandex/$REGISTRY_ID/frontend-app:latest"

$BACKEND_URL = "https://$DOMAIN_CLEAN/api"
Write-Host "Building frontend image $FRONTEND_IMAGE_NAME with NEXT_PUBLIC_API_URL=$BACKEND_URL..."
docker build -t $FRONTEND_IMAGE_NAME -t $FRONTEND_LATEST_NAME --build-arg NEXT_PUBLIC_API_URL="$BACKEND_URL" ./services/frontend
if ($LASTEXITCODE -ne 0) { throw "Frontend Docker build failed" }

Write-Host "Pushing frontend images to Registry..."
docker push $FRONTEND_IMAGE_NAME
if ($LASTEXITCODE -ne 0) { throw "Frontend Docker push failed for $FRONTEND_IMAGE_NAME" }
docker push $FRONTEND_LATEST_NAME
if ($LASTEXITCODE -ne 0) { throw "Frontend Docker push failed for $FRONTEND_LATEST_NAME" }

Write-Host "`n--- Step 3: Kubernetes Setup and Deploy ---" -ForegroundColor Cyan
yc managed-kubernetes cluster get-credentials --id $CLUSTER_ID --external --force

Write-Host "Installing Ingress NGINX (via Helm)..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null
helm repo update ingress-nginx

# Ensure namespace exists before applying anything that might fail if it doesn't
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install ingress-nginx ingress-nginx `
  --repo https://kubernetes.github.io/ingress-nginx `
  --namespace ingress-nginx `
  --set controller.service.type=LoadBalancer `
  --set controller.service.loadBalancerIP="$EXTERNAL_IP" `
  --set controller.service.annotations."service\.beta\.kubernetes\.io/yandex-cloud-load-balancer-type"=external `
  --set controller.service.externalTrafficPolicy=Local `
  --wait

Write-Host "Installing cert-manager (if not installed)..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

Write-Host "Waiting for cert-manager readiness..."
Start-Sleep -Seconds 20

Write-Host "Applying ClusterIssuer..."
kubectl apply -f helm\cluster-issuer.yaml

$RELEASE_NAME = "fastapi"

# Determine Secret key and Database components from Lockbox
$payload = yc lockbox payload get $LOCKBOX_ID --format json | ConvertFrom-Json
$SECRET_KEY_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "secret_key" }).text_value

# Function to get entry from lockbox payload
function Get-LockboxEntry($key) {
    return ($payload.entries | Where-Object { $_.key -eq $key }).text_value
}

$DB_HOST = Get-LockboxEntry "db_host"
$DB_PORT = Get-LockboxEntry "db_port"
$DB_USER = Get-LockboxEntry "db_user"
$DB_PASSWORD = Get-LockboxEntry "db_password"
$DB_NAME = Get-LockboxEntry "db_name"
$DB_SSL_MODE = Get-LockboxEntry "db_ssl_mode"

if (-not $SECRET_KEY_FROM_LOCKBOX) { throw "Failed to fetch SECRET_KEY from Lockbox" }

if (-not $DB_HOST -or -not $DB_USER -or -not $DB_PASSWORD -or -not $DB_NAME) {
    Write-Host "`n[WARNING] Some individual database variables (db_host, db_user, etc.) are missing in Lockbox!" -ForegroundColor Yellow
    Write-Host "New configuration requires these separate variables to handle special characters in passwords." -ForegroundColor Yellow
    Write-Host "Would you like to run 'terraform apply' to update Lockbox with separate variables? (y/n)" -ForegroundColor Cyan
    $choice = Read-Host
    if ($choice -eq 'y') {
        Push-Location terraform
        terraform apply -auto-approve
        Pop-Location
        # Refresh payload
        $payload = yc lockbox payload get $LOCKBOX_ID --format json | ConvertFrom-Json
        $DB_HOST = Get-LockboxEntry "db_host"
        $DB_PORT = Get-LockboxEntry "db_port"
        $DB_USER = Get-LockboxEntry "db_user"
        $DB_PASSWORD = Get-LockboxEntry "db_password"
        $DB_NAME = Get-LockboxEntry "db_name"
        $DB_SSL_MODE = Get-LockboxEntry "db_ssl_mode"
    }
    
    if (-not $DB_HOST -or -not $DB_USER -or -not $DB_PASSWORD -or -not $DB_NAME) {
        throw "Missing database configuration in Lockbox. Please ensure db_host, db_port, db_user, db_password, db_name are present. Run 'terraform apply' to populate them."
    }
}

# Create/Update secrets via kubectl to avoid passing them as helm arguments
# We use --dry-run=client -o yaml | kubectl apply to be idempotent and silent about values
$RELEASE_NAME = "fastapi"

Write-Host "Creating/Updating application secrets..."
kubectl create secret generic "$RELEASE_NAME-app-secrets" `
    --from-literal=secret-key="$SECRET_KEY_FROM_LOCKBOX" `
    --from-literal=db-host="$DB_HOST" `
    --from-literal=db-port="$DB_PORT" `
    --from-literal=db-user="$DB_USER" `
    --from-literal=db-password="$DB_PASSWORD" `
    --from-literal=db-name="$DB_NAME" `
    --from-literal=db-ssl-mode="$DB_SSL_MODE" `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "--- Running Database Migrations ---" -ForegroundColor Cyan
$MIGRATE_REVISION = $TAG # Use timestamp for unique job name
$MIGRATE_JOB_FILE = "migrate-job-generated.yaml"

# Generate migration job from Helm template
helm template $RELEASE_NAME ./helm/fastapi-chart `
    --show-only templates/migrate-job.yaml `
    --set fullnameOverride=$RELEASE_NAME `
    --set image.repository="cr.yandex/$REGISTRY_ID/fastapi-app" `
    --set image.tag="$TAG" `
    --set migration.enabled="true" `
    --set migration.revision="$MIGRATE_REVISION" > $MIGRATE_JOB_FILE

Write-Host "Applying migration job..."
kubectl apply -f $MIGRATE_JOB_FILE

Write-Host "Waiting for migration job to complete..."
$waitTimeout = "300s" # Increased timeout to 5 minutes
kubectl wait --for=condition=complete "job/$RELEASE_NAME-migrate-$MIGRATE_REVISION" --timeout=$waitTimeout
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Migration job failed or timed out!" -ForegroundColor Red
    
    Write-Host "`n--- Job Status ---"
    kubectl get job "$RELEASE_NAME-migrate-$MIGRATE_REVISION"
    kubectl describe job "$RELEASE_NAME-migrate-$MIGRATE_REVISION"
    
    Write-Host "`n--- Pods associated with Job ---"
    $jobPods = kubectl get pods -l "job-name=$RELEASE_NAME-migrate-$MIGRATE_REVISION" -o jsonpath='{.items[*].metadata.name}'
    foreach ($podName in $jobPods.Split(' ')) {
        if ($podName) {
            Write-Host "`nLogs for pod: $podName" -ForegroundColor Yellow
            kubectl logs $podName
            Write-Host "--- End of logs for $podName ---"
        }
    }
    
    throw "Deployment aborted due to migration failure"
}

Write-Host "Deploying Backend with Helm..." -ForegroundColor Cyan
helm upgrade --install $RELEASE_NAME ./helm/fastapi-chart `
    --set fullnameOverride=$RELEASE_NAME `
    --set image.repository="cr.yandex/$REGISTRY_ID/fastapi-app" `
    --set image.tag="$TAG" `
    --set externalIp="$EXTERNAL_IP" `
    --set domainName="$DOMAIN_CLEAN" `
    --set logging.level="INFO" `
    --set ingress.className="nginx" `
    --timeout 5m `
    --wait `
    --wait-for-jobs

Write-Host "Deploying Frontend with Helm..." -ForegroundColor Cyan
$FRONTEND_RELEASE_NAME = "frontend"
helm upgrade --install $FRONTEND_RELEASE_NAME ./helm/frontend-chart `
    --set fullnameOverride=$FRONTEND_RELEASE_NAME `
    --set image.repository="cr.yandex/$REGISTRY_ID/frontend-app" `
    --set image.tag="$TAG" `
    --set externalIp="$EXTERNAL_IP" `
    --set domainName="$DOMAIN_CLEAN" `
    --set ingress.className="nginx" `
    --timeout 5m `
    --wait

# Ingress NGINX and its IP are now handled during setup step
# No need to patch again here unless we want to be sure
# kubectl patch svc ingress-nginx-controller -n ingress-nginx -p $patch

Write-Host "`n--- Diagnostics ---" -ForegroundColor Cyan
Write-Host "Waiting for Ingress to get IP..."
$ingress_ip = ""
for ($i = 0; $i -lt 12; $i++) {
    $ingress_ip = kubectl get ingress $RELEASE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($ingress_ip) {
        Write-Host "Unified Ingress IP: $ingress_ip" -ForegroundColor Green
        break
    }
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 10
}
Write-Host ""

if (-not $ingress_ip) {
    Write-Warning "Ingress still has no IP or not found."
}

Write-Host "`n--- Final Status ---" -ForegroundColor Green
Write-Host "Check certificate status:"
if ($DOMAIN_CLEAN) {
    $certName = ($DOMAIN_CLEAN.Replace('.', '-')) + "-tls"
    Write-Host "kubectl get certificate $certName"
    kubectl get certificate $certName -o wide 2>$null
    Write-Host "Domain will be available at: https://$DOMAIN_CLEAN"
} else {
    Write-Host "Domain not set. Check Ingress status for IP address."
}
