# =============================================================================
# BookMyEvent - Migrate Data to RDS Script
# =============================================================================
# This script migrates data from in-cluster PostgreSQL to AWS RDS
# Prerequisites: RDS instance created, EKS cluster running with postgres pod
# =============================================================================

param(
    [string]$RDSEndpoint = "",
    [string]$DBPassword = "BookMyEvent2024!",
    [string]$Namespace = "bookmyevent"
)

if ([string]::IsNullOrEmpty($RDSEndpoint)) {
    Write-Host "Getting RDS endpoint..." -ForegroundColor Yellow
    $RDSEndpoint = aws rds describe-db-instances --db-instance-identifier bookmyevent-rds --query "DBInstances[0].Endpoint.Address" --output text --region us-east-1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Migrating Data to AWS RDS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS Endpoint: $RDSEndpoint" -ForegroundColor Gray

# Migrate events_db
Write-Host "`n[1/3] Migrating events_db..." -ForegroundColor Yellow
kubectl exec -n $Namespace deployment/postgres -- sh -c "PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d events_db -c 'DROP TABLE IF EXISTS events CASCADE; DROP TABLE IF EXISTS venues CASCADE; DROP TABLE IF EXISTS admin_refresh_tokens CASCADE; DROP TABLE IF EXISTS admins CASCADE;'" 2>$null
kubectl exec -n $Namespace deployment/postgres -- sh -c "pg_dump -U postgres -d events_db --schema-only | PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d events_db"
kubectl exec -n $Namespace deployment/postgres -- sh -c "pg_dump -U postgres -d events_db --data-only | PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d events_db"
Write-Host "  events_db migrated" -ForegroundColor Green

# Migrate users_db
Write-Host "`n[2/3] Migrating users_db..." -ForegroundColor Yellow
kubectl exec -n $Namespace deployment/postgres -- sh -c "PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d users_db -c 'DROP TABLE IF EXISTS refresh_tokens CASCADE; DROP TABLE IF EXISTS users CASCADE;'" 2>$null
kubectl exec -n $Namespace deployment/postgres -- sh -c "pg_dump -U postgres -d users_db --schema-only | PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d users_db"
kubectl exec -n $Namespace deployment/postgres -- sh -c "pg_dump -U postgres -d users_db --data-only | PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d users_db"
Write-Host "  users_db migrated" -ForegroundColor Green

# Migrate bookings_db
Write-Host "`n[3/3] Migrating bookings_db..." -ForegroundColor Yellow
kubectl exec -n $Namespace deployment/postgres -- sh -c "PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d bookings_db -c 'DROP TABLE IF EXISTS booking_seats CASCADE; DROP TABLE IF EXISTS payments CASCADE; DROP TABLE IF EXISTS waitlist CASCADE; DROP TABLE IF EXISTS bookings CASCADE;'" 2>$null
kubectl exec -n $Namespace deployment/postgres -- sh -c "pg_dump -U postgres -d bookings_db --schema-only | PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d bookings_db"
kubectl exec -n $Namespace deployment/postgres -- sh -c "pg_dump -U postgres -d bookings_db --data-only | PGPASSWORD='$DBPassword' psql -h $RDSEndpoint -U postgres -d bookings_db"
Write-Host "  bookings_db migrated" -ForegroundColor Green

# Update Kubernetes secrets
Write-Host "`nUpdating Kubernetes secrets..." -ForegroundColor Yellow

$secretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: bookmyevent-secrets
  namespace: $Namespace
type: Opaque
stringData:
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "$DBPassword"
  USER_SERVICE_DB_URL: "postgresql://postgres:$DBPassword@$RDSEndpoint:5432/users_db?sslmode=require"
  EVENT_SERVICE_DB_URL: "postgresql://postgres:$DBPassword@$RDSEndpoint:5432/events_db?sslmode=require"
  BOOKING_SERVICE_DB_URL: "postgresql://postgres:$DBPassword@$RDSEndpoint:5432/bookings_db?sslmode=require"
  JWT_SECRET: "super-secret-jwt-key-for-bookmyevent-2024"
  INTERNAL_API_KEY: "internal-api-key-for-service-communication-2024"
"@

$secretYaml | Out-File -FilePath "k8s/02-secrets-rds.yaml" -Encoding UTF8
kubectl apply -f k8s/02-secrets-rds.yaml

# Restart services
Write-Host "`nRestarting services..." -ForegroundColor Yellow
kubectl rollout restart deployment/user-service deployment/event-service deployment/booking-service deployment/search-service -n $Namespace

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Migration Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "All data migrated to RDS" -ForegroundColor Green
Write-Host "Services restarted with new configuration" -ForegroundColor Green
Write-Host "`nNext step: Run setup-dns-ssl.ps1" -ForegroundColor Yellow


