#!/bin/bash
# =============================================================================
# Script: setup-secrets-manager.sh
# Description: Creates secrets in AWS Secrets Manager for BookMyEvent
# Usage: ./scripts/secrets/setup-secrets-manager.sh
# =============================================================================

set -e

echo "============================================================"
echo "  Setting up AWS Secrets Manager for BookMyEvent"
echo "============================================================"

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo "Configuration:"
echo "  AWS Region: $AWS_REGION"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  Cluster: $CLUSTER_NAME"
echo ""

# Generate secure random passwords
echo "[1/5] Generating secure random passwords..."
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/")
INTERNAL_API_KEY=$(openssl rand -base64 64 | tr -d "=+/")

echo "  ✓ Generated secure passwords"

# Create database secret
echo ""
echo "[2/5] Creating database credentials secret..."
aws secretsmanager create-secret \
    --name bookmyevent/database \
    --description "BookMyEvent database credentials" \
    --secret-string "{
        \"username\": \"postgres\",
        \"password\": \"$POSTGRES_PASSWORD\",
        \"user_service_db_url\": \"postgresql://postgres:$POSTGRES_PASSWORD@postgres:5432/users_db?sslmode=disable\",
        \"event_service_db_url\": \"postgresql://postgres:$POSTGRES_PASSWORD@postgres:5432/events_db?sslmode=disable\",
        \"booking_service_db_url\": \"postgresql://postgres:$POSTGRES_PASSWORD@postgres:5432/bookings_db?sslmode=disable\"
    }" \
    --region "$AWS_REGION" 2>/dev/null || \
aws secretsmanager update-secret \
    --secret-id bookmyevent/database \
    --secret-string "{
        \"username\": \"postgres\",
        \"password\": \"$POSTGRES_PASSWORD\",
        \"user_service_db_url\": \"postgresql://postgres:$POSTGRES_PASSWORD@postgres:5432/users_db?sslmode=disable\",
        \"event_service_db_url\": \"postgresql://postgres:$POSTGRES_PASSWORD@postgres:5432/events_db?sslmode=disable\",
        \"booking_service_db_url\": \"postgresql://postgres:$POSTGRES_PASSWORD@postgres:5432/bookings_db?sslmode=disable\"
    }" \
    --region "$AWS_REGION"

echo "  ✓ Database credentials secret created/updated"

# Create application secret
echo ""
echo "[3/5] Creating application secrets..."
aws secretsmanager create-secret \
    --name bookmyevent/application \
    --description "BookMyEvent application secrets" \
    --secret-string "{
        \"jwt_secret\": \"$JWT_SECRET\",
        \"internal_api_key\": \"$INTERNAL_API_KEY\"
    }" \
    --region "$AWS_REGION" 2>/dev/null || \
aws secretsmanager update-secret \
    --secret-id bookmyevent/application \
    --secret-string "{
        \"jwt_secret\": \"$JWT_SECRET\",
        \"internal_api_key\": \"$INTERNAL_API_KEY\"
    }" \
    --region "$AWS_REGION"

echo "  ✓ Application secrets created/updated"

# Create IAM policy for External Secrets Operator
echo ""
echo "[4/5] Creating IAM policy for External Secrets Operator..."
POLICY_NAME="BookMyEventSecretsManagerPolicy"

# Check if policy exists
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text 2>/dev/null || echo "")

if [ -z "$POLICY_ARN" ]; then
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"secretsmanager:GetSecretValue\",
                        \"secretsmanager:DescribeSecret\"
                    ],
                    \"Resource\": [
                        \"arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:bookmyevent/*\"
                    ]
                }
            ]
        }" \
        --query 'Policy.Arn' \
        --output text)
    echo "  ✓ IAM policy created: $POLICY_ARN"
else
    echo "  ✓ IAM policy already exists: $POLICY_ARN"
fi

# Create IAM role with IRSA for External Secrets Operator
echo ""
echo "[5/5] Creating IRSA role for External Secrets Operator..."
eksctl create iamserviceaccount \
    --name external-secrets-sa \
    --namespace bookmyevent \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --role-name "BookMyEventExternalSecretsRole" \
    --attach-policy-arn "$POLICY_ARN" \
    --approve \
    --override-existing-serviceaccounts 2>/dev/null || echo "  ⚠ Service account already exists"

echo "  ✓ IRSA role created/updated"

echo ""
echo "============================================================"
echo "  AWS Secrets Manager Setup Complete!"
echo "============================================================"
echo ""
echo "Secrets created in AWS Secrets Manager:"
echo "  - bookmyevent/database (PostgreSQL credentials)"
echo "  - bookmyevent/application (JWT & API keys)"
echo ""
echo "IAM Resources:"
echo "  - Policy: $POLICY_ARN"
echo "  - Role: arn:aws:iam::$AWS_ACCOUNT_ID:role/BookMyEventExternalSecretsRole"
echo ""
echo "Next steps:"
echo "  1. Install External Secrets Operator CRDs:"
echo "     kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml"
echo ""
echo "  2. Deploy External Secrets resources:"
echo "     kubectl apply -f k8s/secrets-management/"
echo ""
echo "  3. Verify secrets are synced:"
echo "     kubectl get externalsecrets -n bookmyevent"
echo "     kubectl get secrets -n bookmyevent"
echo ""
echo "============================================================"
