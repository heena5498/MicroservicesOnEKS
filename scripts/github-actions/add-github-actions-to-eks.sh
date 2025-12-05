#!/bin/bash
# =============================================================================
# Script: add-github-actions-to-eks.sh
# Description: Adds GitHub Actions IAM user to EKS aws-auth ConfigMap
# Usage: ./scripts/k8s/add-github-actions-to-eks.sh
# =============================================================================

set -e

echo "============================================================"
echo "  Adding GitHub Actions User to EKS aws-auth ConfigMap"
echo "============================================================"

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"
export GITHUB_ACTIONS_USER="${GITHUB_ACTIONS_USER:-github-actions-bookmyevent}"

# Get AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo "Configuration:"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  Region: $AWS_REGION"
echo "  Cluster: $CLUSTER_NAME"
echo "  IAM User: $GITHUB_ACTIONS_USER"
echo ""

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# Backup current aws-auth
echo "Backing up current aws-auth ConfigMap..."
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth-backup.yaml
echo "  Backup saved to: aws-auth-backup.yaml"

# Check if user already exists in aws-auth
if kubectl get configmap aws-auth -n kube-system -o yaml | grep -q "$GITHUB_ACTIONS_USER"; then
    echo ""
    echo "⚠️  GitHub Actions user already exists in aws-auth ConfigMap"
    echo "    No changes needed."
    exit 0
fi

# Add GitHub Actions user to aws-auth
echo ""
echo "Adding GitHub Actions user to aws-auth ConfigMap..."

# Get current aws-auth
kubectl get configmap aws-auth -n kube-system -o yaml > /tmp/aws-auth.yaml

# Create patch with GitHub Actions user
cat > /tmp/aws-auth-patch.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapUsers: |
    - groups:
      - system:masters
      userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${GITHUB_ACTIONS_USER}
      username: ${GITHUB_ACTIONS_USER}
EOF

# Apply the update
kubectl patch configmap aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yaml)"

echo ""
echo "============================================================"
echo "  GitHub Actions User Added Successfully!"
echo "============================================================"
echo ""
echo "User ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${GITHUB_ACTIONS_USER}"
echo "Permissions: system:masters"
echo ""
echo "GitHub Actions can now:"
echo "  ✅ Access EKS cluster"
echo "  ✅ Deploy Kubernetes resources"
echo "  ✅ Run kubectl commands"
echo ""
echo "Backup of original aws-auth: aws-auth-backup.yaml"
echo ""
echo "To verify:"
echo "  kubectl get configmap aws-auth -n kube-system -o yaml"
echo ""
echo "============================================================"
