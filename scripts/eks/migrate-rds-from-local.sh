#!/bin/bash
set -e

echo "=================================================="
echo "Running Database Migrations via Kubernetes Pod"
echo "=================================================="

# Get database URLs from secrets
echo "Fetching database credentials from Kubernetes secrets..."
USER_DB_URL=$(kubectl get secret bookmyevent-secrets -n bookmyevent -o jsonpath='{.data.USER_SERVICE_DB_URL}' | base64 -d)
EVENT_DB_URL=$(kubectl get secret bookmyevent-secrets -n bookmyevent -o jsonpath='{.data.EVENT_SERVICE_DB_URL}' | base64 -d)
BOOKING_DB_URL=$(kubectl get secret bookmyevent-secrets -n bookmyevent -o jsonpath='{.data.BOOKING_SERVICE_DB_URL}' | base64 -d)

echo "✓ Credentials retrieved"
echo ""

# Check if goose is installed
if ! command -v goose &> /dev/null; then
    echo "ERROR: goose is not installed locally"
    echo "Install it with one of these commands:"
    echo "  macOS: brew install goose"
    echo "  Go: go install github.com/pressly/goose/v3/cmd/goose@latest"
    exit 1
fi

echo "✓ goose is installed"
echo ""

# Run migrations
echo "Running User Service Migrations..."
echo "------------------------------------"
goose -dir migrations/user-service postgres "$USER_DB_URL" up
echo "✓ User service migrations complete"
echo ""

echo "Running Event Service Migrations (includes admins table)..."
echo "------------------------------------------------------------"
goose -dir migrations/event-service postgres "$EVENT_DB_URL" up
echo "✓ Event service migrations complete"
echo ""

echo "Running Booking Service Migrations..."
echo "--------------------------------------"
goose -dir migrations/booking-service postgres "$BOOKING_DB_URL" up
echo "✓ Booking service migrations complete"
echo ""

echo "=================================================="
echo "✅ ALL MIGRATIONS COMPLETED SUCCESSFULLY!"
echo "=================================================="
echo ""
echo "Summary:"
echo "  ✓ users_db - User authentication tables"
echo "  ✓ events_db - Events, venues, and ADMINS tables"
echo "  ✓ bookings_db - Booking and reservation tables"
echo ""
echo "You can now test admin registration:"
echo "  export ALB_URL=\$(kubectl get ingress bookmyevent-ingress -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "  curl -X POST http://\${ALB_URL}/api/event/auth/admin/register \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"email\":\"newadmin@test.com\",\"password\":\"admin123\",\"name\":\"Test Admin\"}'"
