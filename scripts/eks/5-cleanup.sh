#!/bin/bash
# =============================================================================
# Script: 5-cleanup.sh
# Description: Cleans up all EKS resources
# =============================================================================

set -e

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

echo "======================================"
echo "⚠️  WARNING: This will delete all resources!"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "======================================"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Step 1: Delete Kubernetes resources
echo ""
echo "Step 1: Deleting Kubernetes resources..."
kubectl delete namespace bookmyevent --ignore-not-found=true || true

# Step 2: Delete EKS cluster
echo ""
echo "Step 2: Deleting EKS cluster..."
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait || true

# Step 3: Delete ECR repositories (optional)
echo ""
read -p "Do you want to delete ECR repositories? (yes/no): " delete_ecr

if [ "$delete_ecr" == "yes" ]; then
    echo "Deleting ECR repositories..."
    REPOS=(
        "bookmyevent/user-service"
        "bookmyevent/event-service"
        "bookmyevent/search-service"
        "bookmyevent/booking-service"
        "bookmyevent/init-container"
        "bookmyevent/frontend"
    )
    
    for REPO in "${REPOS[@]}"; do
        echo "Deleting $REPO..."
        aws ecr delete-repository \
            --repository-name "$REPO" \
            --region "$AWS_REGION" \
            --force 2>/dev/null || true
    done
fi

echo ""
echo "======================================"
echo "Cleanup Complete!"
echo "======================================"




