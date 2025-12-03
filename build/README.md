# Build Configuration

This directory contains all build-related configuration files and CI/CD documentation for the BookMyEvent microservices application.

## Contents

### Documentation

**CI/CD Guides:**
- `ci-cd-guide.md` - Complete CI/CD pipeline documentation
- `ci-cd-quickstart.md` - Quick start guide for CI/CD setup
- `ci-cd-testing-guide.md` - Testing and validation guide
- `github-setup.md` - GitHub Actions setup and configuration

### Dockerfiles

Multi-stage Dockerfiles for all services:

- `Dockerfile-user-service` - User authentication and management service
- `Dockerfile-event-service` - Event creation and management service
- `Dockerfile-search-service` - Elasticsearch-based search service
- `Dockerfile-booking-service` - Event booking and waitlist service
- `Dockerfile-frontend` - React frontend application
- `Dockerfile-init-container` - Database initialization container

### Build Tools

- `Makefile` - Make targets for local development and testing
- `docker-compose.yml` - Local development environment orchestration
- `nginx.conf` - NGINX reverse proxy configuration for local development

## Usage

### Building Individual Services

```bash
# From repository root
docker build -f build/Dockerfile-user-service -t user-service:latest .
```

### Building All Services

Use the automated script:

```bash
./scripts/eks/2-build-push-images.sh
```

Or use docker-compose for local development:

```bash
docker-compose -f build/docker-compose.yml up --build
```

### Using Makefile

```bash
# Build all services
make -f build/Makefile build

# Run tests
make -f build/Makefile test

# Clean build artifacts
make -f build/Makefile clean
```

## CI/CD Integration

The GitHub Actions workflows automatically reference these Dockerfiles:

- `.github/workflows/ci-build-and-push.yml` - Builds and pushes to ECR
- `.github/workflows/pr-validation.yml` - Validates Dockerfiles with hadolint

**Quick Setup:**
See [ci-cd-quickstart.md](ci-cd-quickstart.md) for 3-step CI/CD setup.

**Complete Documentation:**
See [ci-cd-guide.md](ci-cd-guide.md) for comprehensive CI/CD documentation.

## Notes

- All Dockerfiles use multi-stage builds to minimize image size
- Images are optimized for production deployment
- Frontend Dockerfile accepts `VITE_API_URL` build argument for API endpoint configuration
