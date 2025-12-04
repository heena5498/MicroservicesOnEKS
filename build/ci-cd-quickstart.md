# 🚀 CI/CD Quick Setup Guide

## ⚡ Quick Start (3 Steps)

### Step 1: Create IAM User for GitHub Actions

```bash
# Create IAM user
aws iam create-user --user-name github-actions-bookmyevent

# Create access keys
aws iam create-access-key --user-name github-actions-bookmyevent

# SAVE THE OUTPUT - You'll need:
# - AccessKeyId (for AWS_ACCESS_KEY_ID secret)
# - SecretAccessKey (for AWS_SECRET_ACCESS_KEY secret)
```

### Step 2: Attach Required Policies

```bash
# Get your AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Attach ECR permissions
aws iam attach-user-policy \
  --user-name github-actions-bookmyevent \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# Create and attach EKS access policy
cat > /tmp/eks-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:AccessKubernetesApi"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name github-actions-bookmyevent \
  --policy-name EKSAccess \
  --policy-document file:///tmp/eks-policy.json
```

### Step 3: Configure GitHub Secrets

1. Go to your GitHub repository
2. **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these 3 secrets:

| Name | Value | How to Get |
|------|-------|------------|
| `AWS_ACCESS_KEY_ID` | From Step 1 output | The `AccessKeyId` value |
| `AWS_SECRET_ACCESS_KEY` | From Step 1 output | The `SecretAccessKey` value |
| `AWS_ACCOUNT_ID` | Your AWS account number | Run: `aws sts get-caller-identity --query Account --output text` |

---

## ✅ Verify Setup

### Test GitHub Actions Can Access AWS

Push a commit to trigger the workflow:

```bash
git add .
git commit -m "test: trigger CI/CD pipeline"
git push origin main
```

Then:
1. Go to GitHub → **Actions** tab
2. Watch the "CI - Build and Push Images" workflow
3. Should complete successfully ✅

---

## 📁 What Was Created

```
.github/workflows/
├── ci-build-and-push.yml      # Builds & pushes Docker images
├── cd-deploy-to-eks.yml       # Deploys to EKS cluster
└── pr-validation.yml          # Validates PRs before merge

ci-cd-guide.md                 # Complete documentation
CI_CD_QUICKSTART.md           # This file
```

---

## 🔄 How It Works

### On Every Push to `main`:

```
1. CI Workflow (Build & Push)
   ├── Build all services (parallel)
   ├── Run security scans (Trivy)
   ├── Push images to ECR
   └── ✅ Success
   
2. CD Workflow (Deploy)
   ├── Update kubeconfig
   ├── Deploy infrastructure
   ├── Run migrations
   ├── Deploy services
   ├── Run smoke tests
   └── ✅ Deployment complete
```

### On Pull Requests:

```
PR Validation Workflow
├── Run Go tests
├── Lint Dockerfiles
├── Validate Kubernetes YAML
├── Check for secrets
└── Post results as PR comment
```

---

## 🎯 Common Workflows

### Automatic Deployment (Recommended)

```bash
# Just push to main - CI/CD handles everything
git checkout main
git merge your-feature-branch
git push origin main

# Watch deployment in GitHub Actions tab
```

### Manual Deployment

```bash
# GitHub → Actions → "CD - Deploy to EKS" → Run workflow
# Select environment: production or staging
# Click "Run workflow"
```

### Deploy Specific Service

```bash
# Rebuild and push specific service
docker build -t $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bookmyevent/user-service:latest -f Dockerfile-user-service .
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bookmyevent/user-service:latest

# Restart deployment
kubectl rollout restart deployment/user-service -n bookmyevent
```

---

## 🔧 Troubleshooting

### Workflow fails at "Login to Amazon ECR"

```bash
# Verify secrets are set in GitHub
# Settings → Secrets and variables → Actions

# Test locally:
aws ecr get-login-password --region us-east-1
```

### "Access Denied" when deploying to EKS

```bash
# Update EKS ConfigMap to allow GitHub Actions user
kubectl edit configmap aws-auth -n kube-system

# Add under mapUsers:
# - groups:
#   - system:masters
#   userarn: arn:aws:iam::YOUR_ACCOUNT_ID:user/github-actions-bookmyevent
#   username: github-actions-bookmyevent

# Or run this script:
./scripts/k8s/add-github-actions-to-eks.sh
```

### Deployment hangs at "Wait for PostgreSQL"

```bash
# Check pod status
kubectl get pods -n bookmyevent

# Check logs
kubectl logs deployment/postgres -n bookmyevent

# If PVC stuck, check storage class
kubectl get pvc -n bookmyevent
kubectl get storageclass
```

---

## 🔒 Security Features

✅ **Trivy Scanning** - All images scanned for vulnerabilities  
✅ **Secret Detection** - Gitleaks prevents credential leaks  
✅ **Least Privilege IAM** - Minimal permissions for GitHub Actions  
✅ **SARIF Upload** - Security results in GitHub Security tab  
✅ **Protected Branches** - Require PR reviews before merge

---

## 📊 Monitoring

### View Build Status

```bash
# GitHub → Actions tab
# Filter by workflow or branch
```

### View Security Scans

```bash
# GitHub → Security → Code scanning
# View Trivy scan results for each service
```

### View Deployments

```bash
# GitHub → Code → Environments → production
# Shows deployment history and status
```

---

## 🎨 Customization

### Change Deployment Trigger

Edit `.github/workflows/cd-deploy-to-eks.yml`:

```yaml
on:
  push:
    branches:
      - main
      - release/*  # Also deploy release branches
```

### Add Slack Notifications

Add to workflow:

```yaml
- name: Notify Slack
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Deployment ${{ job.status }}"
      }
```

### Enable Staging Environment

Create namespace:

```bash
kubectl create namespace bookmyevent-staging
```

Deploy to staging first, then production.

---

## 💡 Pro Tips

1. **Use Draft PRs** for work-in-progress (prevents running expensive workflows)
2. **Enable auto-merge** on dependabot PRs after tests pass
3. **Use environments** with approval gates for production
4. **Cache aggressively** to speed up builds
5. **Monitor costs** in AWS Cost Explorer (ECR storage, data transfer)

---

## 📈 What's Automated Now

| Task | Before | After |
|------|--------|-------|
| Build images | Manual `docker build` | ✅ Automatic on push |
| Security scanning | Never | ✅ Every build |
| Push to ECR | Manual `docker push` | ✅ Automatic |
| Deploy to EKS | Run 5 scripts | ✅ Automatic |
| Database migrations | Manual kubectl | ✅ Automatic |
| Smoke tests | Never | ✅ After every deploy |
| Rollback | Manual kubectl | ✅ Automatic on failure |

---

## 🎉 You're All Set!

Your CI/CD pipeline is now fully automated. Every push to `main`:

1. ✅ Builds all Docker images
2. ✅ Scans for security vulnerabilities
3. ✅ Pushes to Amazon ECR
4. ✅ Deploys to EKS cluster
5. ✅ Runs database migrations
6. ✅ Seeds test data
7. ✅ Runs smoke tests
8. ✅ Posts deployment summary

---

**Need more details?** See `ci-cd-guide.md` for comprehensive documentation.

**Having issues?** Check the troubleshooting section above or GitHub Actions logs.
