# Automatic deployment script for Yandex Cloud (PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "--- Step 1: Getting data from Terraform ---" -ForegroundColor Cyan
if (-not (Test-Path "terraform")) {
    Write-Error "Terraform directory not found!"
}

Push-Location terraform
try {
    $REGISTRY_ID = (terraform output -raw registry_id)
    $CLUSTER_ID = (terraform output -raw cluster_id)
    $EXTERNAL_IP = (terraform output -raw external_ip)
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
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

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

Write-Host "Deploying with Helm..."
helm upgrade --install fastapi-release ./helm/fastapi-chart `
    --set image.repository="cr.yandex/$REGISTRY_ID/fastapi-app" `
    --set image.tag="$TAG" `
    --set externalIp="$EXTERNAL_IP" `
    --wait

Write-Host "`n--- Configuring static IP for Ingress ---" -ForegroundColor Cyan
Write-Host "Binding external IP $EXTERNAL_IP to Ingress controller LoadBalancer and configuring Yandex NLB..."
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

Write-Host "`n--- Done! ---" -ForegroundColor Green
Write-Host "Check certificate status:"
Write-Host "kubectl get certificate tryout-site-tls"
Write-Host "Domain will be available at: https://tryout.site"
