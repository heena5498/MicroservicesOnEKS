#!/bin/bash

# Local Docker Build Script for BookMyEvent Microservices
# Usage: ./scripts/build-local.sh [service-name] [tag]
# Example: ./scripts/build-local.sh booking-service latest
#          ./scripts/build-local.sh all v1.0.0

set -e

# Get AWS account ID dynamically
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
AWS_REGION="${AWS_REGION:-us-east-1}"

# Configuration - use environment variable or derive from AWS account
if [ -n "$ECR_REGISTRY" ]; then
  # Use provided ECR_REGISTRY environment variable
  ECR_REGISTRY="$ECR_REGISTRY"
elif [ -n "$AWS_ACCOUNT_ID" ]; then
  # Derive from AWS account ID
  ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/bookmyevent"
else
  # Fallback to local tag only (no ECR)
  ECR_REGISTRY="bookmyevent"
  echo -e "${YELLOW}⚠️  AWS CLI not configured. Building with local tags only.${NC}"
  echo -e "${YELLOW}To push to ECR, configure AWS CLI or set ECR_REGISTRY environment variable.${NC}"
fi

DEFAULT_TAG="${1:-latest}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Services to build
SERVICES=(
    "user-service"
    "event-service"
    "booking-service"
    "search-service"
    "frontend"
    "init-container"
)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}BookMyEvent - Local Docker Build${NC}"
echo -e "${GREEN}========================================${NC}"

# Function to build a single service
build_service() {
    local service=$1
    local tag=$2
    
    echo -e "\n${YELLOW}Building $service:$tag...${NC}"
    
    if [ ! -f "k8s/services/$service/Dockerfile" ]; then
        echo -e "${RED}Error: Dockerfile not found for $service${NC}"
        return 1
    fi
    
    docker build \
        -f "k8s/services/$service/Dockerfile" \
        -t "$ECR_REGISTRY/$service:$tag" \
        -t "$ECR_REGISTRY/$service:latest" \
        .
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully built $service:$tag${NC}"
    else
        echo -e "${RED}✗ Failed to build $service${NC}"
        return 1
    fi
}

# Main build logic
if [ "$1" == "all" ] || [ -z "$1" ]; then
    TAG="${2:-latest}"
    echo -e "${YELLOW}Building all services with tag: $TAG${NC}\n"
    
    for service in "${SERVICES[@]}"; do
        build_service "$service" "$TAG" || exit 1
    done
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}All services built successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
elif [[ " ${SERVICES[@]} " =~ " $1 " ]]; then
    TAG="${2:-latest}"
    build_service "$1" "$TAG"
    
else
    echo -e "${RED}Error: Unknown service '$1'${NC}"
    echo -e "\nAvailable services:"
    for service in "${SERVICES[@]}"; do
        echo -e "  - $service"
    done
    echo -e "\nUsage: $0 [all|service-name] [tag]"
    exit 1
fi

echo -e "\n${YELLOW}To push images to ECR, run:${NC}"
echo -e "  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY"
echo -e "  docker push $ECR_REGISTRY/[service-name]:$TAG"
