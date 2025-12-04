# CI/CD Pipeline Testing Guide

This guide shows you how to test and verify that your CI/CD pipeline is working correctly.

## 🧪 Testing Strategy

We'll test in 3 phases:
1. **Local Testing** - Verify scripts work locally
2. **PR Testing** - Test PR validation workflow
3. **Deployment Testing** - Test full CI/CD pipeline

---

## Phase 1: Local Testing (5 minutes)

### Test 1: Verify GitHub Actions Setup Script

```bash
# Dry run to check if script is working
./scripts/github-actions/setup-github-actions.sh

# This will:
# ✅ Create IAM user (or show it exists)
# ✅ Create access keys
# ✅ Attach policies
# ✅ Update EKS aws-auth
# ✅ Display GitHub secrets

# Expected output:
# - Green checkmarks for each step
# - Table with 3 GitHub secrets
# - Credentials saved to github-actions-credentials.txt
```

**What to verify:**
- [ ] Script completes without errors
- [ ] File `github-actions-credentials.txt` is created
- [ ] Contains `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ACCOUNT_ID`

### Test 2: Verify IAM User Was Created

```bash
# Check if IAM user exists
aws iam get-user --user-name github-actions-bookmyevent

# Expected output:
# {
#     "User": {
#         "UserName": "github-actions-bookmyevent",
#         "UserId": "...",
#         "Arn": "arn:aws:iam::ACCOUNT_ID:user/github-actions-bookmyevent",
#         "CreateDate": "..."
#     }
# }
```

### Test 3: Verify IAM Policies Are Attached

```bash
# Check attached policies
aws iam list-attached-user-policies --user-name github-actions-bookmyevent

# Expected output should include:
# - AmazonEC2ContainerRegistryPowerUser

# Check inline policies
aws iam list-user-policies --user-name github-actions-bookmyevent

# Expected output should include:
# - EKSAccess
```

### Test 4: Verify EKS Access

```bash
# Check if user is in aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml | grep github-actions-bookmyevent

# Expected output:
# userarn: arn:aws:iam::ACCOUNT_ID:user/github-actions-bookmyevent
# username: github-actions-bookmyevent
```

### Test 5: Test AWS Credentials Locally

```bash
# Test ECR access with the new credentials
export AWS_ACCESS_KEY_ID=$(grep AWS_ACCESS_KEY_ID github-actions-credentials.txt | cut -d= -f2)
export AWS_SECRET_ACCESS_KEY=$(grep AWS_SECRET_ACCESS_KEY github-actions-credentials.txt | cut -d= -f2)

# Try to login to ECR
aws ecr get-login-password --region us-east-1

# Expected: Should return a password (long base64 string)

# Try to list repositories
aws ecr describe-repositories --region us-east-1

# Expected: Should list your ECR repositories
```

### Test 6: Verify Workflow Files Exist

```bash
# Check if workflow files are present
ls -la .github/workflows/

# Expected output:
# ci-build-and-push.yml
# cd-deploy-to-eks.yml
# pr-validation.yml
```

### Test 7: Validate Workflow YAML Syntax

```bash
# Install yamllint (if not installed)
# macOS: brew install yamllint
# Linux: sudo apt-get install yamllint

# Validate workflow syntax
yamllint .github/workflows/ci-build-and-push.yml
yamllint .github/workflows/cd-deploy-to-eks.yml
yamllint .github/workflows/pr-validation.yml

# Expected: No errors (warnings are okay)
```

---

## Phase 2: GitHub Repository Setup (2 minutes)

### Step 1: Add GitHub Secrets

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these 3 secrets from `github-actions-credentials.txt`:

```bash
# Read from the credentials file
cat github-actions-credentials.txt

# Copy these values to GitHub:
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=...
# AWS_ACCOUNT_ID=123456789012
```

### Step 2: Verify Secrets Are Set

```bash
# You can't read secret values via API, but you can list them
# Using GitHub CLI (if installed):
gh secret list

# Expected output:
# AWS_ACCESS_KEY_ID      Updated YYYY-MM-DD
# AWS_SECRET_ACCESS_KEY  Updated YYYY-MM-DD
# AWS_ACCOUNT_ID         Updated YYYY-MM-DD
```

### Step 3: Clean Up Credentials File

```bash
# After adding to GitHub, delete the local credentials file
rm github-actions-credentials.txt

# Verify it's deleted
ls github-actions-credentials.txt
# Expected: No such file or directory
```

---

## Phase 3: Test PR Validation Workflow (10 minutes)

### Test 1: Create a Test Branch

```bash
# Create a test branch
git checkout -b test/ci-pipeline

# Make a small change
echo "# Testing CI/CD" >> test-file.md
git add test-file.md
git commit -m "test: trigger PR validation workflow"

# Push to GitHub
git push origin test/ci-pipeline
```

### Test 2: Create a Pull Request

1. Go to GitHub repository
2. Click **Pull requests** → **New pull request**
3. Base: `main` or `build` (your default branch)
4. Compare: `test/ci-pipeline`
5. Click **Create pull request**
6. Title: "Test: CI/CD Pipeline"
7. Click **Create pull request**

### Test 3: Watch PR Validation Run

1. In the PR, scroll down to **Checks**
2. You should see "PR Validation" workflow running
3. Click **Details** to see real-time logs

**Expected Checks:**
- ✅ Validate Pull Request (Go tests, linting)
- ✅ Lint Dockerfiles
- ✅ Validate Kubernetes Manifests
- ✅ Check for Secrets in Code
- ✅ PR Summary

### Test 4: Verify PR Comment

After workflow completes (~5 minutes):
- A bot should post a comment with validation results
- Should show status for each check (✅ or ❌)

### Test 5: Review Workflow Logs

```bash
# Or view locally using GitHub CLI
gh run list --workflow=pr-validation.yml
gh run view --log
```

**What to check in logs:**
- [ ] Go tests passed
- [ ] No formatting issues
- [ ] Dockerfiles are valid
- [ ] Kubernetes YAML is valid
- [ ] No secrets detected

---

## Phase 4: Test Full CI/CD Pipeline (20-30 minutes)

### Test 1: Merge PR to Trigger CI/CD

```bash
# Option 1: Merge via GitHub UI
# - Click "Merge pull request" on the PR
# - Click "Confirm merge"

# Option 2: Merge via command line
git checkout main
git merge test/ci-pipeline
git push origin main
```

### Test 2: Watch CI Workflow (Build & Push)

1. Go to **Actions** tab
2. Click on "CI - Build and Push Images" workflow
3. You should see a new run starting

**Expected Jobs:**
- Build Backend Services (user, event, search, booking)
- Build Frontend
- Build Init Container

**Timeline:**
- Backend builds: ~8-10 minutes (parallel)
- Frontend build: ~5-7 minutes
- Total: ~10-12 minutes

### Test 3: Monitor Build Progress

Click on a job to see real-time logs:

```yaml
Expected Steps:
✅ Checkout code
✅ Set up Docker Buildx
✅ Configure AWS credentials
✅ Login to Amazon ECR
✅ Extract metadata for Docker
✅ Build Docker image
✅ Run Trivy vulnerability scanner
✅ Upload Trivy results to GitHub Security
✅ Push Docker image to ECR
✅ Image digest
```

### Test 4: Verify Images in ECR

```bash
# While CI is running, check ECR
aws ecr describe-images \
  --repository-name bookmyevent/user-service \
  --region us-east-1

# Expected: Should see new image with tags:
# - latest
# - main
# - main-{commit-sha}
```

### Test 5: Check Security Scan Results

1. Go to **Security** tab in GitHub
2. Click **Code scanning**
3. You should see Trivy scan results
4. Click on any finding to see details

**Expected:**
- Scan results for each service
- Severity levels (Critical, High, Medium, Low)
- Remediation suggestions

### Test 6: Watch CD Workflow (Deploy to EKS)

After CI completes successfully:
- CD workflow should auto-trigger
- Go to **Actions** tab
- Click "CD - Deploy to EKS"

**Expected Steps:**
```yaml
✅ Checkout code
✅ Configure AWS credentials
✅ Update kubeconfig for EKS
✅ Verify cluster access
✅ Deploy namespace and config
✅ Deploy infrastructure services
✅ Wait for PostgreSQL
✅ Wait for Redis
✅ Wait for Elasticsearch
✅ Run database migrations
✅ Deploy microservices
✅ Wait for microservices
✅ Deploy API Gateway
✅ Deploy frontend
✅ Deploy init container
✅ Verify deployment health
✅ Run smoke tests
✅ Create GitHub deployment
✅ Post deployment summary
```

**Timeline:** ~5-10 minutes

### Test 7: Verify Deployment in EKS

```bash
# Check if all pods are running
kubectl get pods -n bookmyevent

# Expected: All pods should be Running
# NAME                                READY   STATUS    RESTARTS
# booking-service-xxx                 1/1     Running   0
# elasticsearch-xxx                   1/1     Running   0
# event-service-xxx                   1/1     Running   0
# frontend-xxx                        1/1     Running   0
# nginx-gateway-xxx                   1/1     Running   0
# postgres-xxx                        1/1     Running   0
# redis-xxx                           1/1     Running   0
# search-service-xxx                  1/1     Running   0
# user-service-xxx                    1/1     Running   0

# Check services
kubectl get svc -n bookmyevent

# Check deployments
kubectl get deployments -n bookmyevent
```

### Test 8: Get Application URLs

```bash
# Get frontend URL
kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get API Gateway URL
kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Or check in workflow output - it's in the deployment summary
```

### Test 9: Test Application Endpoints

```bash
# Get API URL from workflow or kubectl
export API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test health endpoint
curl http://$API_URL/health

# Expected: "healthy"

# Test events API
curl http://$API_URL/api/event/events

# Expected: JSON array of events (might be empty initially)

# Test with pretty print
curl http://$API_URL/api/event/events | jq .
```

### Test 10: Verify Frontend

```bash
# Get frontend URL
export FRONTEND_URL=$(kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Open in browser
echo "Frontend: http://$FRONTEND_URL"

# Or test with curl
curl -I http://$FRONTEND_URL

# Expected: HTTP 200 OK
```

---

## Phase 5: Test Manual Deployment Trigger (5 minutes)

### Test Manual Workflow Dispatch

1. Go to **Actions** tab
2. Click "CD - Deploy to EKS" in the left sidebar
3. Click **Run workflow** button
4. Select environment: `production`
5. Click **Run workflow**

**Expected:**
- Workflow starts immediately
- Deploys to EKS cluster
- Posts deployment summary

---

## Phase 6: Test Rollback (Optional)

### Simulate a Failed Deployment

```bash
# Make a breaking change
echo "INVALID YAML" >> k8s/services/user-service/user-service.yaml
git add .
git commit -m "test: intentional break to test rollback"
git push origin main
```

**Expected:**
- CI workflow succeeds (builds images)
- CD workflow fails at deployment step
- No changes applied to cluster (automatic rollback)

### Verify Rollback

```bash
# Check that previous version is still running
kubectl get deployments -n bookmyevent
kubectl describe deployment user-service -n bookmyevent

# Should show previous image version
```

### Fix and Redeploy

```bash
# Revert the breaking change
git revert HEAD
git push origin main

# CI/CD should run again and deploy successfully
```

---

## 📊 Verification Checklist

### ✅ Local Setup
- [ ] IAM user created
- [ ] Access keys generated
- [ ] Policies attached
- [ ] EKS aws-auth updated
- [ ] GitHub secrets configured

### ✅ PR Validation
- [ ] Workflow triggers on PR
- [ ] Go tests pass
- [ ] Dockerfiles validated
- [ ] Kubernetes YAML validated
- [ ] No secrets detected
- [ ] Bot posts PR comment

### ✅ CI Pipeline
- [ ] Workflow triggers on push to main
- [ ] All services build successfully
- [ ] Images pushed to ECR
- [ ] Security scans complete
- [ ] Results in GitHub Security tab

### ✅ CD Pipeline
- [ ] Auto-triggers after successful CI
- [ ] Connects to EKS cluster
- [ ] Infrastructure deployed
- [ ] Migrations run successfully
- [ ] All microservices deployed
- [ ] Health checks pass
- [ ] Smoke tests pass

### ✅ Application
- [ ] All pods running
- [ ] LoadBalancers have external IPs
- [ ] API Gateway responds
- [ ] Frontend loads
- [ ] Test login works

---

## 🔍 Troubleshooting Common Issues

### Issue 1: "Error: No AWS credentials found"

**Problem:** GitHub workflow can't access AWS

**Solution:**
```bash
# Verify secrets are set in GitHub
# Settings → Secrets and variables → Actions

# Should have:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_ACCOUNT_ID
```

### Issue 2: "Error: Unauthorized to perform: ecr:GetAuthorizationToken"

**Problem:** IAM user doesn't have ECR permissions

**Solution:**
```bash
# Re-attach ECR policy
aws iam attach-user-policy \
  --user-name github-actions-bookmyevent \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

### Issue 3: "Error: You must be logged in to the server (Unauthorized)"

**Problem:** GitHub Actions can't access EKS cluster

**Solution:**
```bash
# Re-run the EKS access script
./scripts/k8s/add-github-actions-to-eks.sh
```

### Issue 4: Workflow stuck at "Waiting for PostgreSQL"

**Problem:** Infrastructure not ready

**Solution:**
```bash
# Check pod status
kubectl get pods -n bookmyevent

# Check PVC status
kubectl get pvc -n bookmyevent

# If PVC stuck, verify EBS CSI driver
kubectl get pods -n kube-system | grep ebs
```

### Issue 5: "ImagePullBackOff" errors

**Problem:** Can't pull images from ECR

**Solution:**
```bash
# Verify images exist in ECR
aws ecr list-images \
  --repository-name bookmyevent/user-service \
  --region us-east-1

# Verify node role has ECR access
# Check eksctl created the correct permissions
```

---

## 📈 Success Metrics

After testing, you should see:

✅ **GitHub Actions:**
- All workflows show green checkmarks
- No failed runs
- Security scans complete without critical issues

✅ **EKS Cluster:**
- All pods in Running state
- No CrashLoopBackOff errors
- LoadBalancers have external IPs

✅ **Application:**
- API responds to health checks
- Frontend loads in browser
- Can log in with test credentials

✅ **Monitoring:**
- GitHub deployment shows "Active"
- Workflow runs tracked in Actions tab
- Security findings tracked in Security tab

---

## 🎯 Next Steps After Successful Testing

1. **Enable Branch Protection:**
   ```bash
   # GitHub → Settings → Branches → Add rule
   # Branch name pattern: main
   # ✓ Require pull request reviews before merging
   # ✓ Require status checks to pass before merging
   ```

2. **Set Up Notifications:**
   - Configure GitHub notifications for workflow failures
   - Set up Slack webhooks (optional)

3. **Document Your Pipeline:**
   - Update README.md with deployment status badge
   - Document any custom modifications

4. **Plan Monitoring:**
   - Ready to add Prometheus + Grafana next

---

## 🆘 Getting Help

If you encounter issues during testing:

1. **Check workflow logs** in GitHub Actions
2. **Review step-by-step output** in each job
3. **Verify prerequisites** (IAM, EKS, secrets)
4. **Check pod logs:** `kubectl logs deployment/SERVICE -n bookmyevent`
5. **Review this guide's troubleshooting section**

---

**Ready to test?** Start with Phase 1 and work your way through! 🚀
