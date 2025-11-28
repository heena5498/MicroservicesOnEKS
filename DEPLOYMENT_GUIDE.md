# BookMyEvent - Deployment & Cleanup Guide

This guide provides step-by-step instructions for deploying and cleaning up the BookMyEvent application on AWS EKS.

## 📋 Available Scripts

### Deployment Scripts

| Script | Description | Time | Usage |
|--------|-------------|------|-------|
| `scripts/eks/deploy-complete.ps1` | **Complete one-command deployment** | ~25 min | Recommended for full deployment |
| `scripts/eks/1-create-ecr-repos.ps1` | Create ECR repositories only | 1 min | Step-by-step deployment |
| `scripts/eks/2-build-push-images.ps1` | Build and push Docker images | 10-15 min | Step-by-step deployment |
| `scripts/eks/3-create-eks-cluster.ps1` | Create EKS cluster only | 15-20 min | Step-by-step deployment |
| `scripts/eks/4-deploy-to-eks.ps1` | Deploy Kubernetes resources | 5-10 min | Step-by-step deployment |

### Cleanup Scripts

| Script | Description | What It Deletes |
|--------|-------------|-----------------|
| `scripts/eks/5-cleanup.ps1` | Cleanup all resources | EKS cluster, Kubernetes resources, (optional) ECR repos |

## 🚀 Quick Start: Deploy Everything

### One-Command Deployment

```powershell
.\scripts\eks\deploy-complete.ps1
```

This script does everything:
1. ✅ Creates ECR repositories
2. ✅ Builds and pushes all Docker images
3. ✅ Creates EKS cluster
4. ✅ Installs EBS CSI driver
5. ✅ Deploys all Kubernetes resources
6. ✅ Runs database migrations
7. ✅ Seeds initial test data

**Time**: ~25 minutes  
**Cost**: Starts when EKS cluster is created

---

## 🧹 Cleanup: Remove Everything

### Complete Cleanup Script

```powershell
.\scripts\eks\5-cleanup.ps1
```

This script will:
1. ⚠️ Ask for confirmation
2. Delete Kubernetes namespace (all pods, services, etc.)
3. Delete EKS cluster
4. Optionally delete ECR repositories

**Time**: ~10-15 minutes  
**Cost**: Stops once cluster is deleted

---

## 📝 Step-by-Step Deployment (If Needed)

If you prefer more control, run scripts individually:

### Step 1: Create ECR Repositories
```powershell
.\scripts\eks\1-create-ecr-repos.ps1
```

### Step 2: Build and Push Images
```powershell
.\scripts\eks\2-build-push-images.ps1
```
**Note**: Requires Docker Desktop running

### Step 3: Create EKS Cluster
```powershell
.\scripts\eks\3-create-eks-cluster.ps1
```
**Time**: 15-20 minutes

### Step 4: Deploy to EKS
```powershell
.\scripts\eks\4-deploy-to-eks.ps1
```

---

## 🌐 DNS Setup (After Deployment)

After deployment, set up DNS:

```powershell
.\scripts\eks\6-setup-dns.ps1
```

Or manually:
1. Update nameservers at your registrar
2. Wait 5-15 minutes for DNS propagation

---

## 💰 Cost Management

### When You're Not Using It

**To stop costs:**
```powershell
.\scripts\eks\5-cleanup.ps1
```
This deletes the EKS cluster and all resources.

**Note**: ECR repositories cost very little (~$0.10/month per repository), so you can keep them or delete them.

### When You Want to Use It Again

Simply redeploy:
```powershell
.\scripts\eks\deploy-complete.ps1
```

The ECR repositories and images will still be there, so it will be faster (~20 minutes instead of 25).

---

## 📊 Cost Breakdown

| Resource | Monthly Cost | When Charged |
|----------|--------------|--------------|
| EKS Cluster | $0.10/hour (~$72/month) | Only when cluster exists |
| EC2 Nodes (2x t3.medium) | ~$60/month | Only when cluster exists |
| Load Balancers (NLB) | ~$20/month | Only when services are running |
| EBS Volumes | ~$5/month | Only when PVCs exist |
| ECR Storage | ~$0.10/month | Per repository |
| Route 53 | $0.50/month | Per hosted zone |

**Total when running**: ~$157/month  
**Total when stopped**: ~$0.60/month (Route 53 + ECR)

---

## 🔧 Useful Commands

### Check Deployment Status
```powershell
kubectl get pods -n bookmyevent
kubectl get svc -n bookmyevent
kubectl get pvc -n bookmyevent
```

### View Logs
```powershell
kubectl logs -f deployment/user-service -n bookmyevent
kubectl logs -f deployment/frontend -n bookmyevent
```

### Get Application URLs
```powershell
kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Restart Services
```powershell
kubectl rollout restart deployment/user-service -n bookmyevent
kubectl rollout restart deployment/frontend -n bookmyevent
```

---

## ⚠️ Important Notes

1. **Cleanup takes time**: EKS cluster deletion takes 10-15 minutes
2. **Data is deleted**: PVCs (database, Redis, Elasticsearch data) are deleted with cleanup
3. **DNS stays**: Route 53 hosted zone is NOT deleted (keeps your domain working)
4. **ECR images**: Optionally kept for faster redeployment

---

## 🆘 Troubleshooting

### Cleanup Failed
If cleanup fails partway:
```powershell
# Manually delete namespace
kubectl delete namespace bookmyevent --force --grace-period=0

# Manually delete cluster
eksctl delete cluster --name bookmyevent-cluster --region us-east-1
```

### Redeployment Issues
If images are missing:
```powershell
# Rebuild images
.\scripts\eks\2-build-push-images.ps1
```

---

## 📚 Quick Reference

| Action | Command |
|--------|---------|
| Deploy everything | `.\scripts\eks\deploy-complete.ps1` |
| Cleanup everything | `.\scripts\eks\5-cleanup.ps1` |
| Check pods | `kubectl get pods -n bookmyevent` |
| View logs | `kubectl logs -f deployment/<service> -n bookmyevent` |
| Get URLs | `kubectl get svc -n bookmyevent` |

---

## 🎯 Recommended Workflow

### Daily Use
1. Deploy: `.\scripts\eks\deploy-complete.ps1`
2. Use application
3. When done: `.\scripts\eks\5-cleanup.ps1`

### Development/Testing
1. Deploy once
2. Keep running for testing
3. Cleanup when done

### Production
1. Deploy once
2. Keep running
3. Monitor costs in AWS Console


