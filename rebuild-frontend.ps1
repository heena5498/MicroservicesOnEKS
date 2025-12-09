# Script to rebuild frontend with correct API URL
# This fixes the issue where frontend was built with http://localhost

param(
    [string]$Domain = "https://campuseventmanager.work.gd",
    [string]$ECRRegistry = "",
    [string]$AWSAccountId = "",
    [string]$AWSRegion = "us-east-1"
)

Write-Host "Rebuilding frontend with API URL: (empty for relative URLs)" -ForegroundColor Yellow

# If ECR registry not provided, try to get from environment or construct
if ([string]::IsNullOrEmpty($ECRRegistry)) {
    if ($env:AWS_ACCOUNT_ID) {
        $ECRRegistry = "$env:AWS_ACCOUNT_ID.dkr.ecr.$AWSRegion.amazonaws.com/bookmyevent"
    } else {
        Write-Host "Error: ECR registry not provided and AWS_ACCOUNT_ID not set" -ForegroundColor Red
        Write-Host "Usage: .\rebuild-frontend.ps1 -ECRRegistry <registry> -AWSAccountId <account-id>" -ForegroundColor Yellow
        exit 1
    }
}

# Build frontend with empty API URL (uses relative URLs)
Write-Host "Building frontend Docker image..." -ForegroundColor Cyan
# Use the Dockerfile in k8s/services/frontend/ or create a symlink Dockerfile-frontend
if (Test-Path "Dockerfile-frontend") {
    $dockerfile = "Dockerfile-frontend"
} elseif (Test-Path "k8s/services/frontend/Dockerfile") {
    $dockerfile = "k8s/services/frontend/Dockerfile"
} else {
    Write-Host "Error: Dockerfile not found!" -ForegroundColor Red
    exit 1
}
docker build --build-arg VITE_API_URL="" -t "$ECRRegistry/frontend:latest" -f $dockerfile .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

# Login to ECR
Write-Host "Logging into ECR..." -ForegroundColor Cyan
aws ecr get-login-password --region $AWSRegion | docker login --username AWS --password-stdin $ECRRegistry

if ($LASTEXITCODE -ne 0) {
    Write-Host "ECR login failed!" -ForegroundColor Red
    exit 1
}

# Push image
Write-Host "Pushing image to ECR..." -ForegroundColor Cyan
docker push "$ECRRegistry/frontend:latest"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Push failed!" -ForegroundColor Red
    exit 1
}

# Restart frontend deployment
Write-Host "Restarting frontend deployment..." -ForegroundColor Cyan
kubectl rollout restart deployment frontend -n bookmyevent

Write-Host "`nFrontend rebuild complete!" -ForegroundColor Green
Write-Host "Waiting for rollout to complete..." -ForegroundColor Yellow
kubectl rollout status deployment frontend -n bookmyevent --timeout=5m

Write-Host "`nFrontend should now use relative API URLs and work correctly!" -ForegroundColor Green

