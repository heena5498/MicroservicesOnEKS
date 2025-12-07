#!/bin/bash

# Push Docker Images to ECR
# Usage: ./scripts/push-to-ecr.sh [service-name] [tag]
# Example: ./scripts/push-to-ecr.sh booking-service latest
#          ./scripts/push-to-ecr.sh all v1.0.0

set -e

# Get AWS account ID dynamically
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
AWS_REGION="${AWS_REGION:-us-east-1}"

# Configuration - use environment variable or derive from AWS account
if [ -n "$ECR_REGISTRY" ]; then
  ECR_REGISTRY="$ECR_REGISTRY"
elif [ -n "$AWS_ACCOUNT_ID" ]; then
  ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/bookmyevent"
else
  echo -e "${RED}Error: AWS CLI not configured and ECR_REGISTRY not set${NC}"
  echo "Please configure AWS CLI or set ECR_REGISTRY environment variable"
  exit 1
fi

TAG="${2:-latest}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Services
SERVICES=(
    "user-service"
    "event-service"
    "booking-service"
    "search-service"
    "frontend"
    "init-container"
)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}BookMyEvent - Push to ECR${NC}"
echo -e "${GREEN}========================================${NC}"

# Login to ECR
echo -e "\n${YELLOW}Logging in to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to login to ECR${NC}"
    exit 1
fi

# Function to push a single service
push_service() {
    local service=$1
    local tag=$2
    
    echo -e "\n${YELLOW}Pushing $service:$tag...${NC}"
    
    docker push "$ECR_REGISTRY/$service:$tag"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully pushed $service:$tag${NC}"
        
        # Also push latest tag if different
        if [ "$tag" != "latest" ]; then
            docker push "$ECR_REGISTRY/$service:latest"
            echo -e "${GREEN}✓ Successfully pushed $service:latest${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to push $service${NC}"
        return 1
    fi
}

# Main push logic
if [ "$1" == "all" ] || [ -z "$1" ]; then
    echo -e "${YELLOW}Pushing all services with tag: $TAG${NC}\n"
    
    for service in "${SERVICES[@]}"; do
        push_service "$service" "$TAG" || exit 1
    done
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}All images pushed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
elif [[ " ${SERVICES[@]} " =~ " $1 " ]]; then
    push_service "$1" "$TAG"
    
else
    echo -e "${RED}Error: Unknown service '$1'${NC}"
    echo -e "\nAvailable services:"
    for service in "${SERVICES[@]}"; do
        echo -e "  - $service"
    done
    echo -e "\nUsage: $0 [all|service-name] [tag]"
    exit 1
fi
