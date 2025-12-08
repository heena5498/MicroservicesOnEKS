# Build Scripts Documentation

This folder contains scripts for building and pushing Docker images for the BookMyEvent microservices.

## 📜 Scripts Overview

### `build-local.sh`
Builds Docker images locally for all or specific microservices.

**Usage:**
```bash
# Build all services
./scripts/build-local.sh all

# Build all with custom tag
./scripts/build-local.sh all v1.0.0

# Build specific service
./scripts/build-local.sh user-service
./scripts/build-local.sh booking-service latest
```

**Available Services:**
- `user-service` - User authentication and profile management
- `event-service` - Event creation and management
- `booking-service` - Booking and reservation system (payment-free for campus events)
- `search-service` - Elasticsearch-powered search
- `frontend` - React web application
- `init-container` - Database initialization container

**Environment Variables:**
- `ECR_REGISTRY` - ECR repository URL (auto-detected from AWS CLI if not set)
- `AWS_REGION` - AWS region (default: us-east-1)

**Example:**
```bash
# Use custom ECR registry
ECR_REGISTRY="123456789.dkr.ecr.us-east-1.amazonaws.com/bookmyevent" \
  ./scripts/build-local.sh all

# Build for specific region
AWS_REGION="us-east-1" ./scripts/build-local.sh user-service
```

---

### `push-to-ecr.sh`
Pushes Docker images to Amazon ECR (Elastic Container Registry).

**Prerequisites:**
- AWS CLI configured with valid credentials
- ECR repository created (`bookmyevent` repository in ECR)
- Docker logged in to ECR

**Usage:**
```bash
# Login to ECR first
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Push all services
./scripts/push-to-ecr.sh all

# Push specific service
./scripts/push-to-ecr.sh booking-service

# Push with custom tag
./scripts/push-to-ecr.sh booking-service v1.0.0
```

**Features:**
- Automatic ECR login
- Tags images with both specified tag and `latest`
- Validates services before pushing
- Color-coded output for better visibility

**Environment Variables:**
- `ECR_REGISTRY` - ECR repository URL (auto-detected from AWS CLI if not set)
- `AWS_REGION` - AWS region (default: us-east-1)

---

## 🔄 CI/CD Integration

### GitHub Actions Workflow

The `.github/workflows/build-and-deploy.yml` workflow automates the entire build and deployment process:

**Pipeline Stages:**

1. **Test** - Run Go unit tests and security scans
2. **Build** - Build Docker images for all services
3. **Deploy** - Deploy to AWS EKS with Helm
4. **Integration Tests** - Run API endpoint tests
5. **Notify** - Send deployment status notifications

**Triggers:**
- Push to `main`, `build`, or `dev` branches
- Pull requests to `main` or `build`
- Manual workflow dispatch

**Workflow Features:**
- ✅ Multi-platform Docker builds (linux/amd64)
- ✅ Trivy security scanning (source code + images)
- ✅ GitHub Security SARIF upload
- ✅ Semantic versioning (latest, SHA, branch)
- ✅ Helm atomic upgrades
- ✅ RDS database migrations
- ✅ Automated health checks
- ✅ Integration test suite

**Secrets Required:**
```yaml
AWS_ACCESS_KEY_ID       # AWS IAM credentials
AWS_SECRET_ACCESS_KEY   # AWS IAM credentials
AWS_REGION              # AWS region (e.g., us-east-1)
EKS_CLUSTER_NAME        # EKS cluster name
RDS_ENDPOINT            # RDS PostgreSQL endpoint
RDS_PASSWORD            # RDS master password
JWT_SECRET              # JWT signing secret
INTERNAL_API_KEY        # Internal API authentication key
```

---

## 🐳 Docker Build Process

### Multi-Stage Builds

All services use optimized multi-stage Dockerfiles:

**Stage 1: Builder**
- Base: `golang:1.24-alpine` (or `node:18-alpine` for frontend)
- Installs dependencies
- Compiles application
- Runs tests (optional)

**Stage 2: Runtime**
- Base: `alpine:latest`
- Copies only compiled binary
- Runs as non-root user
- Minimal attack surface

**Benefits:**
- Small image sizes (~15-50MB)
- Fast builds with layer caching
- Security hardening (non-root, minimal dependencies)
- Production-ready images

---

## 🔐 Security Best Practices

### Image Security
- ✅ Non-root user execution
- ✅ Read-only root filesystems
- ✅ Minimal base images (Alpine)
- ✅ No secrets in images
- ✅ Trivy vulnerability scanning

### Registry Security
- ✅ Private ECR repositories
- ✅ IAM-based access control
- ✅ Image scanning on push
- ✅ Lifecycle policies for old images

### CI/CD Security
- ✅ GitHub Secrets for credentials
- ✅ OIDC authentication (recommended)
- ✅ Least-privilege IAM roles
- ✅ Secret rotation policies

---

## 📊 Build Metrics

**Average Build Times:**
- User Service: ~30-45 seconds
- Event Service: ~35-50 seconds
- Booking Service: ~40-55 seconds
- Search Service: ~30-45 seconds
- Frontend: ~60-90 seconds (npm build)
- Init Container: ~15-25 seconds

**Total Build Time (all services):** ~4-6 minutes

**Image Sizes:**
- Backend services: 15-25 MB each
- Frontend: 40-50 MB
- Init container: 10-15 MB

---

## 🛠️ Troubleshooting

### Build Failures

**"ECR_REGISTRY not set"**
```bash
# Configure AWS CLI
aws configure

# Or set explicitly
export ECR_REGISTRY="<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/bookmyevent"
```

**"denied: Your authorization token has expired"**
```bash
# Re-login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

**"no such file or directory: Dockerfile"**
```bash
# Run from project root, not from scripts directory
cd /path/to/eks-microservices-build
./scripts/build-local.sh all
```

### Push Failures

**"repository does not exist"**
```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name bookmyevent/user-service \
  --region us-east-1
```

**Platform mismatch errors**
```bash
# Rebuild for linux/amd64 platform
docker build --platform linux/amd64 \
  -f k8s/services/booking-service/Dockerfile \
  -t $ECR_REGISTRY/booking-service:latest .
```

---

## 📚 Related Documentation

- [CI/CD Pipeline Guide](../../docs/build/ci-cd-guide.md)
- [CI/CD Quick Start](../../docs/build/ci-cd-quickstart.md)
- [Pipeline Testing Guide](../../docs/build/ci-cd-testing-guide.md)
- [EKS Deployment Guide](../../docs/deployment/eks-deployment-guide.md)
- [Secrets Management](../../docs/secrets/secrets-manager-guide.md)

---

## 💡 Tips

**Speed up builds:**
```bash
# Use Docker BuildKit
export DOCKER_BUILDKIT=1

# Enable buildx for cache
docker buildx create --use
docker buildx build --cache-from=type=local,src=/tmp/cache ...
```

**Build specific Go service only:**
```bash
cd cmd/booking-service
go build -o ../../booking-service .
```

**Verify image before pushing:**
```bash
docker run --rm $ECR_REGISTRY/booking-service:latest --version
docker inspect $ECR_REGISTRY/booking-service:latest | jq '.[0].Config.User'
```

---

**Last Updated:** December 2025  
**Maintained By:** ENPM818R Group 5
