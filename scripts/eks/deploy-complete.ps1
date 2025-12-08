# =============================================================================
# Script: deploy-complete.ps1
# Description: Complete one-command deployment to EKS (Windows PowerShell)
# Usage: .\scripts\eks\deploy-complete.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host @"
============================================================
  BookMyEvent - Complete EKS Deployment Script
  With Security Best Practices
============================================================
"@ -ForegroundColor Cyan

# Configuration
if (-not $env:AWS_REGION) { $env:AWS_REGION = "us-east-1" }
if (-not $env:CLUSTER_NAME) { $env:CLUSTER_NAME = "bookmyevent-cluster" }

# Get AWS Account ID
Write-Host "`n[1/9] Getting AWS Account ID..." -ForegroundColor Yellow
$env:AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
$ECR_REGISTRY = "$env:AWS_ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com"

Write-Host "  Account: $env:AWS_ACCOUNT_ID"
Write-Host "  Region: $env:AWS_REGION"
Write-Host "  Registry: $ECR_REGISTRY"

# Change to project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $ScriptDir "../..")

# Step 2: Create ECR Repositories
Write-Host "`n[2/9] Creating ECR Repositories..." -ForegroundColor Yellow
$services = @("bookmyevent/user-service", "bookmyevent/event-service", "bookmyevent/search-service", "bookmyevent/booking-service", "bookmyevent/init-container", "bookmyevent/frontend")
foreach ($service in $services) {
    aws ecr create-repository --repository-name $service --region $env:AWS_REGION --image-scanning-configuration scanOnPush=true 2>$null
    Write-Host "  Created: $service" -ForegroundColor Green
}

# Step 3: Login to ECR
Write-Host "`n[3/9] Logging into ECR..." -ForegroundColor Yellow
$loginPassword = aws ecr get-login-password --region $env:AWS_REGION
$loginPassword | docker login --username AWS --password-stdin $ECR_REGISTRY
Write-Host "  ECR login successful" -ForegroundColor Green

# Step 4: Build and Push Images (with security features)
Write-Host "`n[4/9] Building and Pushing Docker Images (with security features)..." -ForegroundColor Yellow
Write-Host "  Security: Non-root user, HEALTHCHECK, multi-stage builds" -ForegroundColor Cyan

# Create .env if needed
if (-not (Test-Path ".env")) { New-Item -ItemType File -Path ".env" -Force | Out-Null }

$dockerfiles = @{
    "user-service" = "Dockerfile-user-service"
    "event-service" = "Dockerfile-event-service"
    "search-service" = "Dockerfile-search-service"
    "booking-service" = "Dockerfile-booking-service"
    "init-container" = "Dockerfile-init-container"
}

foreach ($service in $dockerfiles.Keys) {
    Write-Host "  Building $service..." -ForegroundColor White
    docker build -t "$ECR_REGISTRY/bookmyevent/${service}:latest" -f $dockerfiles[$service] . | Out-Null
    docker push "$ECR_REGISTRY/bookmyevent/${service}:latest" | Out-Null
    Write-Host "  Pushed: $service" -ForegroundColor Green
}

# Step 5: Create EKS Cluster
Write-Host "`n[5/9] Creating EKS Cluster (this takes 15-20 minutes)..." -ForegroundColor Yellow
$clusterExists = eksctl get cluster --name $env:CLUSTER_NAME --region $env:AWS_REGION 2>$null
if ($clusterExists) {
    Write-Host "  Cluster already exists, updating kubeconfig..." -ForegroundColor Yellow
    aws eks update-kubeconfig --region $env:AWS_REGION --name $env:CLUSTER_NAME
} else {
    eksctl create cluster `
        --name $env:CLUSTER_NAME `
        --region $env:AWS_REGION `
        --nodegroup-name "bookmyevent-nodes" `
        --node-type t3.medium `
        --nodes 3 `
        --nodes-min 2 `
        --nodes-max 5 `
        --managed `
        --with-oidc `
        --logging "api,authenticator,audit,controllerManager,scheduler" `
        --full-ecr-access
}
Write-Host "  EKS Cluster ready" -ForegroundColor Green

# Step 5b: Install EBS CSI Driver
Write-Host "`n  Installing EBS CSI Driver..." -ForegroundColor Yellow
eksctl create iamserviceaccount `
    --name ebs-csi-controller-sa `
    --namespace kube-system `
    --cluster $env:CLUSTER_NAME `
    --region $env:AWS_REGION `
    --role-name AmazonEKS_EBS_CSI_DriverRole `
    --role-only `
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy `
    --approve 2>$null

$ROLE_ARN = "arn:aws:iam::${env:AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole"
eksctl create addon --name aws-ebs-csi-driver --cluster $env:CLUSTER_NAME --region $env:AWS_REGION --service-account-role-arn $ROLE_ARN --force 2>$null
Write-Host "  EBS CSI Driver installed" -ForegroundColor Green

# Step 6: Deploy Kubernetes Resources
Write-Host "`n[6/9] Deploying Kubernetes Resources..." -ForegroundColor Yellow

# Namespace and configs
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secrets.yaml
kubectl apply -f k8s/03-env-file-configmap.yaml

# Network Policy for security
Write-Host "  Applying Network Policy..." -ForegroundColor White
kubectl apply -f k8s/network-policy.yaml

# Infrastructure
Write-Host "  Deploying infrastructure..." -ForegroundColor White
kubectl apply -f k8s/infrastructure/

Write-Host "  Waiting for infrastructure to be ready..." -ForegroundColor White
Start-Sleep -Seconds 60
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n bookmyevent
kubectl wait --for=condition=available --timeout=300s deployment/redis -n bookmyevent
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch -n bookmyevent

# Run migrations
Write-Host "  Running database migrations..." -ForegroundColor White
kubectl apply -f k8s/jobs/db-migrations.yaml
Start-Sleep -Seconds 30
kubectl wait --for=condition=complete --timeout=120s job/db-migrations -n bookmyevent

# Deploy services with correct image names (not template variables)
Write-Host "  Deploying microservices..." -ForegroundColor White
$serviceFiles = @("user-service", "event-service", "search-service", "booking-service")
foreach ($service in $serviceFiles) {
    $content = Get-Content "k8s/services/$service.yaml" -Raw
    $content = $content -replace '\$\{AWS_ACCOUNT_ID\}', $env:AWS_ACCOUNT_ID
    $content = $content -replace '\$\{AWS_REGION\}', $env:AWS_REGION
    $content | kubectl apply -f -
}

# Update volume mounts to /app/.env for non-root containers
Write-Host "  Patching volume mounts for non-root containers..." -ForegroundColor White
foreach ($service in $serviceFiles) {
    kubectl patch deployment $service -n bookmyevent --type=json -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/volumeMounts/0/mountPath", "value": "/app/.env"}]' 2>$null
}

# Set correct image names
Write-Host "  Setting correct image names..." -ForegroundColor White
foreach ($service in $serviceFiles) {
    kubectl set image deployment/$service $service="$ECR_REGISTRY/bookmyevent/${service}:latest" -n bookmyevent
}

Start-Sleep -Seconds 30
foreach ($service in $serviceFiles) {
    kubectl wait --for=condition=available --timeout=300s deployment/$service -n bookmyevent
}

# Deploy nginx gateway and ALB Ingress
Write-Host "  Deploying API gateway with ALB Ingress..." -ForegroundColor White
kubectl apply -f k8s/services/nginx-gateway/nginx-gateway.yaml
kubectl wait --for=condition=available --timeout=300s deployment/nginx-gateway -n bookmyevent

# Wait for ALB to be provisioned
Write-Host "  Waiting for ALB to be provisioned (this may take 2-3 minutes)..." -ForegroundColor White
Start-Sleep -Seconds 60
$retryCount = 0
$maxRetries = 10
do {
    $API_URL = kubectl get ingress bookmyevent-ingress -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    if (-not $API_URL) {
        Write-Host "  Waiting for ALB DNS..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
        $retryCount++
    }
} while (-not $API_URL -and $retryCount -lt $maxRetries)

if (-not $API_URL) {
    Write-Host "  Warning: Could not get ALB URL. Check ingress status manually." -ForegroundColor Red
    $API_URL = "pending"
}
Write-Host "  API Gateway URL (ALB): http://$API_URL" -ForegroundColor Cyan

# Step 7: Build and deploy frontend with correct API URL
Write-Host "`n[7/9] Building Frontend with API URL..." -ForegroundColor Yellow
docker build --build-arg VITE_API_URL="http://$API_URL" -t "$ECR_REGISTRY/bookmyevent/frontend:latest" -f Dockerfile-frontend . | Out-Null
docker push "$ECR_REGISTRY/bookmyevent/frontend:latest" | Out-Null

$frontendContent = Get-Content "k8s/services/frontend.yaml" -Raw
$frontendContent = $frontendContent -replace '\$\{AWS_ACCOUNT_ID\}', $env:AWS_ACCOUNT_ID
$frontendContent = $frontendContent -replace '\$\{AWS_REGION\}', $env:AWS_REGION
$frontendContent | kubectl apply -f -

# Set frontend image
kubectl set image deployment/frontend frontend="$ECR_REGISTRY/bookmyevent/frontend:latest" -n bookmyevent
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n bookmyevent
Write-Host "  Frontend deployed" -ForegroundColor Green

# Step 8: Seed data
Write-Host "`n[8/9] Seeding test data..." -ForegroundColor Yellow
$initContent = Get-Content "k8s/services/init-container.yaml" -Raw
$initContent = $initContent -replace '\$\{AWS_ACCOUNT_ID\}', $env:AWS_ACCOUNT_ID
$initContent = $initContent -replace '\$\{AWS_REGION\}', $env:AWS_REGION
$initContent | kubectl apply -f -
Start-Sleep -Seconds 30
Write-Host "  Test data seeded" -ForegroundColor Green

# Step 9: Verify deployment
Write-Host "`n[9/9] Verifying deployment..." -ForegroundColor Yellow
kubectl get pods -n bookmyevent
kubectl get ingress -n bookmyevent

# Get ALB URL (single load balancer for all traffic)
$ALB_URL = kubectl get ingress bookmyevent-ingress -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

Write-Host @"

============================================================
  DEPLOYMENT COMPLETE!
============================================================

Your Application URL (ALB):
  Application: http://$ALB_URL

  The ALB routes all traffic through nginx-gateway:
    - Frontend: http://$ALB_URL/
    - API Gateway: http://$ALB_URL/api/

Test Credentials:
  User:  atlanuser1@mail.com / 11111111
  Admin: atlanadmin@mail.com / 11111111

Security Features Deployed:
  - Non-root containers (appuser)
  - HEALTHCHECK in all Dockerfiles
  - Multi-stage Docker builds
  - NetworkPolicy applied
  - Resource limits on all pods
  - Liveness/Readiness probes
  - AWS Application Load Balancer (ALB)

Next Steps (Optional):
  1. Setup RDS: .\scripts\eks\setup-rds.ps1
  2. Setup DNS/SSL: .\scripts\eks\setup-dns-ssl.ps1

Useful Commands:
  kubectl get pods -n bookmyevent
  kubectl get ingress -n bookmyevent
  kubectl logs deployment/user-service -n bookmyevent

To cleanup: .\scripts\eks\5-cleanup-all.ps1
============================================================
"@ -ForegroundColor Cyan
