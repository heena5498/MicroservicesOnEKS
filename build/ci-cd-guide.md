# GitHub Actions CI/CD Pipeline Guide

This guide explains the automated CI/CD pipeline for BookMyEvent using GitHub Actions.

## 🚀 Overview

The CI/CD pipeline automates:
-  Building Docker images
-  Security vulnerability scanning (Trivy)
-  Pushing images to Amazon ECR
-  Deploying to EKS cluster
-  Running database migrations
-  Smoke testing deployments
-  PR validation and testing

## 📋 Workflows

### 1. **CI - Build and Push Images** (`ci-build-and-push.yml`)

**Triggers:**
- Push to `main`, `develop`, or `build` branches
- Pull requests to `main` or `develop`
- Manual workflow dispatch

**What it does:**
1. Builds all backend services (user, event, search, booking)
2. Builds frontend with npm install and tests
3. Builds init container
4. Runs Trivy security scans on all images
5. Uploads scan results to GitHub Security tab
6. Pushes images to ECR (only on push, not PR)

**Image Tags:**
- `latest` - Latest from main branch
- `{branch}-{sha}` - Branch name + commit SHA
- `{branch}` - Branch name

---

### 2. **CD - Deploy to EKS** (`cd-deploy-to-eks.yml`)

**Triggers:**
- Automatically after successful CI workflow on `main` branch
- Manual workflow dispatch with environment selection

**What it does:**
1. Updates kubeconfig for EKS cluster
2. Deploys namespace and configuration
3. Deploys infrastructure (PostgreSQL, Redis, Elasticsearch)
4. Waits for infrastructure to be ready
5. Runs database migrations
6. Deploys all microservices
7. Deploys NGINX gateway and frontend
8. Seeds database with test data
9. Runs smoke tests
10. Creates GitHub deployment record

**Outputs:**
- Frontend URL
- API Gateway URL
- Deployment summary

---

### 3. **PR Validation** (`pr-validation.yml`)

**Triggers:**
- When PR is opened, updated, or reopened

**What it does:**
1. **Go Validation:**
   - Runs `go vet`
   - Checks `go fmt` formatting
   - Runs unit tests with race detection
   - Uploads coverage to Codecov
   - Checks for security vulnerabilities

2. **Dockerfile Linting:**
   - Runs hadolint on all Dockerfiles

3. **Kubernetes Validation:**
   - Validates all K8s YAML files with kubeval

4. **Secret Detection:**
   - Scans for leaked secrets with gitleaks

5. **PR Summary:**
   - Posts validation results as comment on PR

---

## 🔑 Required GitHub Secrets

You need to configure these secrets in your GitHub repository:

### **Repository Secrets** (Settings → Secrets and variables → Actions)

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AWS_ACCESS_KEY_ID` | AWS access key for GitHub Actions | Create IAM user with ECR + EKS permissions |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | From IAM user creation |
| `AWS_ACCOUNT_ID` | Your AWS account ID | Run: `aws sts get-caller-identity --query Account --output text` |

### **Optional Secrets**

| Secret Name | Description |
|-------------|-------------|
| `GITLEAKS_LICENSE` | Gitleaks Pro license (optional) |

---

## 🛠️ Setup Instructions

### Step 1: Create IAM User for GitHub Actions

```bash
# Create IAM user
aws iam create-user --user-name github-actions-bookmyevent

# Create access key
aws iam create-access-key --user-name github-actions-bookmyevent

# Save the output - you'll need AccessKeyId and SecretAccessKey
```

### Step 2: Attach IAM Policies

Create a policy file `github-actions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

Apply the policy:

```bash
# Create the policy
aws iam create-policy \
  --policy-name GitHubActionsBookMyEventPolicy \
  --policy-document file://github-actions-policy.json

# Attach to user
aws iam attach-user-policy \
  --user-name github-actions-bookmyevent \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActionsBookMyEventPolicy
```

### Step 3: Configure kubectl Access

Add this inline policy for kubectl access:

```bash
cat > eks-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:AccessKubernetesApi",
        "eks:DescribeCluster"
      ],
      "Resource": "arn:aws:eks:us-east-1:YOUR_ACCOUNT_ID:cluster/bookmyevent-cluster"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name github-actions-bookmyevent \
  --policy-name EKSAccess \
  --policy-document file://eks-access-policy.json
```

### Step 4: Update EKS ConfigMap for GitHub Actions

```bash
# Get current aws-auth configmap
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth.yaml

# Edit and add this to mapUsers section:
# - groups:
#   - system:masters
#   userarn: arn:aws:iam::YOUR_ACCOUNT_ID:user/github-actions-bookmyevent
#   username: github-actions-bookmyevent

# Apply the updated configmap
kubectl apply -f aws-auth.yaml
```

### Step 5: Add Secrets to GitHub

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these secrets:
   - `AWS_ACCESS_KEY_ID` = (from Step 1)
   - `AWS_SECRET_ACCESS_KEY` = (from Step 1)
   - `AWS_ACCOUNT_ID` = (run: `aws sts get-caller-identity --query Account --output text`)

---

## 🔄 Workflow Execution

### Automatic Deployment Flow

```
1. Developer pushes to main branch
   ↓
2. CI workflow triggers
   ↓
3. Builds all Docker images
   ↓
4. Runs security scans
   ↓
5. Pushes to ECR
   ↓
6. CD workflow triggers
   ↓
7. Deploys to EKS
   ↓
8. Runs smoke tests
   ↓
9. Posts deployment summary
```

### Manual Deployment

```bash
# Go to GitHub repository
# Actions → CD - Deploy to EKS → Run workflow
# Select environment: production or staging
# Click "Run workflow"
```

---

## 📊 Monitoring Workflows

### View Workflow Runs

1. Go to **Actions** tab in GitHub
2. Select a workflow
3. Click on a specific run to see details

### View Logs

1. Click on a workflow run
2. Click on a job (e.g., "Build Backend Services")
3. Expand steps to see detailed logs

### View Security Scans

1. Go to **Security** tab
2. Click **Code scanning**
3. View Trivy scan results for each image

---

## 🔍 Troubleshooting

### Workflow Fails at "Login to Amazon ECR"

**Error:** `Unable to locate credentials`

**Solution:**
```bash
# Verify secrets are set correctly
# Check if IAM user has ECR permissions
aws ecr get-login-password --region us-east-1
```

### Workflow Fails at "Update kubeconfig for EKS"

**Error:** `error: You must be logged in to the server (Unauthorized)`

**Solution:**
```bash
# Update aws-auth ConfigMap with GitHub Actions IAM user
kubectl edit configmap aws-auth -n kube-system
```

### Deployment Fails at "Wait for PostgreSQL"

**Error:** `deployment "postgres" not found`

**Solution:**
```bash
# Check if namespace exists
kubectl get namespace bookmyevent

# Check infrastructure deployment
kubectl get deployments -n bookmyevent
```

### Image Pull Errors

**Error:** `Failed to pull image: Access denied`

**Solution:**
```bash
# Grant node role access to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com
```

---

## 🎯 Best Practices

###  DO

-  Use branch protection rules for `main` branch
-  Require PR reviews before merging
-  Enable status checks (require workflows to pass)
-  Use semantic versioning for releases
-  Review security scan results before deploying
-  Test in staging before production
-  Monitor deployment logs

### DON'T

-  Commit AWS credentials to Git
-  Skip security scans
-  Deploy directly to production without testing
-  Ignore failed tests
-    Use `--force` on main branch

---

## 🔒 Security Considerations

### Image Scanning

All images are scanned with Trivy for:
- Critical vulnerabilities
- High vulnerabilities
- Outdated dependencies
- Malware

Results are uploaded to GitHub Security tab.

### Secret Detection

Gitleaks scans every PR for:
- AWS credentials
- API keys
- Private keys
- Passwords

### IAM Permissions

GitHub Actions IAM user follows least-privilege:
-  ECR push/pull only
-  EKS describe and access
-  No delete permissions
-  No IAM modification permissions

---

## 📈 Workflow Optimization

### Caching

Workflows use GitHub Actions cache for:
- Docker layer caching
- Go module caching
- npm package caching

### Parallelization

Backend services build in parallel using matrix strategy:
- 4 services build simultaneously
- Reduces total build time by ~75%

### Conditional Execution

- PR builds don't push to ECR (saves time)
- Deployment only runs after successful CI
- Smoke tests continue on error (non-blocking)

---

## 🚀 Advanced Usage

### Deploy to Staging

```yaml
# Manually trigger CD workflow
# Select environment: staging
# Uses separate namespace: bookmyevent-staging
```

### Rollback Deployment

```bash
# Option 1: Revert commit and push
git revert HEAD
git push origin main

# Option 2: Deploy previous image tag
kubectl set image deployment/user-service \
  user-service=ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/bookmyevent/user-service:main-abc123 \
  -n bookmyevent
```

### Custom Workflow Triggers

```yaml
# Add to workflow file
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly Monday 2 AM
  repository_dispatch:
    types: [deploy-prod]
```

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS Actions for GitHub](https://github.com/aws-actions)
- [Trivy Security Scanner](https://github.com/aquasecurity/trivy)
- [Docker Build Push Action](https://github.com/docker/build-push-action)

---

## 🆘 Getting Help

If workflows fail:

1. **Check workflow logs** in Actions tab
2. **Verify GitHub secrets** are configured
3. **Check IAM permissions** for GitHub Actions user
4. **Verify EKS cluster** is accessible
5. **Review recent commits** for breaking changes
6. **Check AWS service quotas** and limits

For persistent issues, review the detailed logs and error messages in the GitHub Actions interface.
