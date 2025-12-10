# 🧪 CI/CD Testing - Quick Start

## ⚡ Fastest Way to Test (1 Command)

```bash
# Run automated test suite
./scripts/testing/test-cicd-pipeline.sh
```

This script automatically tests:
- IAM user and permissions
- GitHub workflow files
- EKS cluster access
- ECR repositories
- Current deployments
- LoadBalancer status

**Expected output:**
```
============================================================
  Test Summary
============================================================

Total Tests: 20
Passed: 20
Failed: 0

🎉 All tests passed!
```

---

## 🎯 3-Phase Testing (Step-by-Step)

### Phase 1: Setup & Local Tests (5 min)

```bash
# 1. Run setup script
./scripts/github-actions/setup-github-actions.sh

# 2. Add GitHub secrets from the output
# Go to: GitHub → Settings → Secrets → Add:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY  
# - AWS_ACCOUNT_ID

# 3. Run automated tests
./scripts/testing/test-cicd-pipeline.sh

# 4. Clean up credentials file
rm github-actions-credentials.txt
```

---

### Phase 2: Test PR Validation (10 min)

```bash
# Create test branch
git checkout -b test/cicd-validation
echo "# CI/CD Test" >> TEST.md
git add TEST.md
git commit -m "test: trigger PR workflow"
git push origin test/cicd-validation

# Then on GitHub:
# 1. Create Pull Request
# 2. Watch "PR Validation" workflow run
# 3. Verify bot posts comment with results
# 4. Check all checks pass ✅
```

**What to verify:**
- [ ] Workflow runs automatically
- [ ] Go tests pass
- [ ] Dockerfile linting passes
- [ ] Kubernetes validation passes
- [ ] Bot comment appears on PR

---

### Phase 3: Test Full Deployment (30 min)

```bash
# Merge PR to trigger full CI/CD
git checkout main
git merge test/cicd-validation
git push origin main

# Watch in GitHub Actions:
# 1. "CI - Build and Push Images" runs (~10 min)
# 2. "CD - Deploy to EKS" runs automatically (~10 min)
```

**Monitor progress:**
```bash
# Watch pods deploy
kubectl get pods -n bookmyevent -w

# Check when ready
kubectl get deployments -n bookmyevent

# Get URLs
kubectl get svc -n bookmyevent
```

**Test endpoints:**
```bash
# Get API URL
export API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test health
curl http://$API_URL/health

# Test API
curl http://$API_URL/api/event/events
```

---

## Quick Verification Checklist

### Before Testing:
- [ ] EKS cluster is running
- [ ] kubectl configured and working
- [ ] AWS CLI configured
- [ ] GitHub repo accessible

### After Setup:
- [ ] IAM user created
- [ ] GitHub secrets added
- [ ] Automated tests pass
- [ ] Credentials file deleted

### After PR Test:
- [ ] PR workflow runs
- [ ] All checks pass
- [ ] Bot comments on PR
- [ ] No errors in logs

### After Full Deployment:
- [ ] CI workflow completes (~10 min)
- [ ] CD workflow completes (~10 min)
- [ ] All pods running
- [ ] LoadBalancers have IPs
- [ ] Health endpoint responds
- [ ] Frontend loads

---

## 🔍 Quick Health Checks

```bash
# Check if everything is running
kubectl get all -n bookmyevent

# Check for errors
kubectl get events -n bookmyevent --sort-by='.lastTimestamp'

# Check specific service logs
kubectl logs deployment/user-service -n bookmyevent --tail=50

# Check if APIs respond
API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$API_URL/health
curl http://$API_URL/api/event/events
```

---

## 🚨 Common Issues & Quick Fixes

### "No GitHub secrets configured"
```bash
# Add them manually in GitHub:
# Settings → Secrets and variables → Actions → New repository secret
```

### "kubectl: command not found"
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name bookmyevent-cluster
```

### "ImagePullBackOff"
```bash
# Check if images exist in ECR
aws ecr list-images --repository-name bookmyevent/user-service --region us-east-1

# Verify ECR permissions
aws ecr get-login-password --region us-east-1
```

### "Error: Unauthorized" in GitHub Actions
```bash
# Re-add GitHub Actions user to EKS
./scripts/k8s/add-github-actions-to-eks.sh
```

### LoadBalancer stuck in "Pending"
```bash
# Wait 2-3 minutes for AWS to provision
# Check events
kubectl describe svc nginx-gateway -n bookmyevent
```

---

## 📊 Expected Timings

| Phase | Duration | What Happens |
|-------|----------|--------------|
| Setup | 5 min | Create IAM, add secrets |
| PR Test | 5-10 min | Validation runs |
| CI (Build) | 8-12 min | Build all images |
| CD (Deploy) | 5-10 min | Deploy to EKS |
| **Total** | **25-35 min** | **End-to-end** |

---

## 🎯 Success Indicators

### In GitHub Actions:
- All workflows show green checkmarks
- Security scans complete
- Deployment summary posted

### In EKS:
```bash
kubectl get pods -n bookmyevent
# All pods: Running (1/1 or 2/2)
```

### In Browser:
- Frontend URL loads
- Can navigate the app
- Can log in with test credentials

---

## 🚀 What to Test Next

After basic testing works:

1. **Test automatic deployment**
   ```bash
   # Make any code change
   git add .
   git commit -m "test: auto deploy"
   git push origin main
   # Watch CI/CD run automatically
   ```

2. **Test rollback**
   ```bash
   # Deploy previous version
   kubectl rollout undo deployment/user-service -n bookmyevent
   ```

3. **Test manual deployment**
   ```bash
   # GitHub → Actions → "CD - Deploy to EKS" → Run workflow
   ```

4. **Test security scans**
   ```bash
   # GitHub → Security → Code scanning
   # Review Trivy results
   ```

---

## 📚 Full Documentation

For detailed testing procedures, see:
- **Complete Guide:** `CI_CD_TESTING_GUIDE.md`
- **Setup Guide:** `CI_CD_QUICKSTART.md`
- **Full Documentation:** `../../docs/build/ci-cd-guide.md`

---

## 🆘 Need Help?

```bash
# Run automated tests to diagnose
./scripts/testing/test-cicd-pipeline.sh

# Check logs
kubectl logs deployment/SERVICE -n bookmyevent

# Check GitHub Actions logs
# GitHub → Actions → Click workflow → Click job → Expand steps

# Review testing guide
cat CI_CD_TESTING_GUIDE.md
```

---

**Ready?** Start with: `./scripts/testing/test-cicd-pipeline.sh` 🚀
