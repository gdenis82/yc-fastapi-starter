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

Write-Host "`n--- Step 2: Cleaning up Kubernetes resources ---" -ForegroundColor Cyan
try {
    # Check if we have a cluster to clean up
    $clusters = yc managed-kubernetes cluster list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
    foreach ($c in $clusters) {
        if ($c.status -eq "RUNNING") {
            Write-Host "Getting credentials for cluster $($c.name) ($($c.id))..."
            yc managed-kubernetes cluster get-credentials --id $($c.id) --external --force 2>$null
            
            Write-Host "Uninstalling Helm releases..."
            $releases = helm list -A --output json | ConvertFrom-Json
            foreach ($rel in $releases) {
                Write-Host "  Uninstalling release $($rel.name) in namespace $($rel.namespace)..."
                helm uninstall $($rel.name) --namespace $($rel.namespace) --wait 2>$null
            }

            Write-Host "Deleting remaining namespaces (except default ones)..."
            $namespaces = kubectl get ns -o jsonpath='{.items[*].metadata.name}'
            foreach ($ns in $namespaces.Split(' ')) {
                if ($ns -notin @("default", "kube-system", "kube-public", "kube-node-lease")) {
                    Write-Host "  Deleting namespace $ns..."
                    kubectl delete ns $ns --timeout=30s 2>$null
                }
            }
        }
    }
} catch {
    Write-Warning "Failed to cleanup some K8s resources: $_"
}

Write-Host "`n--- Step 3: Attempting Terraform Destroy ---" -ForegroundColor Cyan
Push-Location terraform
try {
    if (Test-Path "terraform.tfstate") {
        terraform destroy -auto-approve
    } else {
        Write-Host "No terraform.tfstate found, skipping terraform destroy." -ForegroundColor Yellow
    }
} catch {
    Write-Warning "Terraform destroy failed or partially failed. Proceeding with manual cleanup."
}
Pop-Location

Write-Host "`n--- Step 4: Forced cleanup via YC CLI ---" -ForegroundColor Cyan

Write-Host "Deleting Kubernetes Clusters..."
$clusters = yc managed-kubernetes cluster list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $clusters) {
    foreach ($c in $clusters) {
        if ($null -ne $c.id) {
            Write-Host "Deleting cluster $($c.id)..."
            yc managed-kubernetes cluster delete $($c.id)
        }
    }
}

Write-Host "Deleting Container Registries and Images..."
$registries = yc container registry list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $registries) {
    foreach ($r in $registries) {
        Write-Host "Cleaning up registry $($r.name) ($($r.id))..."
        # List repositories
        $repos = yc container repository list --registry-id $($r.id) --format json | ConvertFrom-Json
        if ($null -ne $repos) {
            foreach ($repo in $repos) {
                Write-Host "  Processing repository $($repo.name)..."
                # List and delete all images in the repository
                $images = yc container image list --registry-id $($r.id) --repository-name $($repo.name) --format json | ConvertFrom-Json
                if ($null -ne $images -and $images.Count -gt 0) {
                    $imageIds = $images | ForEach-Object { $_.id }
                    Write-Host "    Deleting $($images.Count) images..."
                    yc container image delete $imageIds
                }
            }
        }
        Write-Host "  Deleting registry itself..."
        yc container registry delete $($r.id)
    }
}

Write-Host "Deleting Lockbox Secrets..."
$secrets = yc lockbox secret list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $secrets) {
    foreach ($s in $secrets) {
        if ($null -ne $s.id) {
            Write-Host "Deleting secret $($s.id)..."
            yc lockbox secret delete $($s.id)
        }
    }
}

Write-Host "Deleting DNS Zones..."
$zones = yc dns zone list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $zones) {
    foreach ($z in $zones) {
        if ($null -ne $z.id) {
            Write-Host "Deleting DNS zone $($z.id)..."
            yc dns zone delete $($z.id)
        }
    }
}

Write-Host "Deleting Cloud Logging Groups..."
$logGroups = yc logging group list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $logGroups) {
    foreach ($lg in $logGroups) {
        if ($null -ne $lg.id) {
            # Note: "default" group might have special handling, but we try to delete all found in the folder
            Write-Host "Deleting log group $($lg.name) ($($lg.id))..."
            yc logging group delete $($lg.id)
        }
    }
}

Write-Host "Deleting Static IPs..."
$ips = yc vpc address list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $ips) {
    foreach ($ip in $ips) {
        if ($null -ne $ip.id) {
            Write-Host "Deleting IP $($ip.id)..."
            yc vpc address delete $($ip.id)
        }
    }
}

Write-Host "Deleting Subnets..."
$subnets = yc vpc subnet list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $subnets) {
    foreach ($sn in $subnets) {
        if ($null -ne $sn.id) {
            Write-Host "Deleting subnet $($sn.id)..."
            yc vpc subnet delete $($sn.id)
        }
    }
}

Write-Host "Deleting Networks..."
$networks = yc vpc network list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $networks) {
    foreach ($nw in $networks) {
        if ($null -ne $nw.id) {
            Write-Host "Cleaning up security groups for network $($nw.id)..."
            $sgs = yc vpc security-group list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
            if ($null -ne $sgs) {
                foreach ($sg in $sgs) {
                    if ($sg.network_id -eq $nw.id -and $null -ne $sg.id) {
                        Write-Host "  Deleting security group $($sg.id)..."
                        yc vpc security-group delete $($sg.id)
                    }
                }
            }
            Write-Host "Deleting network $($nw.id)..."
            yc vpc network delete $($nw.id)
        }
    }
}

Write-Host "Deleting Service Accounts..."
$sas = yc iam service-account list --folder-id $FOLDER_ID --format json | ConvertFrom-Json
if ($null -ne $sas) {
    foreach ($sa in $sas) {
        if ($null -ne $sa.id -and $sa.name -ne "tf-bootstrap") { # Keep bootstrap SA if it was created manually
            Write-Host "Deleting SA $($sa.name) ($($sa.id))..."
            yc iam service-account delete $($sa.id)
        }
    }
}

Write-Host "`n--- Step 5: Finalizing ---" -ForegroundColor Cyan
if (Test-Path "terraform/terraform.tfstate") {
    $cleanState = Read-Host "Do you want to delete local terraform.tfstate? (y/n)"
    if ($cleanState -eq 'y') {
        Remove-Item "terraform/terraform.tfstate" -Force
        Remove-Item "terraform/terraform.tfstate.backup" -ErrorAction SilentlyContinue
        Write-Host "Local state files removed."
    }
}

Write-Host "`n--- Cleanup tasks submitted! ---" -ForegroundColor Green
Write-Host "Note: Some deletions are asynchronous. Please check 'yc operation list' or the Cloud Console for progress."
Write-Host "After all resources are gone, you can run '.\deploy.ps1' to start from scratch."
