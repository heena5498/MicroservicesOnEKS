#!/usr/bin/env bash
# =============================================================================
# BookMyEvent - Configure Existing RDS for Kubernetes
# =============================================================================
# This script configures an EXISTING RDS instance that was created via Console
# It will:
#   1. Retrieve RDS endpoint from AWS
#   2. Get credentials from AWS Secrets Manager (created by Console)
#   3. Create Kubernetes secrets with RDS connection strings
#   4. Optionally create databases (users_db, events_db, bookings_db)
# =============================================================================

set -euo pipefail

# ---------------------- CONFIG (EDIT THESE) ----------------------
REGION="${AWS_REGION:-us-east-1}"
DB_INSTANCE_IDENTIFIER="bookmyevent-rds"
K8S_NAMESPACE="bookmyevent"

# The ARN of the secret created by AWS Console when you created RDS
# Find it in: RDS Console → Your Instance → Configuration → "Manage master credentials in Secrets Manager"
RDS_SECRET_ARN="${RDS_SECRET_ARN:-}"

# Set to "true" to create the application databases (users_db, events_db, bookings_db)
CREATE_DATABASES="${CREATE_DATABASES:-true}"
# -----------------------------------------------------------------

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not installed"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq not installed"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not installed"; exit 1; }

echo "=========================================="
echo "Configure Existing RDS for Kubernetes"
echo "=========================================="

# Validate RDS_SECRET_ARN is provided
if [[ -z "$RDS_SECRET_ARN" ]]; then
  echo ""
  echo "ERROR: RDS_SECRET_ARN environment variable is not set!"
  echo ""
  echo "To find your secret ARN:"
  echo "  1. Go to AWS Console → RDS → Databases → $DB_INSTANCE_IDENTIFIER"
  echo "  2. Click on 'Configuration' tab"
  echo "  3. Look for 'Master credentials ARN' or 'Manage master credentials in Secrets Manager'"
  echo "  4. Copy the ARN (looks like: arn:aws:secretsmanager:REGION:ACCOUNT:secret:...)"
  echo ""
  echo "Then run this script with:"
  echo "  RDS_SECRET_ARN='arn:aws:secretsmanager:...' ./$0"
  echo ""
  exit 1
fi

echo ""
echo "[1/5] Fetching RDS endpoint..."
DB_JSON=$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
  --output json)

DB_ENDPOINT=$(echo "$DB_JSON" | jq -r '.DBInstances[0].Endpoint.Address')
DB_PORT=$(echo "$DB_JSON" | jq -r '.DBInstances[0].Endpoint.Port')
DB_STATUS=$(echo "$DB_JSON" | jq -r '.DBInstances[0].DBInstanceStatus')

if [[ "$DB_ENDPOINT" == "null" || -z "$DB_ENDPOINT" ]]; then
  echo "ERROR: Could not find RDS instance '$DB_INSTANCE_IDENTIFIER'"
  exit 1
fi

echo "  Endpoint: $DB_ENDPOINT"
echo "  Port: $DB_PORT"
echo "  Status: $DB_STATUS"

if [[ "$DB_STATUS" != "available" ]]; then
  echo "  WARNING: RDS status is '$DB_STATUS', not 'available'"
  echo "  You may need to wait for RDS to be ready."
fi

echo ""
echo "[2/5] Retrieving credentials from Secrets Manager..."
SECRET_STRING=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$RDS_SECRET_ARN" \
  --query 'SecretString' \
  --output text)

MASTER_USERNAME=$(echo "$SECRET_STRING" | jq -r '.username')
MASTER_PASSWORD=$(echo "$SECRET_STRING" | jq -r '.password')

if [[ -z "$MASTER_PASSWORD" || "$MASTER_PASSWORD" == "null" ]]; then
  echo "ERROR: Could not parse password from secret"
  exit 1
fi

echo "  Username: $MASTER_USERNAME"
echo "  Password: ********** (retrieved)"

echo ""
echo "[3/5] Creating Kubernetes secrets..."

# URL-encode the password for use in connection strings
URL_ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$MASTER_PASSWORD', safe=''))")

# Create connection strings for each service with URL-encoded password
USER_DB_URL="postgresql://${MASTER_USERNAME}:${URL_ENCODED_PASSWORD}@${DB_ENDPOINT}:${DB_PORT}/users_db?sslmode=require"
EVENT_DB_URL="postgresql://${MASTER_USERNAME}:${URL_ENCODED_PASSWORD}@${DB_ENDPOINT}:${DB_PORT}/events_db?sslmode=require"
BOOKING_DB_URL="postgresql://${MASTER_USERNAME}:${URL_ENCODED_PASSWORD}@${DB_ENDPOINT}:${DB_PORT}/bookings_db?sslmode=require"

# Check if secret exists
if kubectl get secret bookmyevent-secrets -n "$K8S_NAMESPACE" >/dev/null 2>&1; then
  echo "  Updating existing secret 'bookmyevent-secrets'..."
  
  # Get existing secret data
  EXISTING_SECRET=$(kubectl get secret bookmyevent-secrets -n "$K8S_NAMESPACE" -o json)
  
  # Extract existing values we want to keep
  JWT_SECRET=$(echo "$EXISTING_SECRET" | jq -r '.data.JWT_SECRET // empty' | base64 -d 2>/dev/null || echo "")
  INTERNAL_API_KEY=$(echo "$EXISTING_SECRET" | jq -r '.data.INTERNAL_API_KEY // empty' | base64 -d 2>/dev/null || echo "")
  
  # Generate new values if they don't exist
  if [[ -z "$JWT_SECRET" ]]; then
    JWT_SECRET=$(openssl rand -base64 32)
    echo "  Generated new JWT_SECRET"
  else
    echo "  Keeping existing JWT_SECRET"
  fi
  
  if [[ -z "$INTERNAL_API_KEY" ]]; then
    INTERNAL_API_KEY=$(openssl rand -base64 32)
    echo "  Generated new INTERNAL_API_KEY"
  else
    echo "  Keeping existing INTERNAL_API_KEY"
  fi
  
  # Delete and recreate (easier than patching)
  kubectl delete secret bookmyevent-secrets -n "$K8S_NAMESPACE"
else
  echo "  Creating new secret 'bookmyevent-secrets'..."
  
  # Generate new secrets
  JWT_SECRET=$(openssl rand -base64 32)
  INTERNAL_API_KEY=$(openssl rand -base64 32)
  echo "  Generated JWT_SECRET and INTERNAL_API_KEY"
fi

# Create the secret with all values
kubectl create secret generic bookmyevent-secrets \
  -n "$K8S_NAMESPACE" \
  --from-literal=USER_SERVICE_DB_URL="$USER_DB_URL" \
  --from-literal=EVENT_SERVICE_DB_URL="$EVENT_DB_URL" \
  --from-literal=BOOKING_SERVICE_DB_URL="$BOOKING_DB_URL" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=INTERNAL_API_KEY="$INTERNAL_API_KEY" \
  --from-literal=POSTGRES_PASSWORD="$MASTER_PASSWORD"

echo "  ✓ Secret created/updated successfully"

if [[ "$CREATE_DATABASES" == "true" ]]; then
  echo ""
  echo "[4/5] Creating application databases..."
  
  # Create a temporary pod to run psql commands
  kubectl run rds-db-setup \
    --image=postgres:15-alpine \
    --restart=Never \
    -n "$K8S_NAMESPACE" \
    --env="PGPASSWORD=$MASTER_PASSWORD" \
    --env="PGSSLMODE=require" \
    --rm -i --quiet -- \
    psql -h "$DB_ENDPOINT" -U "$MASTER_USERNAME" -d postgres -v ON_ERROR_STOP=0 <<EOF
-- Create databases if they don't exist
SELECT 'CREATE DATABASE users_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'users_db')\gexec
SELECT 'CREATE DATABASE events_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'events_db')\gexec
SELECT 'CREATE DATABASE bookings_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bookings_db')\gexec
EOF

  echo "  ✓ Databases created/verified"
else
  echo ""
  echo "[4/5] Skipping database creation (CREATE_DATABASES=$CREATE_DATABASES)"
fi

echo ""
echo "[5/5] Verification..."
echo "  Testing connection to RDS..."

# Quick connection test
if kubectl run rds-test \
    --image=postgres:15-alpine \
    --restart=Never \
    -n "$K8S_NAMESPACE" \
    --env="PGPASSWORD=$MASTER_PASSWORD" \
    --rm -i --quiet -- \
    pg_isready -h "$DB_ENDPOINT" -U "$MASTER_USERNAME" >/dev/null 2>&1; then
  echo "  ✓ RDS connection successful"
else
  echo "  ⚠ RDS connection test failed (check security groups)"
fi

cat <<EOF

========================================
Configuration Complete!
========================================
RDS Endpoint    : $DB_ENDPOINT:$DB_PORT
Username        : $MASTER_USERNAME
Namespace       : $K8S_NAMESPACE
Secret Name     : bookmyevent-secrets

Database URLs configured:
  - users_db    : postgresql://$MASTER_USERNAME:***@$DB_ENDPOINT:$DB_PORT/users_db
  - events_db   : postgresql://$MASTER_USERNAME:***@$DB_ENDPOINT:$DB_PORT/events_db
  - bookings_db : postgresql://$MASTER_USERNAME:***@$DB_ENDPOINT:$DB_PORT/bookings_db

Next steps:
  1. Deploy/update your services with:
     helm upgrade bookmyevent ./helm \\
       --namespace $K8S_NAMESPACE \\
       --set database.postgres.enabled=false \\
       --reuse-values

  2. Verify services can connect:
     kubectl logs -n $K8S_NAMESPACE deployment/user-service
     kubectl logs -n $K8S_NAMESPACE deployment/event-service

EOF
