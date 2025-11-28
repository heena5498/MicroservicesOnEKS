#!/bin/bash
# =============================================================================
# Script: deploy-complete.sh
# Description: Complete one-command deployment to EKS (Linux/Mac)
# Usage: ./scripts/eks/deploy-complete.sh
# =============================================================================

set -e

echo "============================================================"
echo "  BookMyEvent - Complete EKS Deployment Script"
echo "============================================================"

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"

# Get AWS Account ID
echo ""
echo "[1/8] Getting AWS Account ID..."
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "  Account: $AWS_ACCOUNT_ID"
echo "  Region: $AWS_REGION"
echo "  Registry: $ECR_REGISTRY"

# Change to project root
cd "$(dirname "$0")/../.."

# Step 2: Create ECR Repositories
echo ""
echo "[2/8] Creating ECR Repositories..."
for SERVICE in user-service event-service search-service booking-service init-container frontend; do
    aws ecr create-repository --repository-name "bookmyevent/$SERVICE" --region "$AWS_REGION" --image-scanning-configuration scanOnPush=true 2>/dev/null || true
    echo "  Created: bookmyevent/$SERVICE"
done

# Step 3: Login to ECR
echo ""
echo "[3/8] Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Step 4: Build and Push Images
echo ""
echo "[4/8] Building and Pushing Docker Images..."

# Create .env if needed
[ ! -f .env ] && touch .env

for SERVICE in user-service event-service search-service booking-service init-container; do
    echo "  Building $SERVICE..."
    docker build -t "$ECR_REGISTRY/bookmyevent/$SERVICE:latest" -f "Dockerfile-$SERVICE" . > /dev/null
    docker push "$ECR_REGISTRY/bookmyevent/$SERVICE:latest" > /dev/null
    echo "  Pushed: $SERVICE"
done

# Step 5: Create EKS Cluster
echo ""
echo "[5/8] Creating EKS Cluster (this takes 15-20 minutes)..."
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "  Cluster already exists, updating kubeconfig..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
else
    eksctl create cluster \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --nodegroup-name "bookmyevent-nodes" \
        --node-type t3.medium \
        --nodes 2 \
        --nodes-min 1 \
        --nodes-max 4 \
        --managed \
        --with-oidc \
        --full-ecr-access
fi

# Install EBS CSI Driver
echo "  Installing EBS CSI Driver..."
eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve 2>/dev/null || true

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole"
eksctl create addon --name aws-ebs-csi-driver --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --service-account-role-arn "$ROLE_ARN" --force 2>/dev/null || true

# Step 6: Deploy Kubernetes Resources
echo ""
echo "[6/8] Deploying Kubernetes Resources..."

substitute_vars() {
    sed -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" -e "s|\${AWS_REGION}|$AWS_REGION|g" "$1"
}

kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secrets.yaml
kubectl apply -f k8s/03-env-file-configmap.yaml

echo "  Deploying infrastructure..."
kubectl apply -f k8s/infrastructure/

echo "  Waiting for infrastructure..."
sleep 60
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n bookmyevent
kubectl wait --for=condition=available --timeout=300s deployment/redis -n bookmyevent
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch -n bookmyevent

echo "  Running database migrations..."
kubectl apply -f k8s/jobs/db-migrations.yaml
sleep 30
kubectl wait --for=condition=complete --timeout=120s job/db-migrations -n bookmyevent

echo "  Deploying microservices..."
for SERVICE in user-service event-service search-service booking-service; do
    substitute_vars "k8s/services/$SERVICE.yaml" | kubectl apply -f -
done

sleep 30
for SERVICE in user-service event-service search-service booking-service; do
    kubectl wait --for=condition=available --timeout=300s deployment/$SERVICE -n bookmyevent
done

echo "  Deploying API gateway..."
kubectl apply -f k8s/services/nginx-gateway.yaml
kubectl wait --for=condition=available --timeout=300s deployment/nginx-gateway -n bookmyevent

sleep 30
API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "  API Gateway URL: http://$API_URL"

# Step 7: Build and deploy frontend
echo ""
echo "[7/8] Building Frontend with API URL..."
docker build --build-arg VITE_API_URL="http://$API_URL" -t "$ECR_REGISTRY/bookmyevent/frontend:latest" -f Dockerfile-frontend . > /dev/null
docker push "$ECR_REGISTRY/bookmyevent/frontend:latest" > /dev/null

substitute_vars "k8s/services/frontend.yaml" | kubectl apply -f -
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n bookmyevent

# Step 8: Seed data
echo ""
echo "[8/8] Seeding test data..."
substitute_vars "k8s/services/init-container.yaml" | kubectl apply -f -
sleep 30

FRONTEND_URL=$(kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo ""
echo "============================================================"
echo "  DEPLOYMENT COMPLETE!"
echo "============================================================"
echo ""
echo "Your Application URLs:"
echo "  Frontend:    http://$FRONTEND_URL"
echo "  API Gateway: http://$API_URL"
echo ""
echo "Test Credentials:"
echo "  User:  atlanuser1@mail.com / 11111111"
echo "  Admin: atlanadmin@mail.com / 11111111"
echo ""
echo "Useful Commands:"
echo "  kubectl get pods -n bookmyevent"
echo "  kubectl logs deployment/user-service -n bookmyevent"
echo ""
echo "To cleanup: ./scripts/eks/5-cleanup.sh"
echo "============================================================"



