# ⚠️  WARNING: This file contains default development values.
# For production deployments, update all security-related values.
# See k8s/03-env-file-configmap.yaml.example for a template with placeholders.

apiVersion: v1
kind: ConfigMap
metadata:
  name: env-file
  namespace: bookmyevent
data:
  .env: |
    # Service Ports
    USER_SERVICE_PORT=8001
    EVENT_SERVICE_PORT=8002
    SEARCH_SERVICE_PORT=8003
    BOOKING_SERVICE_PORT=8004
    
    # Database URLs (update passwords for production)
    USER_SERVICE_DB_URL=postgresql://postgres:${DB_PASSWORD}@postgres:5432/users_db?sslmode=disable
    EVENT_SERVICE_DB_URL=postgresql://postgres:${DB_PASSWORD}@postgres:5432/events_db?sslmode=disable
    BOOKING_SERVICE_DB_URL=postgresql://postgres:${DB_PASSWORD}@postgres:5432/bookings_db?sslmode=disable
    
    # Redis
    REDIS_URL=redis://redis:6379
    
    # Elasticsearch
    ELASTICSEARCH_URL=http://elasticsearch:9200
    
    # Service URLs for inter-service communication
    USER_SERVICE_URL=http://user-service:8001
    EVENT_SERVICE_URL=http://event-service:8002
    SEARCH_SERVICE_URL=http://search-service:8003
    BOOKING_SERVICE_URL=http://booking-service:8004
    
    # Security (CHANGE THESE IN PRODUCTION!)
    # Generate secure secrets: openssl rand -base64 32
    JWT_SECRET="${JWT_SECRET}"
    INTERNAL_API_KEY="${INTERNAL_API_KEY}"
    
    # Environment
    ENVIRONMENT=production

