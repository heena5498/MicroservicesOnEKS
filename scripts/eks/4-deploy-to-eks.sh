#!/bin/bash
# =============================================================================
# Script: 4-deploy-to-eks.sh
# Description: Deploys BookMyEvent application to EKS
# =============================================================================

set -e

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
export IMAGE_TAG="${IMAGE_TAG:-latest}"

# Change to project root
cd "$(dirname "$0")/../.."

echo "======================================"
echo "Deploying BookMyEvent to EKS"
echo "Registry: $ECR_REGISTRY"
echo "======================================"

# Function to substitute environment variables in YAML files
substitute_vars() {
    local file=$1
    sed -e "s|\${AWS_ACCOUNT_ID}|$AWS_ACCOUNT_ID|g" \
        -e "s|\${AWS_REGION}|$AWS_REGION|g" \
        -e "s|\${IMAGE_TAG}|$IMAGE_TAG|g" \
        "$file"
}

# Step 1: Create namespace and base resources
echo ""
echo "Step 1: Creating namespace and base configs..."
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secrets.yaml

# Step 2: Deploy infrastructure (PostgreSQL, Redis, Elasticsearch)
echo ""
echo "Step 2: Deploying infrastructure..."
kubectl apply -f k8s/infrastructure/

# Wait for infrastructure to be ready
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n bookmyevent

echo "Waiting for Redis to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/redis -n bookmyevent

echo "Waiting for Elasticsearch to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch -n bookmyevent

# Step 3: Deploy microservices (substitute ECR registry)
echo ""
echo "Step 3: Deploying microservices..."
for SERVICE in user-service event-service search-service booking-service; do
    echo "Deploying $SERVICE..."
    substitute_vars "k8s/services/$SERVICE/$SERVICE.yaml" | kubectl apply -f -
done

# Wait for services to be ready
echo "Waiting for microservices to be ready..."
for SERVICE in user-service event-service search-service booking-service; do
    kubectl wait --for=condition=available --timeout=300s deployment/$SERVICE -n bookmyevent
done

# Step 4: Deploy nginx gateway
echo ""
echo "Step 4: Deploying nginx gateway..."
kubectl apply -f k8s/services/nginx-gateway/nginx-gateway.yaml

kubectl wait --for=condition=available --timeout=300s deployment/nginx-gateway -n bookmyevent

# Step 5: Deploy frontend
echo ""
echo "Step 5: Deploying frontend..."
substitute_vars "k8s/services/frontend/frontend.yaml" | kubectl apply -f -

kubectl wait --for=condition=available --timeout=300s deployment/frontend -n bookmyevent

# Step 6: Run database migrations (via init container)
echo ""
echo "Step 6: Running database initialization..."
substitute_vars "k8s/services/init-container/init-container.yaml" | kubectl apply -f -

# Wait for init job to complete
echo "Waiting for initialization to complete..."
kubectl wait --for=condition=complete --timeout=300s job/bookmyevent-init -n bookmyevent || true

echo ""
echo "======================================"
echo "Deployment Complete!"
echo "======================================"

# Get LoadBalancer URLs
echo ""
echo "Getting external URLs..."
echo ""

# API Gateway URL
API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$API_URL" ]; then
    echo "📡 API Gateway: http://$API_URL"
else
    echo "⏳ API Gateway: LoadBalancer is still provisioning..."
    echo "   Run: kubectl get svc nginx-gateway -n bookmyevent"
fi

# Frontend URL
FRONTEND_URL=$(kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$FRONTEND_URL" ]; then
    echo "🌐 Frontend: http://$FRONTEND_URL"
else
    echo "⏳ Frontend: LoadBalancer is still provisioning..."
    echo "   Run: kubectl get svc frontend -n bookmyevent"
fi

echo ""
echo "======================================"
echo "Useful Commands:"
echo "======================================"
echo "kubectl get pods -n bookmyevent                    # View all pods"
echo "kubectl get svc -n bookmyevent                     # View all services"
echo "kubectl logs -f deployment/user-service -n bookmyevent  # View logs"
echo "kubectl describe pod <pod-name> -n bookmyevent    # Debug pod issues"




