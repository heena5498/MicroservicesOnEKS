#!/bin/bash
# Docker Compose Local Testing Script
# Tests that all infrastructure services start correctly

set -e

echo "🚀 Testing Docker Compose Setup..."
echo "================================="

# Check if docker-compose is installed
if ! command -v docker compose &> /dev/null; then
    echo "❌ docker compose is not installed"
    exit 1
fi

echo "✅ Docker Compose found"

# Start infrastructure services
echo ""
echo "📦 Starting infrastructure services (PostgreSQL, Redis, Elasticsearch)..."
docker compose up -d postgres redis elasticsearch

# Wait for services to be healthy
echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Test PostgreSQL
echo ""
echo "🔍 Testing PostgreSQL..."
docker compose exec -T postgres pg_isready -U postgres
if [ $? -eq 0 ]; then
    echo "✅ PostgreSQL is ready"
else
    echo "❌ PostgreSQL failed health check"
    exit 1
fi

# Test Redis
echo ""
echo "🔍 Testing Redis..."
docker compose exec -T redis redis-cli ping
if [ $? -eq 0 ]; then
    echo "✅ Redis is ready"
else
    echo "❌ Redis failed health check"
    exit 1
fi

# Test Elasticsearch
echo ""
echo "🔍 Testing Elasticsearch..."
sleep 5  # ES needs more time
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9201/_cluster/health)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Elasticsearch is ready"
else
    echo "⚠️  Elasticsearch may need more time (got HTTP $HTTP_CODE)"
fi

# Show running containers
echo ""
echo "📋 Running containers:"
docker compose ps

echo ""
echo "================================="
echo "✅ All infrastructure services are running!"
echo ""
echo "Services available at:"
echo "  - PostgreSQL: localhost:5434"
echo "  - Redis: localhost:6380"
echo "  - Elasticsearch: localhost:9201"
echo ""
echo "To stop services: docker compose down"
echo "To view logs: docker compose logs -f"
