# Automatic deployment script for Yandex Cloud (PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "--- Step 1: Getting data from Terraform ---" -ForegroundColor Cyan
if (-not (Test-Path "terraform")) {
    Write-Error "Terraform directory not found!"
}

Push-Location terraform
try {
    Write-Host "Checking Terraform state..."
    $state = terraform show -json | ConvertFrom-Json
    if ($null -eq $state.values) {
        Write-Host "Infrastructure not found. Do you want to run 'terraform apply'? (y/n)" -ForegroundColor Yellow
        $choice = Read-Host
        if ($choice -eq 'y') {
            # Ensure DB_PASSWORD and FASTAPI_KEY are available for Terraform
            if (-not $env:TF_VAR_db_password) {
                $env:TF_VAR_db_password = Read-Host "Enter DB_PASSWORD for PostgreSQL"
            }
            if (-not $env:TF_VAR_fastapi_key) {
                $env:TF_VAR_fastapi_key = Read-Host "Enter FASTAPI_KEY for application"
            }
            terraform apply -auto-approve
        } else {
            throw "Infrastructure must be provisioned before deployment."
        }
    }

    $REGISTRY_ID = (terraform output -raw registry_id)
    $CLUSTER_ID = (terraform output -raw cluster_id)
    $EXTERNAL_IP = (terraform output -raw external_ip)
    $DB_HOST = (terraform output -raw db_host)
    $DB_NAME = (terraform output -raw db_name)
    $DB_USER = (terraform output -raw db_user)
    $LOCKBOX_ID = (terraform output -raw lockbox_secret_id)
} catch {
    Write-Error "Failed to get outputs from Terraform. Ensure 'terraform apply' was successful."
} finally {
    Pop-Location
}

Write-Host "REGISTRY_ID: $REGISTRY_ID"
Write-Host "CLUSTER_ID: $CLUSTER_ID"
Write-Host "EXTERNAL_IP: $EXTERNAL_IP"

Write-Host "`n--- Step 2: Build and Push Docker Image ---" -ForegroundColor Cyan
yc container registry configure-docker
$TAG = Get-Date -Format "yyyyMMdd-HHmmss"
$IMAGE_NAME = "cr.yandex/$REGISTRY_ID/fastapi-app:$TAG"
$LATEST_NAME = "cr.yandex/$REGISTRY_ID/fastapi-app:latest"

Write-Host "Building image $IMAGE_NAME..."
docker build -t $IMAGE_NAME -t $LATEST_NAME .
if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

Write-Host "Pushing images to Registry..."
docker push $IMAGE_NAME
if ($LASTEXITCODE -ne 0) { throw "Docker push failed for $IMAGE_NAME" }
docker push $LATEST_NAME
if ($LASTEXITCODE -ne 0) { throw "Docker push failed for $LATEST_NAME" }

Write-Host "`n--- Step 3: Kubernetes Setup and Deploy ---" -ForegroundColor Cyan
yc managed-kubernetes cluster get-credentials --id $CLUSTER_ID --external --force

Write-Host "Installing Ingress NGINX (if not installed)..."
# Pass the static IP to the ingress-nginx service directly during installation if possible
# However, the standard manifest doesn't know our $EXTERNAL_IP.
# We will use a more reliable way: check if it's already patched or use a helm chart for ingress-nginx.
# But keeping the user's flow, we'll ensure the patch is done efficiently.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Wait for the service to be created so we can patch it before it gets a random IP if possible
Write-Host "Waiting for ingress-nginx-controller service..."
for ($i=0; $i -lt 10; $i++) {
    $svc = kubectl get svc ingress-nginx-controller -n ingress-nginx --ignore-not-found
    if ($svc) { break }
    Start-Sleep -Seconds 2
}

Write-Host "Patching ingress-nginx-controller with static IP $EXTERNAL_IP..."
$patch = @{
    spec = @{
        loadBalancerIP = $EXTERNAL_IP
        externalTrafficPolicy = "Local"
    }
    metadata = @{
        annotations = @{
            "yandex.cloud/load-balancer-type" = "external"
        }
    }
} | ConvertTo-Json -Depth 10 -Compress
$patch = $patch.Replace('"', '\"')
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p $patch

Write-Host "Installing cert-manager (if not installed)..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

Write-Host "Waiting for cert-manager readiness..."
Start-Sleep -Seconds 30

Write-Host "Fixing ClusterIssuer ownership for Helm (if exists)..."
$issuerExists = kubectl get clusterissuer letsencrypt-prod -o name 2>$null
if ($issuerExists) {
    Write-Host "ClusterIssuer letsencrypt-prod found. Adding Helm ownership labels and annotations..."
    kubectl label clusterissuer letsencrypt-prod app.kubernetes.io/managed-by=Helm --overwrite
    kubectl annotate clusterissuer letsencrypt-prod meta.helm.sh/release-name=fastapi-release --overwrite
    kubectl annotate clusterissuer letsencrypt-prod meta.helm.sh/release-namespace=default --overwrite
}

# Fetch secrets from Yandex Lockbox and create Kubernetes Secrets directly
Write-Host "Fetching secrets from Yandex Lockbox and updating Kubernetes Secrets..."
$payload = yc lockbox payload get --id $LOCKBOX_ID --format json | ConvertFrom-Json
$DB_PASSWORD_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "db_password" }).text_value
$FASTAPI_KEY_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "fastapi_key" }).text_value

if (-not $DB_PASSWORD_FROM_LOCKBOX) { throw "Failed to fetch DB_PASSWORD from Lockbox" }
if (-not $FASTAPI_KEY_FROM_LOCKBOX) { throw "Failed to fetch FASTAPI_KEY from Lockbox" }

# Create/Update secrets via kubectl to avoid passing them as helm arguments
# We use --dry-run=client -o yaml | kubectl apply to be idempotent and silent about values
kubectl create secret opaque fastapi-release-db-secret `
    --from-literal=password="$DB_PASSWORD_FROM_LOCKBOX" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret opaque fastapi-release-app-secrets `
    --from-literal=fastapi-key="$FASTAPI_KEY_FROM_LOCKBOX" `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Deploying with Helm..."
helm upgrade --install fastapi-release ./helm/fastapi-chart `
    --set image.repository="cr.yandex/$REGISTRY_ID/fastapi-app" `
    --set image.tag="$TAG" `
    --set externalIp="$EXTERNAL_IP" `
    --set postgresql.server="$DB_HOST" `
    --set postgresql.database="$DB_NAME" `
    --set postgresql.user="$DB_USER" `
    --wait

# Ingress NGINX and its IP are now handled during setup step
# No need to patch again here unless we want to be sure
# kubectl patch svc ingress-nginx-controller -n ingress-nginx -p $patch

Write-Host "`n--- Done! ---" -ForegroundColor Green
Write-Host "Check certificate status:"
Write-Host "kubectl get certificate tryout-site-tls"
Write-Host "Domain will be available at: https://tryout.site"
