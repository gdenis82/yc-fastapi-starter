# Cleanup script to wipe Yandex Cloud resources in a folder
$ErrorActionPreference = "Continue" # Continue on errors to clean up as much as possible

Write-Host "--- Step 1: Loading configuration ---" -ForegroundColor Cyan
if (Test-Path "terraform/terraform.tfvars") {
    $vars = Get-Content "terraform/terraform.tfvars"
    $FOLDER_ID = ($vars | Select-String 'folder_id\s*=\s*"(.*)"').Matches.Groups[1].Value
}

if (-not $FOLDER_ID) {
    $FOLDER_ID = Read-Host "Enter Yandex Cloud Folder ID to cleanup"
}

if (-not $FOLDER_ID) {
    Write-Error "Folder ID is required for cleanup."
    exit
}

Write-Host "Target Folder ID: $FOLDER_ID" -ForegroundColor Yellow
$confirm = Read-Host "ARE YOU SURE YOU WANT TO DELETE ALL RESOURCES IN THIS FOLDER? (type 'DESTROY' to confirm)"
if ($confirm -ne "DESTROY") {
    Write-Host "Cleanup aborted."
    exit
}

Write-Host "`n--- Step 2: Attempting Terraform Destroy ---" -ForegroundColor Cyan
Push-Location terraform
terraform destroy -auto-approve
Pop-Location

Write-Host "`n--- Step 3: Forced cleanup via YC CLI ---" -ForegroundColor Cyan

Write-Host "Deleting Kubernetes Clusters..."
$clusters = yc managed-kubernetes cluster list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($c in $clusters) {
    Write-Host "Deleting cluster $($c.id)..."
    yc managed-kubernetes cluster delete $($c.id) --async
}

Write-Host "Deleting PostgreSQL Clusters..."
$pg_clusters = yc mdb postgresql cluster list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($pc in $pg_clusters) {
    Write-Host "Deleting PG cluster $($pc.id)..."
    yc mdb postgresql cluster delete $($pc.id) --async
}

Write-Host "Deleting Container Registries and Images..."
$registries = yc container registry list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($r in $registries) {
    Write-Host "Cleaning up registry $($r.name) ($($r.id))..."
    # List and delete all repositories in the registry
    $repos = yc container repository list --registry-id $($r.id) --format json | ConvertFrom-Json
    foreach ($repo in $repos) {
        Write-Host "  Deleting repository $($repo.name)..."
        yc container repository delete $($repo.id) --async
    }
    Write-Host "  Deleting registry itself..."
    yc container registry delete $($r.id) --async
}

Write-Host "Deleting Lockbox Secrets..."
$secrets = yc lockbox secret list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($s in $secrets) {
    Write-Host "Deleting secret $($s.id)..."
    yc lockbox secret delete $($s.id)
}

Write-Host "Deleting DNS Zones..."
$zones = yc dns zone list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($z in $zones) {
    Write-Host "Deleting DNS zone $($z.id)..."
    yc dns zone delete $($z.id)
}

Write-Host "Deleting Static IPs..."
$ips = yc vpc address list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($ip in $ips) {
    Write-Host "Deleting IP $($ip.id)..."
    yc vpc address delete $($ip.id)
}

Write-Host "Deleting Subnets..."
$subnets = yc vpc subnet list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($sn in $subnets) {
    Write-Host "Deleting subnet $($sn.id)..."
    yc vpc subnet delete $($sn.id)
}

Write-Host "Deleting Networks..."
$networks = yc vpc network list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($nw in $networks) {
    Write-Host "Cleaning up security groups for network $($nw.id)..."
    $sgs = yc vpc security-group list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
    foreach ($sg in $sgs) {
        if ($sg.network_id -eq $nw.id) {
            Write-Host "  Deleting security group $($sg.id)..."
            yc vpc security-group delete $($sg.id)
        }
    }
    Write-Host "Deleting network $($nw.id)..."
    yc vpc network delete $($nw.id)
}

Write-Host "Deleting Service Accounts..."
$sas = yc iam service-account list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
foreach ($sa in $sas) {
    if ($sa.name -ne "tf-bootstrap") { # Keep bootstrap SA if it was created manually
        Write-Host "Deleting SA $($sa.name) ($($sa.id))..."
        yc iam service-account delete $($sa.id)
    }
}

Write-Host "`n--- Cleanup tasks submitted! ---" -ForegroundColor Green
Write-Host "Note: Some deletions are asynchronous. Please check 'yc operation list' or the Cloud Console for progress."
Write-Host "After all resources are gone, you can run '.\deploy.ps1' to start from scratch."
