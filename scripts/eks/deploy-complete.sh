#!/bin/bash
# =============================================================================
# Script: deploy-complete.sh
# Description: Complete one-command deployment to EKS (Linux/Mac)
# Usage: ./scripts/eks/deploy-complete.sh
# =============================================================================

set -e

# Ensure Docker Buildx multi-arch builder exists and is in use
ensure_buildx() {
  # Check if buildx is available at all
  if ! docker buildx version >/dev/null 2>&1; then
    echo "[ERROR] docker buildx is not available. Please update Docker Desktop or enable Buildx."
    exit 1
  fi

  # If our 'multiarch' builder doesn't exist, create it
  if docker buildx ls | grep -q 'multiarch'; then
    echo "[INFO] Using existing Buildx builder 'multiarch'..."
    docker buildx use multiarch
  elif docker buildx ls | grep -q 'desktop-linux'; then
    echo "[INFO] Using default Docker Desktop Buildx builder 'desktop-linux'..."
    docker buildx use desktop-linux
  else
    echo "[INFO] Creating new Buildx builder 'multiarch'..."
    docker buildx create --name multiarch --use
  fi

docker buildx inspect --bootstrap
}

echo "============================================================"
echo "  BookMyEvent - Complete EKS Deployment Script"
echo "============================================================"

# Load environment variables from .env file if it exists (for local runs)
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    set -a
    source .env
    set +a
fi

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"
export RDS_INSTANCE="${RDS_INSTANCE:-bookmyevent-rds}"

# Check required secrets
if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: DB_PASSWORD is not set"
    echo "For local runs, create a .env file with:"
    echo "  DB_PASSWORD=your_password"
    echo "  JWT_SECRET=your_jwt_secret"
    echo "  INTERNAL_API_KEY=your_api_key"
    exit 1
fi

# Generate secrets if not set (for local convenience)
export JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 32)}"
export INTERNAL_API_KEY="${INTERNAL_API_KEY:-$(openssl rand -hex 32)}"

# Get AWS Account ID
echo ""
echo "[1/8] Getting AWS Account ID and RDS Endpoint..."
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Get RDS Endpoint
export RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE" --region "$AWS_REGION" --query 'DBInstances[0].Endpoint.Address' --output text)

echo "  Account: $AWS_ACCOUNT_ID"
echo "  Region: $AWS_REGION"
echo "  Registry: $ECR_REGISTRY"
echo "  RDS Endpoint: $RDS_ENDPOINT"

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

echo "[STEP] Ensuring Docker Buildx multi-arch builder is configured..."
ensure_buildx

# Create .env if needed
[ ! -f .env ] && touch .env

for SERVICE in user-service event-service search-service booking-service init-container; do
    echo "  Building $SERVICE (multi-arch: linux/amd64, linux/arm64)..."
    docker buildx build \
      --platform linux/amd64,linux/arm64 \
      -t "$ECR_REGISTRY/bookmyevent/$SERVICE:latest" \
      -f "Dockerfile-$SERVICE" \
      . \
      --push > /dev/null
    echo "  Pushed: $SERVICE"
done

# Step 5: Create EKS Cluster
echo ""
echo "[5/8] Creating EKS Cluster (this takes 15-20 minutes)..."
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "  Cluster already exists, updating kubeconfig..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
    
    # Check if nodegroup exists, create if missing
    echo "  Checking for nodegroups..."
    if eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$AWS_REGION" --name="bookmyevent-nodes" 2>/dev/null; then
        echo "  Nodegroup already exists"
    else
        echo "  No nodegroup found. Creating nodegroup (this takes 5-10 minutes)..."
        eksctl create nodegroup \
            --cluster="$CLUSTER_NAME" \
            --region="$AWS_REGION" \
            --name="bookmyevent-nodes" \
            --node-type=t3.medium \
            --nodes=3 \
            --nodes-min=3 \
            --nodes-max=6 \
            --managed
        echo "  ✓ Nodegroup created"
    fi
else
    echo "  Creating cluster with nodegroup..."
    eksctl create cluster \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --version 1.30 \
        --nodegroup-name "bookmyevent-nodes" \
        --node-type t3.medium \
        --nodes 3 \
        --nodes-min 3 \
        --nodes-max 6 \
        --managed \
        --with-oidc \
        --full-ecr-access
fi

# Install/Update AWS VPC CNI addon
echo "  Installing/Updating AWS VPC CNI addon..."
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.18.0/config/master/aws-k8s-cni.yaml
echo "  ✓ AWS VPC CNI addon installed/updated"

# Wait for CNI pods to be ready
echo "  Waiting for CNI pods to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=aws-node -n kube-system --timeout=120s || true

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
    sed -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${AWS_REGION}|$AWS_REGION|g" \
        -e "s|\${RDS_ENDPOINT}|$RDS_ENDPOINT|g" \
        -e "s|\${DB_PASSWORD}|$DB_PASSWORD|g" \
        -e "s|\${JWT_SECRET}|$JWT_SECRET|g" \
        -e "s|\${INTERNAL_API_KEY}|$INTERNAL_API_KEY|g" "$1"
}

kubectl apply -f k8s/00-namespace.yaml

echo "  Creating ConfigMap..."
kubectl apply -f k8s/01-configmap.yml

echo "  Creating Secrets with RDS credentials..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: bookmyevent-secrets
  namespace: bookmyevent
type: Opaque
stringData:
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "$DB_PASSWORD"
  USER_SERVICE_DB_URL: "postgresql://postgres:$DB_PASSWORD@$RDS_ENDPOINT:5432/users_db?sslmode=require"
  EVENT_SERVICE_DB_URL: "postgresql://postgres:$DB_PASSWORD@$RDS_ENDPOINT:5432/events_db?sslmode=require"
  BOOKING_SERVICE_DB_URL: "postgresql://postgres:$DB_PASSWORD@$RDS_ENDPOINT:5432/bookings_db?sslmode=require"
  JWT_SECRET: "$JWT_SECRET"
  INTERNAL_API_KEY: "$INTERNAL_API_KEY"
EOF

echo "  Deploying infrastructure (Redis & Elasticsearch only, using RDS for PostgreSQL)..."
kubectl apply -f k8s/infrastructure/redis.yaml
kubectl apply -f k8s/infrastructure/elasticsearch.yaml

echo "  Waiting for infrastructure..."
sleep 30
kubectl wait --for=condition=available --timeout=300s deployment/redis -n bookmyevent
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch -n bookmyevent

echo "  Running database migrations..."
kubectl apply -f k8s/jobs/db-migrations.yaml
sleep 30
kubectl wait --for=condition=complete --timeout=120s job/db-migrations -n bookmyevent

echo "  Deploying microservices..."
for SERVICE in user-service event-service search-service booking-service; do
    substitute_vars "k8s/services/$SERVICE/$SERVICE.yaml" | kubectl apply -f -
done

sleep 30
for SERVICE in user-service event-service search-service booking-service; do
    kubectl wait --for=condition=available --timeout=300s deployment/$SERVICE -n bookmyevent
done

echo "  Deploying API gateway..."
kubectl apply -f k8s/services/nginx-gateway/nginx-gateway.yaml
kubectl wait --for=condition=available --timeout=300s deployment/nginx-gateway -n bookmyevent

sleep 30
API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "  API Gateway URL: http://$API_URL"

# Step 7: Build and deploy frontend
echo ""
echo "[7/8] Building Frontend with API URL (multi-arch)..."
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg VITE_API_URL="http://$API_URL" \
  -t "$ECR_REGISTRY/bookmyevent/frontend:latest" \
  -f Dockerfile-frontend \
  . \
  --push > /dev/null

substitute_vars "k8s/services/frontend/frontend.yaml" | kubectl apply -f -
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n bookmyevent

# Step 8: Seed data
echo ""
echo "[8/8] Seeding test data..."
substitute_vars "k8s/services/init-container/init-container.yaml" | kubectl apply -f -
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
echo "To cleanup: ./scripts/eks/5-cleanup-all.sh"
echo "============================================================"




