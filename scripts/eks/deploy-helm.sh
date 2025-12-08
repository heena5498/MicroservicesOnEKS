#!/bin/bash
set -e

# =============================================================================
# Helm Deployment Script for BookMyEvent on EKS
# =============================================================================
# This script ensures correct ECR registry and image tags are used
# Usage: ./scripts/eks/deploy-helm.sh [IMAGE_TAG]
#
# Examples:
#   ./scripts/eks/deploy-helm.sh latest          # Deploy with :latest tag
#   ./scripts/eks/deploy-helm.sh f9a5763         # Deploy with specific commit tag
#   ./scripts/eks/deploy-helm.sh                 # Auto-detect from git commit
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${K8S_NAMESPACE:-bookmyevent}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-bookmyevent-cluster}"

# Get AWS Account ID dynamically
echo -e "${YELLOW}[1/6] Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}ERROR: Could not determine AWS Account ID${NC}"
    echo "Make sure AWS CLI is configured with valid credentials"
    exit 1
fi
echo -e "${GREEN}  Account ID: $ACCOUNT_ID${NC}"

# Build ECR Registry URL
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/bookmyevent"
echo -e "${GREEN}  ECR Registry: $ECR_REGISTRY${NC}"

# Determine image tag
if [ -n "$1" ]; then
    IMAGE_TAG="$1"
    echo -e "${YELLOW}[2/6] Using provided image tag: $IMAGE_TAG${NC}"
else
    # Auto-detect from git commit
    if git rev-parse --git-dir > /dev/null 2>&1; then
        IMAGE_TAG=$(git rev-parse --short=7 HEAD)
        echo -e "${YELLOW}[2/6] Auto-detected image tag from git: $IMAGE_TAG${NC}"
    else
        IMAGE_TAG="latest"
        echo -e "${YELLOW}[2/6] Using default image tag: $IMAGE_TAG${NC}"
    fi
fi

# Verify ECR images exist
echo -e "${YELLOW}[3/6] Verifying images exist in ECR...${NC}"
SERVICES=("user-service" "event-service" "search-service" "booking-service" "frontend" "init-container")
MISSING_IMAGES=()

for service in "${SERVICES[@]}"; do
    if ! aws ecr describe-images \
        --repository-name "bookmyevent/${service}" \
        --image-ids imageTag="${IMAGE_TAG}" \
        --region "$AWS_REGION" \
        --output text > /dev/null 2>&1; then
        MISSING_IMAGES+=("$service")
        echo -e "${RED}  ✗ $service:$IMAGE_TAG not found${NC}"
    else
        echo -e "${GREEN}  ✓ $service:$IMAGE_TAG${NC}"
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing images for: ${MISSING_IMAGES[*]}${NC}"
    echo "Available tags for first service:"
    aws ecr list-images --repository-name "bookmyevent/${SERVICES[0]}" --region "$AWS_REGION" \
        --query 'imageIds[*].imageTag' --output table 2>/dev/null || true
    exit 1
fi

# Check if namespace exists
echo -e "${YELLOW}[4/6] Checking namespace...${NC}"
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo "  Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
fi

# Add Helm annotations
kubectl label namespace "$NAMESPACE" app.kubernetes.io/managed-by=Helm --overwrite > /dev/null 2>&1
kubectl annotate namespace "$NAMESPACE" meta.helm.sh/release-name=bookmyevent --overwrite > /dev/null 2>&1
kubectl annotate namespace "$NAMESPACE" meta.helm.sh/release-namespace="$NAMESPACE" --overwrite > /dev/null 2>&1

# Check for required secrets
echo -e "${YELLOW}[5/6] Checking secrets...${NC}"
if ! kubectl get secret bookmyevent-secrets -n "$NAMESPACE" > /dev/null 2>&1; then
    echo -e "${RED}  WARNING: bookmyevent-secrets not found${NC}"
    echo "  You may need to create it manually with RDS credentials"
fi

# Deploy with Helm
echo -e "${YELLOW}[6/6] Deploying with Helm...${NC}"
echo "  Registry: $ECR_REGISTRY"
echo "  Image Tag: $IMAGE_TAG"
echo "  Namespace: $NAMESPACE"

helm upgrade --install bookmyevent ./helm \
    --namespace "$NAMESPACE" \
    --set global.imageRegistry="$ECR_REGISTRY" \
    --set imageTags.userService="$IMAGE_TAG" \
    --set imageTags.eventService="$IMAGE_TAG" \
    --set imageTags.searchService="$IMAGE_TAG" \
    --set imageTags.bookingService="$IMAGE_TAG" \
    --set imageTags.frontend="$IMAGE_TAG" \
    --set imageTags.initContainer="$IMAGE_TAG" \
    --set database.postgres.enabled=false \
    --set secrets.create=false \
    --timeout 15m \
    --wait

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Check pod status:"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "Get LoadBalancer URL:"
echo "  kubectl get svc nginx-gateway -n $NAMESPACE"
echo ""
echo "View logs:"
echo "  kubectl logs -f deployment/user-service -n $NAMESPACE"
echo ""
