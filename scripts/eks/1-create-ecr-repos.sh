#!/bin/bash
# =============================================================================
# Script: 1-create-ecr-repos.sh
# Description: Creates ECR repositories for all BookMyEvent services
# =============================================================================

set -e

# Configuration - UPDATE THESE
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

echo "======================================"
echo "Creating ECR Repositories"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "======================================"

# List of services to create repos for
SERVICES=(
    "bookmyevent/user-service"
    "bookmyevent/event-service"
    "bookmyevent/search-service"
    "bookmyevent/booking-service"
    "bookmyevent/init-container"
    "bookmyevent/frontend"
)

for SERVICE in "${SERVICES[@]}"; do
    echo "Creating repository: $SERVICE"
    aws ecr create-repository \
        --repository-name "$SERVICE" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        2>/dev/null || echo "Repository $SERVICE already exists"
done

echo ""
echo "======================================"
echo "ECR Repositories Created Successfully!"
echo "======================================"
echo ""
echo "Next step: Run ./2-build-push-images.sh"




