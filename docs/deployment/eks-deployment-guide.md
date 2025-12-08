# ENPM818R Group Project: BookMyEvent - EKS Deployment Guide

This guide walks you through deploying BookMyEvent to Amazon Elastic Kubernetes Service (EKS).

## 📋 Prerequisites

Before starting, ensure you have the following installed:

### Required Tools

1. **AWS CLI v2** - [Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
   ```bash
   # Verify installation
   aws --version
   ```

2. **kubectl** - [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
   ```bash
   # Verify installation
   kubectl version --client
   ```

3. **eksctl** - [Installation Guide](https://eksctl.io/installation/)
   ```bash
   # Verify installation
   eksctl version
   ```

4. **Docker** - [Installation Guide](https://docs.docker.com/get-docker/)
   ```bash
   # Verify installation
   docker --version
   ```

### AWS Configuration

1. Configure AWS CLI with your credentials:
   ```bash
   aws configure
   ```
   
   You'll need:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (e.g., `us-east-1`)

2. Verify your identity:
   ```bash
   aws sts get-caller-identity
   ```

### Required AWS Permissions

Your AWS user/role needs the following permissions:
- **EKS**: Full access to create/manage clusters
- **ECR**: Full access to create repositories and push images
- **EC2**: Access to create VPCs, subnets, security groups
- **IAM**: Access to create service-linked roles
- **CloudFormation**: Full access (eksctl uses CloudFormation)

---

## 🚀 One-Command Deployment

For the fastest deployment, use the complete deployment script:

```powershell
# Windows PowerShell
.\scripts\eks\deploy-complete.ps1

# Linux/Mac
./scripts/eks/deploy-complete.sh
```

This single command will:
1. Create ECR repositories
2. Build and push all Docker images
3. Create an EKS cluster (~15-20 min)
4. Install EBS CSI driver for persistent storage
5. Deploy all infrastructure (PostgreSQL, Redis, Elasticsearch)
6. Run database migrations
7. Deploy all microservices
8. Build frontend with correct API URL
9. Seed test data

---


## 🚀 Quick Deployment (5 Steps)

### Step 1: Set Environment Variables

```bash
# Linux/Mac
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME="bookmyevent-cluster"

# Windows PowerShell
$env:AWS_REGION = "us-east-1"
$env:AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
$env:CLUSTER_NAME = "bookmyevent-cluster"
```

### Step 2: Create ECR Repositories

```bash
# Linux/Mac
chmod +x scripts/eks/*.sh
./scripts/eks/1-create-ecr-repos.sh

# Windows PowerShell
.\scripts\eks\1-create-ecr-repos.ps1
```

### Step 3: Build & Push Docker Images

```bash
# Linux/Mac
./scripts/eks/2-build-push-images.sh

# Windows PowerShell
.\scripts\eks\2-build-push-images.ps1
```

### Step 4: Create EKS Cluster

```bash
# Linux/Mac
./scripts/eks/3-create-eks-cluster.sh

# Windows PowerShell
.\scripts\eks\3-create-eks-cluster.ps1
```

⏱️ **Note**: Cluster creation takes 15-20 minutes.

### Step 5: Deploy Application

```bash
# Linux/Mac
./scripts/eks/4-deploy-to-eks.sh

# Windows PowerShell
.\scripts\eks\4-deploy-to-eks.ps1
```

---

## 🌐 Accessing Your Deployment

After deployment, get the external URLs:

```bash
# Get API Gateway URL
kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get Frontend URL
kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Test the API

```bash
# Health check
curl http://<API_GATEWAY_URL>/health

# Get events
curl http://<API_GATEWAY_URL>/api/event/events

# Login
curl -X POST http://<API_GATEWAY_URL>/api/user/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "atlanuser1@mail.com", "password": "11111111"}'
```

---

## 📁 Project Structure

```
k8s/
├── 00-namespace.yaml          # Kubernetes namespace
├── 01-configmap.yaml          # Environment configuration
├── 02-secrets.yaml            # Sensitive configuration
├── infrastructure/
│   ├── postgres.yaml          # PostgreSQL database
│   ├── redis.yaml             # Redis cache
│   └── elasticsearch.yaml     # Elasticsearch search
└── services/
    ├── user-service.yaml      # User microservice
    ├── event-service.yaml     # Event microservice
    ├── search-service.yaml    # Search microservice
    ├── booking-service.yaml   # Booking microservice
    ├── nginx-gateway.yaml     # API Gateway
    ├── frontend.yaml          # React frontend
    └── init-container.yaml    # Database seeder

scripts/eks/
├── 1-create-ecr-repos.sh      # Create ECR repositories
├── 2-build-push-images.sh     # Build & push Docker images
├── 3-create-eks-cluster.sh    # Create EKS cluster
├── 4-deploy-to-eks.sh         # Deploy to EKS
└── 5-cleanup.sh               # Delete all resources
```

---

## 🔧 Common Commands

### View Resources

```bash
# View all pods
kubectl get pods -n bookmyevent

# View all services
kubectl get svc -n bookmyevent

# View all deployments
kubectl get deployments -n bookmyevent

# View pod logs
kubectl logs -f deployment/user-service -n bookmyevent
```

### Debugging

```bash
# Describe a failing pod
kubectl describe pod <pod-name> -n bookmyevent

# Get shell access to a pod
kubectl exec -it <pod-name> -n bookmyevent -- /bin/sh

# Port-forward a service locally
kubectl port-forward svc/nginx-gateway 8080:80 -n bookmyevent
```

### Scaling

```bash
# Scale a deployment
kubectl scale deployment user-service --replicas=3 -n bookmyevent

# Enable autoscaling
kubectl autoscale deployment user-service --min=2 --max=10 --cpu-percent=80 -n bookmyevent
```

### Updating Deployments

```bash
# Update image tag
kubectl set image deployment/user-service user-service=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/bookmyevent/user-service:v2 -n bookmyevent

# Restart deployment
kubectl rollout restart deployment/user-service -n bookmyevent

# Check rollout status
kubectl rollout status deployment/user-service -n bookmyevent
```

---

## 💰 Cost Estimation

Approximate monthly costs for this deployment:

| Resource | Type | Estimated Cost |
|----------|------|----------------|
| EKS Control Plane | Managed | $72/month |
| EC2 Nodes (2x t3.medium) | On-demand | ~$60/month |
| EBS Volumes (30GB) | gp2 | ~$3/month |
| Load Balancers (2x NLB) | Network | ~$20/month |
| ECR Storage | Per GB | ~$1/month |
| **Total** | | **~$156/month** |

### Cost Optimization Tips

1. Use Spot Instances for nodes (up to 90% savings)
2. Right-size your node instances
3. Use a single Ingress instead of multiple LoadBalancers
4. Consider using AWS Fargate for serverless containers

---

## 🧹 Cleanup

To delete all resources and avoid charges:

```bash
# Linux/Mac
./scripts/eks/5-cleanup.sh

# Windows PowerShell
.\scripts\eks\5-cleanup.ps1
```

This will:
1. Delete the Kubernetes namespace and all resources
2. Delete the EKS cluster
3. Optionally delete ECR repositories

---

## 🔒 Production Recommendations

Before going to production, consider:

### Security
- [ ] Update secrets in `k8s/02-secrets.yaml` with strong passwords
- [ ] Enable SSL/TLS with AWS Certificate Manager
- [ ] Configure proper CORS origins
- [ ] Enable AWS WAF for the load balancer
- [ ] Use AWS Secrets Manager for sensitive data

### High Availability
- [ ] Deploy to multiple Availability Zones
- [ ] Use RDS PostgreSQL instead of in-cluster Postgres
- [ ] Use ElastiCache Redis instead of in-cluster Redis
- [ ] Use Amazon OpenSearch instead of in-cluster Elasticsearch
- [ ] Configure pod disruption budgets

### Monitoring
- [ ] Install Prometheus and Grafana
- [ ] Configure CloudWatch Container Insights
- [ ] Set up alerting for critical metrics
- [ ] Enable AWS X-Ray for distributed tracing

### CI/CD
- [ ] Set up GitHub Actions or AWS CodePipeline
- [ ] Implement GitOps with ArgoCD or Flux

---

## 🌐 Custom Domain Setup

After deployment, set up a custom domain:

```powershell
# Setup DNS for your domain
.\scripts\eks\6-setup-dns.ps1 -DomainName "bookmyevents.com"

# Setup SSL certificate (optional but recommended)
.\scripts\eks\7-setup-ssl.ps1 -DomainName "bookmyevents.com"
```

See `DNS_SETUP_GUIDE.md` for complete instructions including free domain options.

---

## ❓ Troubleshooting

### Pods stuck in Pending

```bash
kubectl describe pod <pod-name> -n bookmyevent
```
Common causes:
- Insufficient cluster resources (scale up nodes)
- PVC not binding (check storage class)

### Pods in CrashLoopBackOff

```bash
kubectl logs <pod-name> -n bookmyevent --previous
```
Common causes:
- Database connection issues
- Missing environment variables

### LoadBalancer stuck in Pending

```bash
kubectl describe svc nginx-gateway -n bookmyevent
```
Common causes:
- Missing IAM permissions
- VPC configuration issues

### Database Connection Refused

Ensure PostgreSQL is ready before services start:
```bash
kubectl get pods -n bookmyevent | grep postgres
kubectl logs deployment/postgres -n bookmyevent
```

---

## 📞 Support

If you encounter issues:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review pod logs: `kubectl logs -f <pod-name> -n bookmyevent`
3. Check AWS CloudWatch logs for EKS events

Happy deploying! 🚀

