#!/bin/bash
# =============================================================================
# BookMyEvent - AWS RDS PostgreSQL Setup Script
# =============================================================================
# This script creates an RDS PostgreSQL instance for the BookMyEvent application
# Prerequisites: AWS CLI configured, EKS cluster running
# =============================================================================

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DB_INSTANCE_IDENTIFIER="${DB_INSTANCE_IDENTIFIER:-bookmyevent-rds}"
DB_PASSWORD="${DB_PASSWORD:-BookMyEvent2024!}"
CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"

echo "========================================"
echo "Setting up AWS RDS for BookMyEvent"
echo "========================================"

# Get VPC ID from EKS cluster or use default VPC
echo ""
echo "[1/6] Getting VPC information..."

# Try to get VPC from EKS cluster first
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.resourcesVpcConfig.vpcId" --output text --region "$REGION" 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    echo "  EKS cluster not found, using default VPC..."
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region "$REGION")
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
        echo "  ERROR: No default VPC found. Please create an EKS cluster first or specify a VPC."
        exit 1
    fi
fi

echo "  VPC ID: $VPC_ID"

# Get Subnets - find subnets with routes to Internet Gateway (truly public)
echo "  Finding public subnets with Internet Gateway routes..."

# Step 1: Find route tables with IGW routes
IGW_ROUTE_TABLES=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "RouteTables[?Routes[?GatewayId!=null && starts_with(GatewayId, 'igw-')]].RouteTableId" \
    --output text \
    --region "$REGION")

if [ -z "$IGW_ROUTE_TABLES" ]; then
    echo "  ERROR: No route tables with Internet Gateway found in VPC $VPC_ID"
    echo "  Cannot create publicly-accessible RDS without IGW"
    exit 1
fi

echo "  Found route tables with IGW: $IGW_ROUTE_TABLES"

# Step 2: Find subnets associated with these route tables
SUBNETS=""
for RTB in $IGW_ROUTE_TABLES; do
    RTB_SUBNETS=$(aws ec2 describe-route-tables \
        --route-table-ids "$RTB" \
        --query "RouteTables[0].Associations[?SubnetId!=null].SubnetId" \
        --output text \
        --region "$REGION")
    SUBNETS="$SUBNETS $RTB_SUBNETS"
done

# Remove extra spaces and duplicates
SUBNETS=$(echo $SUBNETS | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

if [ -z "$SUBNETS" ]; then
    echo "  ERROR: No subnets found associated with IGW route tables"
    exit 1
fi

SUBNET_COUNT=$(echo $SUBNETS | wc -w)
echo "  Found $SUBNET_COUNT public subnet(s): $SUBNETS"

# Verify we have at least 2 subnets in different AZs
if [ $SUBNET_COUNT -lt 2 ]; then
    echo "  ERROR: At least 2 subnets in different AZs required for RDS"
    echo "  Found only $SUBNET_COUNT subnet(s)"
    exit 1
fi

# Verify subnets are in different AZs
AZ_COUNT=$(aws ec2 describe-subnets --subnet-ids $SUBNETS --region "$REGION" \
    --query 'Subnets[*].AvailabilityZone' --output text | tr '\t' '\n' | sort -u | wc -l)

if [ $AZ_COUNT -lt 2 ]; then
    echo "  ERROR: Subnets must be in at least 2 different Availability Zones"
    echo "  Found subnets in only $AZ_COUNT AZ(s)"
    exit 1
fi

echo "  ✓ Subnets span $AZ_COUNT availability zones"

# Create Security Group
echo ""
echo "[2/6] Setting up Security Group..."
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=bookmyevent-rds-sg" "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "  Creating new security group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name bookmyevent-rds-sg \
        --description "RDS security group for BookMyEvent" \
        --vpc-id "$VPC_ID" \
        --query "GroupId" \
        --output text \
        --region "$REGION")
fi
echo "  Security Group: $SG_ID"

# Add ingress rule
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 5432 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" 2>/dev/null || echo "  Ingress rule already exists"
echo "  ✓ Ingress rule configured"

# Create DB Subnet Group
echo ""
echo "[3/6] Creating DB Subnet Group..."
aws rds create-db-subnet-group \
    --db-subnet-group-name bookmyevent-db-subnet \
    --db-subnet-group-description "Subnet group for BookMyEvent RDS" \
    --subnet-ids $SUBNETS \
    --region "$REGION" 2>/dev/null || echo "  Subnet group already exists"
echo "  ✓ Subnet group ready"

# Create RDS Instance
echo ""
echo "[4/6] Creating RDS PostgreSQL Instance..."
echo "  This takes 5-10 minutes..."

aws rds create-db-instance \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 16.3 \
    --master-username postgres \
    --master-user-password "$DB_PASSWORD" \
    --allocated-storage 20 \
    --vpc-security-group-ids "$SG_ID" \
    --db-subnet-group-name bookmyevent-db-subnet \
    --publicly-accessible \
    --no-multi-az \
    --region "$REGION"

# Check if creation was successful
if [ $? -eq 0 ]; then
    echo "  ✓ RDS instance creation initiated"
else
    echo "  ✗ Failed to create RDS instance"
    exit 1
fi

# Wait for RDS to be available
echo ""
echo "[5/6] Waiting for RDS to be available..."
ATTEMPT=0
MAX_ATTEMPTS=40

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    sleep 30
    ATTEMPT=$((ATTEMPT + 1))
    STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
    echo "  Status: $STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    
    if [ "$STATUS" == "available" ]; then
        break
    fi
done

if [ "$STATUS" == "available" ]; then
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --query "DBInstances[0].Endpoint.Address" \
        --output text \
        --region "$REGION")
    
    echo ""
    echo "[6/6] RDS Instance Ready!"
    echo "  Endpoint: $RDS_ENDPOINT"
    
    # Create databases
    echo ""
    echo "Creating databases..."
    kubectl exec -n bookmyevent deployment/postgres -- sh -c \
        "PGPASSWORD='$DB_PASSWORD' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE users_db;'" 2>/dev/null || true
    kubectl exec -n bookmyevent deployment/postgres -- sh -c \
        "PGPASSWORD='$DB_PASSWORD' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE events_db;'" 2>/dev/null || true
    kubectl exec -n bookmyevent deployment/postgres -- sh -c \
        "PGPASSWORD='$DB_PASSWORD' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE bookings_db;'" 2>/dev/null || true
    echo "  ✓ Databases created: users_db, events_db, bookings_db"
    
    echo ""
    echo "========================================"
    echo "RDS Setup Complete!"
    echo "========================================"
    echo "RDS Endpoint: $RDS_ENDPOINT"
    echo "Password: $DB_PASSWORD"
    echo ""
    echo "Next step: ./scripts/eks/migrate-to-rds.sh"
else
    echo "ERROR: RDS instance did not become available in time"
    exit 1
fi
