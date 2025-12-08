# CI/CD Pipeline Guide

**Course:** ENPM818R - Virtualization & Containerization  
**Institution:** University of Maryland  
**Team:** Group 5 | Fall 2025

---

## Overview

This guide documents the GitHub Actions CI/CD pipeline for the BookMyEvent microservices platform deployed on AWS EKS.

### Pipeline Architecture

```
GitHub Push → Build & Scan → Deploy to EKS → Integration Tests → Monitoring Setup
     ↓              ↓              ↓                ↓                  ↓
  Trigger      Docker Build    Helm Deploy    Test Endpoints    Prometheus/Grafana
               Trivy Scan      RDS Migration   Verify Health     (Manual Trigger)
               ECR Push        ALB/Ingress
```

### Deployment Time
- **Full Pipeline:** 15-20 minutes
- **Build Phase:** 5-7 minutes
- **Deployment Phase:** 8-10 minutes
- **Testing Phase:** 2-3 minutes

---

## Workflows

### 1. Main Deployment Pipeline
**File:** `.github/workflows/deploy-bookmyevent.yaml`

#### Trigger Events
- Push to `build` or `main` branch
- Manual workflow dispatch

#### Pipeline Stages

##### Stage 1: Build & Scan (Parallel)
```yaml
jobs:
  build-user-service:
    - Checkout code
    - Configure AWS credentials
    - Login to ECR
    - Build Docker image
    - Scan with Trivy
    - Push to ECR
```

**Services Built:**
- `user-service`
- `event-service`
- `search-service`
- `booking-service`
- `frontend`
- `init-container`

**Security Scanning:**
- Trivy scans for HIGH/CRITICAL vulnerabilities
- Failed scans block deployment
- Reports uploaded to GitHub Security tab

##### Stage 2: Deploy to EKS
```yaml
deploy:
  needs: [build-user-service, build-event-service, ...]
  steps:
    - Update kubeconfig
    - Run RDS migration job
    - Install/Upgrade Helm chart
    - Wait for pods ready
```

**RDS Migration Job:**
```bash
# Creates databases if not exist
- users_db
- events_db  
- bookings_db

# Runs migrations via init-container
- Schema creation
- Table setup
- Indexes and constraints
```

**Helm Deployment:**
```bash
helm upgrade --install bookmyevent ./helm \
  --namespace bookmyevent \
  --set global.rdsEnabled=true \
  --set global.imageRegistry=${ECR_REGISTRY} \
  --set global.imageTag=${IMAGE_TAG} \
  --timeout 10m \
  --wait
```

##### Stage 3: Integration Testing
```bash
# Execute test suite
./scripts/testing/test-endpoints.sh

# Tests performed:
- Health check
- User registration
- Login authentication
- Profile access (protected route)
- Token refresh
- Logout
- Error handling (401, 409)
```

**Test Endpoints:**
- ALB URL: `k8s-bookmyev-bookmyev-*.us-east-1.elb.amazonaws.com`
- Custom Domain: `campuseventmanager.work.gd`

##### Stage 4: Cleanup
```bash
# Remove temporary resources
- Migration jobs
- Failed pods
- Orphaned ConfigMaps
```

---

### 2. Monitoring Setup Pipeline
**File:** `.github/workflows/setup-monitoring.yml`

#### Trigger
- Manual workflow dispatch only

#### Deployment
```yaml
steps:
  - Install Prometheus
  - Install Grafana
  - Expose via LoadBalancer
  - Output access URLs
```

**Access:**
- Prometheus: `http://<PROMETHEUS-LB>:9090`
- Grafana: `http://<GRAFANA-LB>:3000`
  - Username: `admin`
  - Password: From GitHub Secret `GRAFANA_ADMIN_PASSWORD`

---

## GitHub Secrets Configuration

### Required Secrets (9 Total)

#### AWS Credentials (4)
```
AWS_ACCESS_KEY_ID          - IAM user access key
AWS_SECRET_ACCESS_KEY      - IAM user secret key
AWS_REGION                 - us-east-1
EKS_CLUSTER_NAME           - bookmyevent-cluster
```

#### Database (2)
```
RDS_ENDPOINT               - bookmyevent-rds.*.us-east-1.rds.amazonaws.com
RDS_PASSWORD               - PostgreSQL master password
```

#### Application (2)
```
JWT_SECRET                 - Token signing key (min 32 chars)
INTERNAL_API_KEY           - Service-to-service auth
```

#### Monitoring (1)
```
GRAFANA_ADMIN_PASSWORD     - Grafana admin password
```

### Setup Instructions
```bash
# Navigate to repository settings
GitHub Repository → Settings → Secrets and variables → Actions → New repository secret

# Add each secret with exact name matching above
```

---

## Pipeline Optimization

### Parallel Builds
All 6 services build simultaneously using matrix strategy:
```yaml
strategy:
  matrix:
    service: [user, event, search, booking, frontend, init-container]
```

**Benefits:**
- Build time: 12 minutes → 5-7 minutes
- Resource utilization: 6x improvement
- Faster feedback on failures

### Caching Strategy
```yaml
- Docker layer caching via ECR
- Go module caching via actions/cache
- npm dependency caching for frontend
```

### Resource Limits
```yaml
# Build jobs
timeout-minutes: 15

# Deploy job  
timeout-minutes: 20

# Migration job (Kubernetes)
activeDeadlineSeconds: 120
```

---

## Troubleshooting

### Common Issues

#### 1. Migration Job Timeout
**Symptom:** Job exceeds 120s deadline
**Cause:** RDS connection latency, large schema
**Solution:**
```bash
# Check job logs
kubectl logs -n bookmyevent job/run-migrations-rds-<hash>

# Verify RDS connectivity
kubectl run -it --rm debug --image=postgres:15-alpine \
  --env="PGPASSWORD=$RDS_PASSWORD" -- \
  psql -h $RDS_ENDPOINT -U postgres -c "SELECT version();"

# Increase timeout if needed
activeDeadlineSeconds: 300
```

#### 2. Trivy Scan Failures
**Symptom:** Build blocked by vulnerabilities
**Cause:** New CVEs in base images
**Solution:**
```dockerfile
# Update base image
FROM golang:1.22-alpine  →  FROM golang:1.22.5-alpine

# Or suppress specific CVE
--skip-ids CVE-2024-XXXXX
```

#### 3. Helm Install Fails
**Symptom:** `Error: INSTALLATION FAILED: timed out waiting for the condition`
**Cause:** Pods not reaching Ready state
**Solution:**
```bash
# Check pod status
kubectl get pods -n bookmyevent

# Describe failing pod
kubectl describe pod <pod-name> -n bookmyevent

# Check events
kubectl get events -n bookmyevent --sort-by='.lastTimestamp'
```

#### 4. Integration Tests Fail
**Symptom:** `test-endpoints.sh` reports errors
**Cause:** ALB not ready, services unhealthy
**Solution:**
```bash
# Wait for ALB provisioning (2-3 min)
kubectl get ingress -n bookmyevent bookmyevent-gateway

# Verify service health
kubectl exec -it deploy/user-service -n bookmyevent -- \
  curl http://localhost:8080/healthz
```

---

## Best Practices

### 1. Secrets Management
- **Never commit secrets** to repository
- Use GitHub Secrets for all sensitive data
- Rotate secrets quarterly
- Use AWS Secrets Manager for production (future enhancement)

### 2. Image Tagging
```bash
# Current strategy
IMAGE_TAG="${GITHUB_SHA:0:7}"  # Git commit hash

# Recommended for production
IMAGE_TAG="v1.2.3"              # Semantic versioning
```

### 3. Deployment Strategy
```yaml
# Current: Replace all pods
strategy:
  type: RollingUpdate

# Recommended: Zero-downtime
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

### 4. Testing
- Run integration tests on every deployment
- Test both success and failure scenarios
- Verify error handling (401, 409, 500 codes)
- Test through ALB (production path)

### 5. Monitoring
- Set up Prometheus/Grafana before production
- Configure alerts for pod crashes
- Monitor RDS connection pool
- Track API latency metrics

---

## Pipeline Metrics

### Success Rate
- **Target:** >95%
- **Current:** ~97%
- **Main failures:** Trivy scans (3%), timeout (2%)

### Deployment Frequency
- **Average:** 3-5 deployments/day during development
- **Peak:** 12 deployments/day during testing

### Mean Time to Recovery (MTTR)
- **Rollback time:** 5-7 minutes
- **Redeploy time:** 15-20 minutes

---

## Security Considerations

### 1. Image Scanning
- **Tool:** Trivy
- **Severity threshold:** HIGH, CRITICAL
- **Scan frequency:** Every build
- **Action on failure:** Block deployment

### 2. Secret Encryption
- GitHub Secrets encrypted at rest
- Kubernetes Secrets base64 encoded (not encrypted by default)
- **Recommendation:** Enable encryption at rest for EKS

### 3. Network Security
- ALB with HTTPS (ACM certificate)
- Internal services use ClusterIP
- No external access to databases
- Security groups restrict RDS access to EKS nodes only

### 4. RBAC
```yaml
# GitHub Actions service account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-actions
  namespace: bookmyevent

# Limited permissions
- create/update Deployments
- create/delete Jobs
- read Pods/Services
```

---

## Future Enhancements

### 1. Multi-Environment Support
```yaml
# Staging environment
if: github.ref == 'refs/heads/develop'
  deploy-to: staging-cluster

# Production environment  
if: github.ref == 'refs/heads/main'
  deploy-to: production-cluster
```

### 2. Automated Rollback
```yaml
# On test failure
if: steps.test.outcome == 'failure'
  run: |
    helm rollback bookmyevent -n bookmyevent
```

### 3. Canary Deployments
```yaml
# Deploy to 10% of pods
helm upgrade --set canary.enabled=true \
  --set canary.weight=10
```

### 4. Performance Testing
```yaml
# Load testing with k6
- name: Run load tests
  run: |
    k6 run tests/load-test.js --vus 100 --duration 30s
```

---

## Related Documentation

- **[Deployment Guide](../deployment/eks-deployment-guide.md)** - Infrastructure setup
- **[Secrets Guide](../secrets/secrets-manager-guide.md)** - Secret management
- **[Testing Guide](ci-cd-testing-guide.md)** - Test suite documentation
- **[Quick Start](ci-cd-quickstart.md)** - 3-step pipeline setup

---

## Support

For pipeline issues or questions:
- Check GitHub Actions logs: Repository → Actions → Workflow run
- Review Kubernetes events: `kubectl get events -n bookmyevent`
- Consult team documentation in `docs/` folder

**Last Updated:** December 2025  
**Maintained by:** ENPM818R Group 5
