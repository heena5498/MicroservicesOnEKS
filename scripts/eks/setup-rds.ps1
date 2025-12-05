# =============================================================================
# BookMyEvent - AWS RDS PostgreSQL Setup Script
# =============================================================================
# This script creates an RDS PostgreSQL instance for the BookMyEvent application
# Prerequisites: AWS CLI configured, EKS cluster running
# =============================================================================

param(
    [string]$Region = "us-east-1",
    [string]$DBInstanceIdentifier = "bookmyevent-rds",
    [string]$DBPassword = "BookMyEvent2024!",
    [string]$ClusterName = "bookmyevent-cluster"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting up AWS RDS for BookMyEvent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Get VPC ID from EKS cluster
Write-Host "`n[1/6] Getting VPC information from EKS cluster..." -ForegroundColor Yellow
$VPC_ID = aws eks describe-cluster --name $ClusterName --query "cluster.resourcesVpcConfig.vpcId" --output text --region $Region
Write-Host "  VPC ID: $VPC_ID" -ForegroundColor Green

# Get Subnets
$SUBNETS = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text --region $Region
$SUBNET_ARRAY = $SUBNETS -split "`t"
Write-Host "  Found $($SUBNET_ARRAY.Count) subnets" -ForegroundColor Green

# Create Security Group
Write-Host "`n[2/6] Setting up Security Group..." -ForegroundColor Yellow
$SG_ID = aws ec2 describe-security-groups --filters "Name=group-name,Values=bookmyevent-rds-sg" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text --region $Region 2>$null

if ($SG_ID -eq "None" -or [string]::IsNullOrEmpty($SG_ID)) {
    Write-Host "  Creating new security group..." -ForegroundColor Gray
    $SG_ID = aws ec2 create-security-group --group-name bookmyevent-rds-sg --description "RDS security group for BookMyEvent" --vpc-id $VPC_ID --query "GroupId" --output text --region $Region
}
Write-Host "  Security Group: $SG_ID" -ForegroundColor Green

# Add ingress rule
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 5432 --cidr 0.0.0.0/0 --region $Region 2>$null
Write-Host "  Ingress rule configured" -ForegroundColor Green

# Create DB Subnet Group
Write-Host "`n[3/6] Creating DB Subnet Group..." -ForegroundColor Yellow
aws rds create-db-subnet-group --db-subnet-group-name bookmyevent-db-subnet --db-subnet-group-description "Subnet group for BookMyEvent RDS" --subnet-ids $SUBNET_ARRAY --region $Region 2>$null
Write-Host "  Subnet group ready" -ForegroundColor Green

# Create RDS Instance
Write-Host "`n[4/6] Creating RDS PostgreSQL Instance..." -ForegroundColor Yellow
Write-Host "  This takes 5-10 minutes..." -ForegroundColor Gray

aws rds create-db-instance `
    --db-instance-identifier $DBInstanceIdentifier `
    --db-instance-class db.t3.micro `
    --engine postgres `
    --engine-version 16.3 `
    --master-username postgres `
    --master-user-password $DBPassword `
    --allocated-storage 20 `
    --vpc-security-group-ids $SG_ID `
    --db-subnet-group-name bookmyevent-db-subnet `
    --publicly-accessible `
    --no-multi-az `
    --region $Region 2>$null

# Wait for RDS to be available
Write-Host "`n[5/6] Waiting for RDS to be available..." -ForegroundColor Yellow
$attempt = 0
$maxAttempts = 40

do {
    Start-Sleep -Seconds 30
    $attempt++
    $status = aws rds describe-db-instances --db-instance-identifier $DBInstanceIdentifier --query "DBInstances[0].DBInstanceStatus" --output text --region $Region 2>$null
    Write-Host "  Status: $status (attempt $attempt/$maxAttempts)" -ForegroundColor Gray
} while ($status -ne "available" -and $attempt -lt $maxAttempts)

if ($status -eq "available") {
    $RDS_ENDPOINT = aws rds describe-db-instances --db-instance-identifier $DBInstanceIdentifier --query "DBInstances[0].Endpoint.Address" --output text --region $Region
    Write-Host "`n[6/6] RDS Instance Ready!" -ForegroundColor Green
    Write-Host "  Endpoint: $RDS_ENDPOINT" -ForegroundColor Cyan
    
    # Create databases
    Write-Host "`nCreating databases..." -ForegroundColor Yellow
    kubectl exec -n bookmyevent deployment/postgres -- sh -c "PGPASSWORD='$DBPassword' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE users_db;'" 2>$null
    kubectl exec -n bookmyevent deployment/postgres -- sh -c "PGPASSWORD='$DBPassword' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE events_db;'" 2>$null
    kubectl exec -n bookmyevent deployment/postgres -- sh -c "PGPASSWORD='$DBPassword' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE bookings_db;'" 2>$null
    Write-Host "  Databases created: users_db, events_db, bookings_db" -ForegroundColor Green
    
    # Output for next steps
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "RDS Setup Complete!" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "RDS Endpoint: $RDS_ENDPOINT" -ForegroundColor White
    Write-Host "Password: $DBPassword" -ForegroundColor White
    Write-Host "`nNext step: Run migrate-to-rds.ps1" -ForegroundColor Yellow
} else {
    Write-Host "ERROR: RDS instance did not become available in time" -ForegroundColor Red
    exit 1
}
