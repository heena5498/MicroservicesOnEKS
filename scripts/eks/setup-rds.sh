#!/usr/bin/env bash
# =============================================================================
# BookMyEvent - RDS PostgreSQL Creation Script
# =============================================================================
# Creates:
#   - Security group for RDS
#   - DB subnet group (using subnets from EKS cluster VPC)
#   - Secrets Manager secret with master username/password
#   - RDS PostgreSQL instance (db.t3.micro, single AZ, 20 GiB gp2)
# =============================================================================

set -euo pipefail

# ---------------------- CONFIG (EDIT) ----------------------
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-eks}"

DB_INSTANCE_IDENTIFIER="bookmyevent-rds"
MASTER_USERNAME="postgres"
ALLOCATED_STORAGE_GB=20

SG_NAME="bookmyevent-rds-sg"
DB_SUBNET_GROUP_NAME="bookmyevent-db-subnet"
SECRET_NAME="bookmyevent-rds-master-credentials"
# -----------------------------------------------------------

command -v aws >/dev/null 2>&1 || { echo "aws CLI not installed"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq not installed"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl not installed"; exit 1; }

echo "[1/7] Get VPC from EKS cluster '$CLUSTER_NAME' ..."
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "ERROR: Could not get VPC for cluster $CLUSTER_NAME"; exit 1;
fi
echo "  VPC: $VPC_ID"

echo
echo "[2/7] Find public subnets (with Internet Gateway route) ..."
IGW_ROUTE_TABLES=$(aws ec2 describe-route-tables \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[?Routes[?GatewayId!=null && starts_with(GatewayId, 'igw-')]].RouteTableId" \
  --output text)

if [[ -z "$IGW_ROUTE_TABLES" ]]; then
  echo "ERROR: No route tables with IGW in VPC $VPC_ID"; exit 1;
fi

SUBNETS=""
for RTB in $IGW_ROUTE_TABLES; do
  RTB_SUBNETS=$(aws ec2 describe-route-tables \
    --region "$REGION" \
    --route-table-ids "$RTB" \
    --query "RouteTables[0].Associations[?SubnetId!=null].SubnetId" \
    --output text)
  SUBNETS="$SUBNETS $RTB_SUBNETS"
done

SUBNETS=$(echo "$SUBNETS" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)
SUBNET_COUNT=$(echo "$SUBNETS" | wc -w)

if [[ $SUBNET_COUNT -lt 2 ]]; then
  echo "ERROR: Need at least 2 public subnets, found $SUBNET_COUNT"; exit 1;
fi
echo "  Public subnets: $SUBNETS"

AZ_COUNT=$(aws ec2 describe-subnets \
  --region "$REGION" \
  --subnet-ids $SUBNETS \
  --query "Subnets[*].AvailabilityZone" \
  --output text | tr '\t' '\n' | sort -u | wc -l)

if [[ $AZ_COUNT -lt 2 ]]; then
  echo "ERROR: Subnets must span at least 2 AZs, found $AZ_COUNT"; exit 1;
fi
echo "  Subnets span $AZ_COUNT AZs"

echo
echo "[3/7] Create / get Security Group '$SG_NAME' ..."
SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || echo "")

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "RDS SG for BookMyEvent" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
  echo "  Created SG: $SG_ID"
else
  echo "  Using existing SG: $SG_ID"
fi

aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-id "$SG_ID" \
  --protocol tcp --port 5432 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "  Ingress already present"

echo
echo "[4/7] Create / get DB subnet group '$DB_SUBNET_GROUP_NAME' ..."
aws rds create-db-subnet-group \
  --region "$REGION" \
  --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
  --db-subnet-group-description "BookMyEvent RDS subnet group" \
  --subnet-ids $SUBNETS 2>/dev/null || echo "  Subnet group already exists"

echo
echo "[5/7] Create / update Secrets Manager secret '$SECRET_NAME' ..."
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')

SECRET_PAYLOAD=$(jq -n \
  --arg user "$MASTER_USERNAME" \
  --arg pwd "$DB_PASSWORD" \
  '{username:$user, password:$pwd}')

if aws secretsmanager describe-secret \
    --region "$REGION" \
    --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value \
    --region "$REGION" \
    --secret-id "$SECRET_NAME" \
    --secret-string "$SECRET_PAYLOAD" >/dev/null
  echo "  Updated existing secret."
else
  aws secretsmanager create-secret \
    --region "$REGION" \
    --name "$SECRET_NAME" \
    --description "Master credentials for $DB_INSTANCE_IDENTIFIER" \
    --secret-string "$SECRET_PAYLOAD" >/dev/null
  echo "  Created new secret."
fi

echo
echo "[6/7] Create RDS PostgreSQL instance '$DB_INSTANCE_IDENTIFIER' ..."
if aws rds describe-db-instances \
    --region "$REGION" \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" >/dev/null 2>&1; then
  echo "  Instance already exists, skipping create."
else
  aws rds create-db-instance \
    --region "$REGION" \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 16.3 \
    --master-username "$MASTER_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --allocated-storage "$ALLOCATED_STORAGE_GB" \
    --storage-type gp2 \
    --vpc-security-group-ids "$SG_ID" \
    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
    --publicly-accessible \
    --no-multi-az

  echo "  Waiting for RDS to become available (this can take several minutes)..."
  aws rds wait db-instance-available \
    --region "$REGION" \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER"
fi

echo
echo "[7/7] Fetch final endpoint info ..."
DB_JSON=$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
  --output json)

DB_ENDPOINT=$(echo "$DB_JSON" | jq -r '.DBInstances[0].Endpoint.Address')
DB_PORT=$(echo "$DB_JSON" | jq -r '.DBInstances[0].Endpoint.Port')

cat <<EOF

========================================
RDS Setup Complete
========================================
Cluster     : $CLUSTER_NAME
VPC         : $VPC_ID
Subnets     : $SUBNETS
SG          : $SG_ID

Endpoint    : $DB_ENDPOINT
Port        : $DB_PORT
Username    : $MASTER_USERNAME
Password    : (stored in Secrets Manager secret: $SECRET_NAME)

To retrieve the password later:

  aws secretsmanager get-secret-value \\
    --region "$REGION" \\
    --secret-id "$SECRET_NAME" \\
    --query 'SecretString' --output text | jq -r '.password'

EOF
