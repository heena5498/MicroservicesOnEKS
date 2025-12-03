apiVersion: v1
kind: Secret
metadata:
  name: bookmyevent-secrets
  namespace: bookmyevent
type: Opaque
stringData:
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "${DB_PASSWORD}"
  # Database URLs
  USER_SERVICE_DB_URL: "postgresql://postgres:${DB_PASSWORD}@postgres:5432/users_db?sslmode=disable"
  EVENT_SERVICE_DB_URL: "postgresql://postgres:${DB_PASSWORD}@postgres:5432/events_db?sslmode=disable"
  BOOKING_SERVICE_DB_URL: "postgresql://postgres:${DB_PASSWORD}@postgres:5432/bookings_db?sslmode=disable"
  JWT_SECRET: "${JWT_SECRET}"
  INTERNAL_API_KEY: "${INTERNAL_API_KEY}"



