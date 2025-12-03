#!/bin/bash
# =============================================================================
# Script: setup-github-actions.sh
# Description: Complete setup for GitHub Actions CI/CD pipeline
# Usage: ./scripts/github-actions/setup-github-actions.sh
# =============================================================================

set -e

echo "============================================================"
echo "  GitHub Actions CI/CD Setup"
echo "============================================================"

# Configuration
export IAM_USER_NAME="github-actions-bookmyevent"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "This script will:"
echo "  1. Create IAM user for GitHub Actions"
echo "  2. Generate access keys"
echo "  3. Attach required policies"
echo "  4. Add user to EKS aws-auth ConfigMap"
echo "  5. Display GitHub Secrets to configure"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Get AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo "============================================================"
echo "[1/5] Creating IAM User"
echo "============================================================"

# Check if user exists
if aws iam get-user --user-name "$IAM_USER_NAME" 2>/dev/null; then
    echo -e "${YELLOW} IAM user '$IAM_USER_NAME' already exists${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Delete existing access keys
        echo "Deleting existing access keys..."
        aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'AccessKeyMetadata[*].AccessKeyId' --output text | \
        xargs -I {} aws iam delete-access-key --user-name "$IAM_USER_NAME" --access-key-id {} 2>/dev/null || true
        
        # Detach policies
        echo "Detaching policies..."
        aws iam list-attached-user-policies --user-name "$IAM_USER_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text | \
        xargs -I {} aws iam detach-user-policy --user-name "$IAM_USER_NAME" --policy-arn {} 2>/dev/null || true
        
        # Delete inline policies
        aws iam list-user-policies --user-name "$IAM_USER_NAME" --query 'PolicyNames[*]' --output text | \
        xargs -I {} aws iam delete-user-policy --user-name "$IAM_USER_NAME" --policy-name {} 2>/dev/null || true
        
        # Delete user
        aws iam delete-user --user-name "$IAM_USER_NAME"
        echo "User deleted."
    else
        echo "Skipping user creation. Using existing user."
        USER_EXISTS=true
    fi
fi

if [ -z "$USER_EXISTS" ]; then
    # Create IAM user
    aws iam create-user --user-name "$IAM_USER_NAME"
    echo -e "${GREEN}✓ IAM user created${NC}"
fi

echo ""
echo "============================================================"
echo "[2/5] Creating Access Keys"
echo "============================================================"

# Create access keys
ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER_NAME")
ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')

echo -e "${GREEN}✓ Access keys created${NC}"

echo ""
echo "============================================================"
echo "[3/5] Attaching IAM Policies"
echo "============================================================"

# Attach ECR PowerUser policy
aws iam attach-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

echo -e "${GREEN}✓ ECR policy attached${NC}"

# Create and attach EKS access policy
cat > /tmp/github-actions-eks-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:AccessKubernetesApi"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-name EKSAccess \
    --policy-document file:///tmp/github-actions-eks-policy.json

echo -e "${GREEN}✓ EKS policy attached${NC}"

echo ""
echo "============================================================"
echo "[4/5] Updating EKS aws-auth ConfigMap"
echo "============================================================"

# Update kubeconfig
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

# Check if user already in aws-auth
if kubectl get configmap aws-auth -n kube-system -o yaml 2>/dev/null | grep -q "$IAM_USER_NAME"; then
    echo -e "${YELLOW}⚠️  User already exists in aws-auth ConfigMap${NC}"
else
    # Backup current aws-auth
    kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth-backup-$(date +%Y%m%d-%H%M%S).yaml
    
    # Add user to aws-auth
    kubectl get configmap aws-auth -n kube-system -o json | \
    jq --arg userarn "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${IAM_USER_NAME}" \
       --arg username "$IAM_USER_NAME" \
    '.data.mapUsers = ((.data.mapUsers // "") + 
      "- groups:\n  - system:masters\n  userarn: \($userarn)\n  username: \($username)\n")' | \
    kubectl apply -f -
    
    echo -e "${GREEN}✓ aws-auth ConfigMap updated${NC}"
fi

echo ""
echo "============================================================"
echo "[5/5] Setup Complete!"
echo "============================================================"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 GitHub Actions Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Now configure these GitHub Secrets:"
echo ""
echo "Go to: GitHub Repo → Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "Add these 3 secrets:"
echo ""
echo "┌─────────────────────────────┬─────────────────────────────────────────┐"
echo "│ Secret Name                 │ Secret Value                            │"
echo "├─────────────────────────────┼─────────────────────────────────────────┤"
printf "│ AWS_ACCESS_KEY_ID           │ %-39s │\n" "$ACCESS_KEY_ID"
printf "│ AWS_SECRET_ACCESS_KEY       │ %-39s │\n" "${SECRET_ACCESS_KEY:0:20}... (full value shown below)"
printf "│ AWS_ACCOUNT_ID              │ %-39s │\n" "$AWS_ACCOUNT_ID"
echo "└─────────────────────────────┴─────────────────────────────────────────┘"
echo ""
echo "⚠️  IMPORTANT: Save these credentials securely!"
echo ""
echo "AWS_ACCESS_KEY_ID:"
echo "$ACCESS_KEY_ID"
echo ""
echo "AWS_SECRET_ACCESS_KEY:"
echo "$SECRET_ACCESS_KEY"
echo ""
echo "AWS_ACCOUNT_ID:"
echo "$AWS_ACCOUNT_ID"
echo ""
echo "📝 These credentials have been saved to: github-actions-credentials.txt"
echo ""

# Save credentials to file
cat > github-actions-credentials.txt << EOF
GitHub Actions AWS Credentials
Generated on: $(date)

AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

Instructions:
1. Go to GitHub repository
2. Settings → Secrets and variables → Actions
3. Add the three secrets above
4. Delete this file after adding secrets to GitHub

IAM User: $IAM_USER_NAME
Region: $AWS_REGION
Cluster: $CLUSTER_NAME
EOF

chmod 600 github-actions-credentials.txt

echo "🔒 Credentials file permissions: 600 (read-write for owner only)"
echo ""
echo "Next steps:"
echo "  1. Add the secrets to GitHub (see above)"
echo "  2. Delete credentials file: rm github-actions-credentials.txt"
echo "  3. Push code to trigger CI/CD pipeline"
echo "  4. Monitor workflow: GitHub → Actions tab"
echo ""
echo "Documentation:"
echo "  - Complete guide: build/ci-cd-guide.md"
echo "  - Quick start: build/ci-cd-quickstart.md"
echo ""
echo "============================================================"
