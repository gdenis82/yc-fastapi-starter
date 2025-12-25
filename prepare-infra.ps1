# Script for stepwise infrastructure preparation and waiting

function Wait-For-YC-Resource {
    param (
        [string]$Name,
        [scriptblock]$GetStatusScript,
        [string]$TargetStatus = "RUNNING",
        [int]$TimeoutSeconds = 1200,
        [int]$IntervalSeconds = 30
    )

    Write-Host "Waiting for ${Name} to reach status '${TargetStatus}'..." -ForegroundColor Cyan
    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $currentStatus = &$GetStatusScript
            Write-Host "Current status of ${Name}: ${currentStatus}"
            if ($currentStatus -eq $TargetStatus -or $currentStatus -eq "ALIVE" -or $currentStatus -eq "HEALTHY") {
                Write-Host "${Name} is ready!" -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "Error checking ${Name}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Write-Error "Timeout waiting for ${Name}"
    return $false
}

Write-Host "--- Stepwise Infrastructure Check ---" -ForegroundColor Cyan

# Ensure terraform outputs are available
Push-Location terraform
$outputs = terraform output -json | ConvertFrom-Json
Pop-Location

# 1. Check Registry
$registryId = $outputs.registry_id.value
if ($registryId) {
    Write-Host "Registry ID found: $registryId" -ForegroundColor Green
} else {
    Write-Host "Registry not found. Running terraform apply for Registry..."
    Push-Location terraform
    terraform apply "-target=yandex_container_registry.registry" -auto-approve
    $outputs = terraform output -json | ConvertFrom-Json
    $registryId = $outputs.registry_id.value
    Pop-Location
}

# 2. Check Kubernetes
$clusterId = $outputs.k8s_cluster_id.value
if ($clusterId) {
    Wait-For-YC-Resource -Name "Kubernetes Cluster" -GetStatusScript {
        (yc managed-kubernetes cluster get --id $clusterId --format json | ConvertFrom-Json).status
    } -TargetStatus "RUNNING"
} else {
    Write-Host "K8s Cluster not found in outputs. Running terraform apply for K8s..."
    Push-Location terraform
    terraform apply "-target=yandex_kubernetes_cluster.k8s-cluster" "-target=yandex_kubernetes_node_group.k8s-node-group" -auto-approve
    $outputs = terraform output -json | ConvertFrom-Json
    $clusterId = $outputs.k8s_cluster_id.value
    Pop-Location
    Wait-For-YC-Resource -Name "Kubernetes Cluster" -GetStatusScript {
        (yc managed-kubernetes cluster get --id $clusterId --format json | ConvertFrom-Json).status
    } -TargetStatus "RUNNING"
}

# 3. Check PostgreSQL
Write-Host "Checking PostgreSQL Cluster..." -ForegroundColor Cyan

# Force untaint BEFORE any checks to prevent Terraform from planning a destruction in Step 4
Push-Location terraform
try {
    # We use a try-catch and check $LASTEXITCODE because terraform state list returns 1 if resource is not found,
    # which PowerShell might treat as an error depending on environment settings.
    $hasPostgresInState = terraform state list yandex_mdb_postgresql_cluster.postgres 2>$null
    if ($LASTEXITCODE -eq 0 -and $hasPostgresInState) {
        $stateInfo = terraform state show yandex_mdb_postgresql_cluster.postgres 2>$null
        if ($LASTEXITCODE -eq 0 -and $stateInfo -match "tainted") {
            Write-Host "Resource yandex_mdb_postgresql_cluster.postgres is tainted. Untainting to prevent unnecessary destruction..." -ForegroundColor Yellow
            terraform untaint yandex_mdb_postgresql_cluster.postgres 2>$null
        }
    }
} catch {
    # Ignore errors here, it just means the resource is not in state yet
}
Pop-Location

$dbClusterList = yc managed-postgresql cluster list --format json | ConvertFrom-Json
$dbCluster = $null
if ($dbClusterList) {
    $dbCluster = $dbClusterList | Where-Object { $_.name -eq "fastapi-db" -and $_.status -ne "DELETING" } | Select-Object -First 1
}
$dbClusterId = $dbCluster.id

if (-not $dbClusterId) {
    Write-Host "PostgreSQL cluster not found in Yandex Cloud. Preparing to create..."
    Push-Location terraform
    Write-Host "Running terraform apply for DB Cluster..."
    terraform apply "-target=yandex_mdb_postgresql_cluster.postgres" -auto-approve
    $outputs = terraform output -json | ConvertFrom-Json
    $dbClusterId = $outputs.postgres_cluster_id.value
    Pop-Location
} else {
    Write-Host "PostgreSQL cluster found with ID: $dbClusterId" -ForegroundColor Green
}

Wait-For-YC-Resource -Name "PostgreSQL Cluster" -GetStatusScript {
    if (-not $dbClusterId) { 
        $script:dbClusterId = (yc managed-postgresql cluster list --format json | ConvertFrom-Json | Where-Object { $_.name -eq "fastapi-db" -and $_.status -ne "DELETING" } | Select-Object -First 1).id
        if (-not $script:dbClusterId) { return "MISSING" }
    }
    (yc managed-postgresql cluster get $script:dbClusterId --format json | ConvertFrom-Json).status
} -TargetStatus "RUNNING"

# 4. Final Terraform Apply to sync everything (Lockbox etc)
Write-Host "Running final terraform apply to sync all resources..." -ForegroundColor Cyan
Push-Location terraform
terraform apply -auto-approve
Pop-Location

Write-Host "Infrastructure is fully prepared and synced!" -ForegroundColor Green
