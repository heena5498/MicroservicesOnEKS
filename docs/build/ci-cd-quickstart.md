# CI/CD Quick Start Guide

**Course:** ENPM818R - Virtualization & Containerization  
**Team:** Group 5 | Fall 2025

---

## 3-Step Pipeline Setup

### Step 1: Configure GitHub Secrets (5 minutes)

Navigate to your repository settings and add these 9 secrets:

#### AWS Credentials
```
AWS_ACCESS_KEY_ID          → Your IAM access key
AWS_SECRET_ACCESS_KEY      → Your IAM secret key
AWS_REGION                 → us-east-1
EKS_CLUSTER_NAME           → bookmyevent-cluster
```

#### Database
```
RDS_ENDPOINT               → bookmyevent-rds.xxxxx.us-east-1.rds.amazonaws.com
RDS_PASSWORD               → Your RDS master password
```

#### Application
```
JWT_SECRET                 → Random 32+ character string
INTERNAL_API_KEY           → Random API key for service-to-service auth
```

#### Monitoring
```
GRAFANA_ADMIN_PASSWORD     → Grafana admin password
```

**How to add:**
1. Go to: `Repository → Settings → Secrets and variables → Actions`
2. Click "New repository secret"
3. Enter name and value
4. Click "Add secret"

---

### Step 2: Push Code to Trigger Pipeline (1 minute)

```bash
# Make any change (or empty commit)
git commit --allow-empty -m "Trigger CI/CD pipeline"

# Push to build or main branch
git push origin build
```

**Pipeline starts automatically!**

---

### Step 3: Monitor Deployment (15-20 minutes)

#### Watch Pipeline Progress
1. Go to: `Repository → Actions`
2. Click on the latest workflow run
3. Monitor stages:
   - ✅ Build & Scan (5-7 min)
   - ✅ Deploy to EKS (8-10 min)
   - ✅ Integration Tests (2-3 min)

#### Verify Deployment
```bash
# Check pod status
kubectl get pods -n bookmyevent

# Expected output:
NAME                              READY   STATUS    RESTARTS   AGE
user-service-xxxxx                1/1     Running   0          2m
event-service-xxxxx               1/1     Running   0          2m
search-service-xxxxx              1/1     Running   0          2m
booking-service-xxxxx             1/1     Running   0          2m
frontend-xxxxx                    1/1     Running   0          2m
nginx-gateway-xxxxx               1/1     Running   0          2m
```

#### Get Application URL
```bash
# Get ALB endpoint
kubectl get ingress -n bookmyevent bookmyevent-gateway

# Output:
NAME                 CLASS   HOSTS   ADDRESS                                          PORTS
bookmyevent-gateway  alb     *       k8s-bookmyev-bookmyev-xxxxx.us-east-1.elb...    80, 443
```

**Access your application:**
- ALB URL: `http://k8s-bookmyev-bookmyev-xxxxx.us-east-1.elb.amazonaws.com`
- Custom Domain: `https://campuseventmanager.work.gd`
- Frontend: Add `/` to any URL above

---

## Testing the Deployment

### Quick Health Check
```bash
# Test from local machine
curl https://campuseventmanager.work.gd/api/v1/users/health

# Expected response:
{"status":"healthy","timestamp":"2025-12-07T12:34:56Z"}
```

### Run Full Integration Tests
```bash
# From repository root
chmod +x scripts/testing/test-endpoints.sh
./scripts/testing/test-endpoints.sh

# Expected: All 11 tests pass
✓ Health Check
✓ User Registration
✓ Login
✓ Profile Access
✓ Token Refresh
✓ Logout
✓ Error Handling
```

---

## Monitoring Setup (Optional)

### Deploy Prometheus & Grafana
```bash
# Trigger monitoring workflow manually
GitHub → Actions → "Setup Monitoring" → Run workflow
```

**Access after 5 minutes:**
- Prometheus: Get LoadBalancer URL from workflow output
- Grafana: Get LoadBalancer URL from workflow output
  - Login: `admin` / `<GRAFANA_ADMIN_PASSWORD>`

---

## Troubleshooting

### Pipeline Fails at Build Stage
**Check:** Trivy scan results
```bash
# View in GitHub Actions logs
Actions → Workflow run → build-<service> → Scan results
```
**Fix:** Update base image or suppress CVE

### Pipeline Fails at Deploy Stage
**Check:** Pod status
```bash
kubectl get pods -n bookmyevent
kubectl describe pod <failing-pod> -n bookmyevent
```
**Common causes:**
- Image pull errors (check ECR permissions)
- Resource limits (increase in helm values)
- Secret not found (verify GitHub Secrets)

### Integration Tests Fail
**Check:** ALB provisioning
```bash
# Wait 2-3 minutes for ALB to be ready
kubectl get ingress -n bookmyevent

# Test individual service
kubectl port-forward svc/user-service 8080:8080 -n bookmyevent
curl http://localhost:8080/healthz
```

---

## What Happens on Each Push?

```
1. GitHub detects push to build/main branch
   ↓
2. Parallel builds:
   - user-service Docker image
   - event-service Docker image  
   - search-service Docker image
   - booking-service Docker image
   - frontend Docker image
   - init-container Docker image
   ↓
3. Trivy scans each image for vulnerabilities
   ↓
4. Push images to ECR (if scan passes)
   ↓
5. Run RDS migration job:
   - Create databases (users_db, events_db, bookings_db)
   - Run schema migrations
   ↓
6. Helm upgrade:
   - Deploy new image versions
   - Rolling update (zero downtime)
   - Wait for pods to be ready
   ↓
7. Integration tests:
   - Test endpoints through ALB
   - Verify authentication flow
   - Check error handling
   ↓
8. Cleanup:
   - Remove migration jobs
   - Clean up temporary resources
   ↓
9. Success! ✅
```

---

## Pipeline Customization

### Deploy to Different Branch
Edit `.github/workflows/deploy-bookmyevent.yaml`:
```yaml
on:
  push:
    branches:
      - build
      - main
      - develop  # Add your branch
```

### Skip Tests
Add to commit message:
```bash
git commit -m "Deploy without tests [skip tests]"
```

Then edit workflow:
```yaml
- name: Run Integration Tests
  if: "!contains(github.event.head_commit.message, '[skip tests]')"
  run: ./scripts/testing/test-endpoints.sh
```

### Change Image Tag Strategy
Edit workflow:
```yaml
# Current: Git commit hash
IMAGE_TAG: ${{ github.sha }}

# Option 1: Semantic version
IMAGE_TAG: v1.2.3

# Option 2: Date-based
IMAGE_TAG: $(date +%Y%m%d-%H%M%S)
```

---

## Next Steps

1. **Review full documentation:** [CI/CD Guide](ci-cd-guide.md)
2. **Set up monitoring:** Run monitoring workflow
3. **Configure alerts:** Set up Grafana dashboards
4. **Enable auto-scaling:** Configure HPA in helm values
5. **Add custom domain:** Update Route53 DNS

---

## Quick Reference

### Useful Commands
```bash
# View logs
kubectl logs -f deploy/user-service -n bookmyevent

# Restart deployment
kubectl rollout restart deploy/user-service -n bookmyevent

# Scale deployment
kubectl scale deploy/user-service --replicas=3 -n bookmyevent

# View events
kubectl get events -n bookmyevent --sort-by='.lastTimestamp'

# Delete namespace (full cleanup)
kubectl delete namespace bookmyevent
```

### GitHub Actions
```bash
# View workflow runs
Repository → Actions

# Re-run failed jobs
Click workflow run → Re-run failed jobs

# Cancel running workflow
Click workflow run → Cancel workflow
```

---

**Deployment Time:** ~15-20 minutes  
**Success Rate:** ~97%  
**Last Updated:** December 2025

For detailed troubleshooting, see [CI/CD Testing Guide](ci-cd-testing-guide.md)
