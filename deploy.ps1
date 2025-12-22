# Automatic deployment script for Yandex Cloud (PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "--- Step 1: Getting data from Terraform ---" -ForegroundColor Cyan
if (-not (Test-Path "terraform")) {
    Write-Error "Terraform directory not found!"
}

Push-Location terraform
try {
    Write-Host "Checking Terraform outputs..."
    $outputs = terraform output -json | ConvertFrom-Json
    
    $REGISTRY_ID = $outputs.registry_id.value
    $CLUSTER_ID = $outputs.cluster_id.value
    $EXTERNAL_IP = $outputs.external_ip.value
    $DOMAIN_NAME = $outputs.domain_name.value
    $DB_HOST = $outputs.db_host.value
    $DB_NAME = $outputs.db_name.value
    $DB_USER = $outputs.db_user.value
    $LOCKBOX_ID = $outputs.lockbox_secret_id.value

    if ($null -eq $REGISTRY_ID -or $null -eq $CLUSTER_ID -or $null -eq $EXTERNAL_IP -or $null -eq $DB_HOST -or $null -eq $LOCKBOX_ID) {
        Write-Host "Some required Terraform outputs are missing." -ForegroundColor Yellow
        Write-Host "Do you want to run 'terraform apply' to update the infrastructure and state? (y/n)" -ForegroundColor Yellow
        $choice = Read-Host
        if ($choice -eq 'y') {
            # Ensure we have secrets in environment variables for Terraform
            if (-not $env:TF_VAR_db_password) {
                $env:TF_VAR_db_password = [guid]::NewGuid().ToString()
                Write-Host "Set DB_PASSWORD in environment" -ForegroundColor Gray
            }
            if (-not $env:TF_VAR_fastapi_key) {
                $env:TF_VAR_fastapi_key = [guid]::NewGuid().ToString()
                Write-Host "Set FASTAPI_KEY in environment" -ForegroundColor Gray
            }
            
            if ($LOCKBOX_ID) {
                Write-Host "Lockbox secret ID found ($LOCKBOX_ID). Using existing secrets container, but providing values for new version if needed." -ForegroundColor Gray
            }
            
            terraform apply -auto-approve
            
            # Re-fetch outputs after apply
            $outputs = terraform output -json | ConvertFrom-Json
            $REGISTRY_ID = $outputs.registry_id.value
            $CLUSTER_ID = $outputs.cluster_id.value
            $EXTERNAL_IP = $outputs.external_ip.value
            $DOMAIN_NAME = $outputs.domain_name.value
            $DB_HOST = $outputs.db_host.value
            $DB_NAME = $outputs.db_name.value
            $DB_USER = $outputs.db_user.value
            $LOCKBOX_ID = $outputs.lockbox_secret_id.value
        } else {
            throw "Infrastructure is incomplete. Please run 'terraform apply' manually."
        }
    }

    if (-not $REGISTRY_ID -or -not $CLUSTER_ID -or -not $EXTERNAL_IP -or -not $DB_HOST -or -not $LOCKBOX_ID) {
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
    metadata = @{
        annotations = @{
            "service.beta.kubernetes.io/yandex-cloud-load-balancer-external-ip" = $EXTERNAL_IP
            "yandex.cloud/load-balancer-type" = "external"
        }
    }
    spec = @{
        externalTrafficPolicy = "Local"
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
# Use positional argument for secret ID to avoid the --id conflict if it arises, and ensure it's quoted
$payload = yc lockbox payload get $LOCKBOX_ID --format json | ConvertFrom-Json
$DB_PASSWORD_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "db_password" }).text_value
$FASTAPI_KEY_FROM_LOCKBOX = ($payload.entries | Where-Object { $_.key -eq "fastapi_key" }).text_value

if (-not $DB_PASSWORD_FROM_LOCKBOX) { throw "Failed to fetch DB_PASSWORD from Lockbox" }
if (-not $FASTAPI_KEY_FROM_LOCKBOX) { throw "Failed to fetch FASTAPI_KEY from Lockbox" }

# Create/Update secrets via kubectl to avoid passing them as helm arguments
# We use --dry-run=client -o yaml | kubectl apply to be idempotent and silent about values
$CHART_NAME = "fastapi-chart"
$FULL_RELEASE_NAME = "fastapi-release-$CHART_NAME"

kubectl create secret generic "$FULL_RELEASE_NAME-db-secret" `
    --from-literal=password="$DB_PASSWORD_FROM_LOCKBOX" `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "$FULL_RELEASE_NAME-app-secrets" `
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
    --set domainName="$DOMAIN_NAME" `
    --set logging.level="INFO" `
    --set ingress.className="nginx" `
    --timeout 10m `
    --wait `
    --wait-for-jobs

# Ingress NGINX and its IP are now handled during setup step
# No need to patch again here unless we want to be sure
# kubectl patch svc ingress-nginx-controller -n ingress-nginx -p $patch

Write-Host "`n--- Diagnostics ---" -ForegroundColor Cyan
Write-Host "Waiting for Ingress to get IP..."
$ingress_ip = ""
for ($i = 0; $i -lt 12; $i++) {
    $ingress_ip = kubectl get ingress fastapi-release-fastapi-chart -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
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
if ($DOMAIN_NAME) {
    $certName = ($DOMAIN_NAME.Replace('.', '-')) + "-tls"
    Write-Host "kubectl get certificate $certName"
    kubectl get certificate $certName -o wide 2>$null
    Write-Host "Domain will be available at: https://$DOMAIN_NAME"
} else {
    Write-Host "Domain not set. Check Ingress status for IP address."
}
