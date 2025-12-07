#!/bin/bash
set -e

echo "=========================================="
echo "BookMyEvent RDS Database Migrations"
echo "=========================================="

# RDS Configuration
RDS_ENDPOINT="${RDS_ENDPOINT:-bookmyevent-db.cxqhwipqvfb9.us-east-1.rds.amazonaws.com}"
RDS_PASSWORD="${RDS_PASSWORD:-}"

if [ -z "$RDS_PASSWORD" ]; then
  echo "ERROR: RDS_PASSWORD environment variable is required"
  echo "Usage: RDS_PASSWORD=your_password RDS_ENDPOINT=your_endpoint.rds.amazonaws.com ./run-rds-migrations.sh"
  exit 1
fi
RDS_USER="${RDS_USER:-postgres}"

echo "RDS Endpoint: $RDS_ENDPOINT"
echo ""

# Check if goose is installed
if ! command -v goose &> /dev/null; then
    echo "ERROR: goose is not installed"
    echo "Install it with: brew install goose (macOS) or go install github.com/pressly/goose/v3/cmd/goose@latest"
    exit 1
fi

echo "✓ goose installed: $(goose -version)"
echo ""

# Function to run migrations for a service
run_migration() {
    local service=$1
    local db_name=$2
    local migration_dir="migrations/${service}-service"
    
    echo "----------------------------------------"
    echo "Migrating: $service-service → $db_name"
    echo "----------------------------------------"
    
    if [ ! -d "$migration_dir" ]; then
        echo "ERROR: Migration directory not found: $migration_dir"
        return 1
    fi
    
    local conn_string="host=$RDS_ENDPOINT port=5432 user=$RDS_USER dbname=$db_name password=$RDS_PASSWORD sslmode=require"
    
    echo "Running migrations from: $migration_dir"
    goose -dir "$migration_dir" postgres "$conn_string" up
    
    echo "✓ $service-service migrations complete"
    echo ""
}

# Run migrations for all services
echo "Starting migrations..."
echo ""

run_migration "user" "users_db"
run_migration "event" "events_db"
run_migration "booking" "bookings_db"

echo "=========================================="
echo "✅ All migrations completed successfully!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ users_db migrated"
echo "  ✓ events_db migrated (includes admins table)"
echo "  ✓ bookings_db migrated"
echo ""
echo "You can now test admin registration:"
echo "  curl -X POST http://\${ALB_URL}/api/event/auth/admin/register \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"email\":\"admin@test.com\",\"password\":\"admin123\",\"name\":\"Admin\"}'"
