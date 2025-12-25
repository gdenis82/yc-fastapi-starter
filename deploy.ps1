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

$RELEASE_NAME = "fastapi"

Write-Host "Waiting for cert-manager readiness..."
Start-Sleep -Seconds 30

Write-Host "Fixing ClusterIssuer ownership for Helm (if exists)..."
$issuerExists = kubectl get clusterissuer letsencrypt-prod -o name --ignore-not-found
if ($issuerExists) {
    Write-Host "ClusterIssuer letsencrypt-prod found. Adding Helm ownership labels and annotations..."
    kubectl label clusterissuer letsencrypt-prod app.kubernetes.io/managed-by=Helm --overwrite
    kubectl annotate clusterissuer letsencrypt-prod meta.helm.sh/release-name=$RELEASE_NAME --overwrite
    kubectl annotate clusterissuer letsencrypt-prod meta.helm.sh/release-namespace=default --overwrite
}

# Determine FastAPI key and Database URL from Lockbox
$payload = yc lockbox payload get $LOCKBOX_ID --format json | ConvertFrom-Json
$FASTAPI_KEY_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "fastapi_key" }).text_value
$DATABASE_URL_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "database_url" }).text_value

if (-not $FASTAPI_KEY_FROM_LOCKBOX) { throw "Failed to fetch FASTAPI_KEY from Lockbox" }
if (-not $DATABASE_URL_FROM_LOCKBOX) { throw "Failed to fetch DATABASE_URL from Lockbox" }

# Create/Update secrets via kubectl to avoid passing them as helm arguments
# We use --dry-run=client -o yaml | kubectl apply to be idempotent and silent about values
$RELEASE_NAME = "fastapi"

Write-Host "Creating/Updating application secrets..."
kubectl create secret generic "$RELEASE_NAME-app-secrets" `
    --from-literal=fastapi-key="$FASTAPI_KEY_FROM_LOCKBOX" `
    --from-literal=database-url="$DATABASE_URL_FROM_LOCKBOX" `
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
kubectl wait --for=condition=complete "job/$RELEASE_NAME-migrate-$MIGRATE_REVISION" --timeout=120s
if ($LASTEXITCODE -ne 0) {
    Write-Error "Migration job failed or timed out"
    kubectl logs "job/$RELEASE_NAME-migrate-$MIGRATE_REVISION"
    throw "Deployment aborted due to migration failure"
}

Write-Host "Deploying with Helm..." -ForegroundColor Cyan
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

# Ingress NGINX and its IP are now handled during setup step
# No need to patch again here unless we want to be sure
# kubectl patch svc ingress-nginx-controller -n ingress-nginx -p $patch

Write-Host "`n--- Diagnostics ---" -ForegroundColor Cyan
Write-Host "Waiting for Ingress to get IP..."
$ingress_ip = ""
for ($i = 0; $i -lt 12; $i++) {
    $ingress_ip = kubectl get ingress $RELEASE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($ingress_ip) {
        Write-Host "Ingress IP: $ingress_ip" -ForegroundColor Green
        break
    }
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 10
}
Write-Host ""

if (-not $ingress_ip) {
    Write-Warning "Ingress still has no IP or not found. Check 'kubectl get ingress' and 'kubectl describe svc -n ingress-nginx ingress-nginx-controller'"
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
