#!/bin/bash
# =============================================================================
# Script: 2-build-push-images.sh
# Description: Builds Docker images and pushes them to ECR
# =============================================================================

set -e

# Configuration - UPDATE THESE
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
export IMAGE_TAG="${IMAGE_TAG:-latest}"

# Change to project root
cd "$(dirname "$0")/../.."

echo "======================================"
echo "Building and Pushing Docker Images"
echo "Registry: $ECR_REGISTRY"
echo "Tag: $IMAGE_TAG"
echo "======================================"

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Create .env file if it doesn't exist (required for Dockerfiles)
if [ ! -f .env ]; then
    echo "Creating empty .env file for build..."
    touch .env
fi

# Build and push each service
SERVICES=(
    "user-service:Dockerfile-user-service"
    "event-service:Dockerfile-event-service"
    "search-service:Dockerfile-search-service"
    "booking-service:Dockerfile-booking-service"
    "init-container:Dockerfile-init-container"
    "frontend:Dockerfile-frontend"
)

for SERVICE_DOCKERFILE in "${SERVICES[@]}"; do
    SERVICE="${SERVICE_DOCKERFILE%%:*}"
    DOCKERFILE="${SERVICE_DOCKERFILE##*:}"
    
    echo ""
    echo "Building $SERVICE..."
    
    # Build with API URL for frontend
    if [ "$SERVICE" == "frontend" ]; then
        docker build \
            --build-arg VITE_API_URL="http://localhost" \
            -t "$ECR_REGISTRY/bookmyevent/$SERVICE:$IMAGE_TAG" \
            -f "$DOCKERFILE" .
    else
        docker build \
            -t "$ECR_REGISTRY/bookmyevent/$SERVICE:$IMAGE_TAG" \
            -f "$DOCKERFILE" .
    fi
    
    echo "Pushing $SERVICE..."
    docker push "$ECR_REGISTRY/bookmyevent/$SERVICE:$IMAGE_TAG"
    
    echo "✅ $SERVICE pushed successfully"
done

echo ""
echo "======================================"
echo "All Images Pushed Successfully!"
echo "======================================"
echo ""
echo "Images available at:"
for SERVICE_DOCKERFILE in "${SERVICES[@]}"; do
    SERVICE="${SERVICE_DOCKERFILE%%:*}"
    echo "  - $ECR_REGISTRY/bookmyevent/$SERVICE:$IMAGE_TAG"
done
echo ""
echo "Next step: Run ./3-create-eks-cluster.sh"



