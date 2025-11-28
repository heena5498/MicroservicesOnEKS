# =============================================================================
# Script: 5-cleanup.ps1
# Description: Cleans up all EKS resources (Windows)
# =============================================================================

$ErrorActionPreference = "Stop"

# Configuration
if (-not $env:AWS_REGION) { $env:AWS_REGION = "us-east-1" }
if (-not $env:CLUSTER_NAME) { $env:CLUSTER_NAME = "bookmyevent-cluster" }
if (-not $env:AWS_ACCOUNT_ID) { 
    $env:AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
}

Write-Host "======================================"
Write-Host "⚠️  WARNING: This will delete all resources!" -ForegroundColor Red
Write-Host "Cluster: $env:CLUSTER_NAME"
Write-Host "Region: $env:AWS_REGION"
Write-Host "======================================"
Write-Host ""

$confirm = Read-Host "Are you sure you want to continue? (yes/no)"

if ($confirm -ne "yes") {
    Write-Host "Cleanup cancelled."
    exit 0
}

# Step 1: Delete Kubernetes resources
Write-Host ""
Write-Host "Step 1: Deleting Kubernetes resources..."
try {
    kubectl delete namespace bookmyevent --ignore-not-found=true
} catch {
    Write-Host "Namespace may not exist" -ForegroundColor Yellow
}

# Step 2: Delete EKS cluster
Write-Host ""
Write-Host "Step 2: Deleting EKS cluster..."
try {
    eksctl delete cluster --name $env:CLUSTER_NAME --region $env:AWS_REGION --wait
} catch {
    Write-Host "Cluster may not exist or deletion failed" -ForegroundColor Yellow
}

# Step 3: Delete ECR repositories (optional)
Write-Host ""
$deleteEcr = Read-Host "Do you want to delete ECR repositories? (yes/no)"

if ($deleteEcr -eq "yes") {
    Write-Host "Deleting ECR repositories..."
    
    $REPOS = @(
        "bookmyevent/user-service",
        "bookmyevent/event-service",
        "bookmyevent/search-service",
        "bookmyevent/booking-service",
        "bookmyevent/init-container",
        "bookmyevent/frontend"
    )
    
    foreach ($REPO in $REPOS) {
        Write-Host "Deleting $REPO..."
        try {
            aws ecr delete-repository `
                --repository-name $REPO `
                --region $env:AWS_REGION `
                --force 2>$null
        } catch {
            Write-Host "  Repository $REPO may not exist" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "======================================"
Write-Host "Cleanup Complete!" -ForegroundColor Green
Write-Host "======================================"



