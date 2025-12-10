# BookMyEvent - Deployment Guide

**Course:** ENPM818R - Virtualization & Containerization  
**Project:** Microservices Event Management Platform on AWS EKS  
**Semester:** Fall 2025

---

## 📖 Document Overview

This comprehensive deployment guide provides step-by-step instructions for deploying a production-ready, cloud-native microservices application (BookMyEvent) to Amazon Elastic Kubernetes Service (EKS) with:

- **Container Orchestration:** Kubernetes on AWS EKS
- **Database:** AWS RDS PostgreSQL (managed service)
- **CI/CD:** GitHub Actions automated pipeline
- **Load Balancing:** Application Load Balancer (ALB) with HTTPS/TLS
- **Monitoring:** Prometheus & Grafana stack
- **Security:** NetworkPolicies, encrypted databases, SSL connections, non-root containers

**Deployment Time:** ~40-60 minutes (automated pipeline: ~15-20 minutes)

---

## 📋 Prerequisites

### Required Tools
| Tool | Version | Installation |
|------|---------|--------------|
| AWS CLI v2 | Latest | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| kubectl | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| eksctl | Latest | [Install Guide](https://eksctl.io/installation/) |
| Docker Desktop | Latest | [Install Guide](https://docs.docker.com/get-docker/) |

### AWS Configuration
```powershell
# Configure AWS CLI with SSO
aws configure sso

# Or with access keys
aws configure

# Verify your identity
aws sts get-caller-identity
```

### Required AWS Permissions
- EKS: Full access
- ECR: Full access
- RDS: Full access
- Route53: Full access
- ACM: Full access
- EC2: VPC, Security Groups, Load Balancers

---

## 🔐 Security Features Included

This deployment includes the following security best practices:

| Category | Measures |
|----------|----------|
| **Docker** | Multi-stage builds, non-root user, HEALTHCHECK, Alpine images |
| **Kubernetes** | NetworkPolicy, resource limits, liveness/readiness probes |
| **Network** | TLS/HTTPS, internal ClusterIP services, NLB with TLS termination |
| **Data** | RDS encryption at rest, SSL database connections |
| **Secrets** | Kubernetes Secrets, no hardcoded credentials |

---

## 🚀 Quick Start (Automated CI/CD Deployment)

**Recommended:** Use GitHub Actions for automated deployment with RDS:

1. Push to `build` branch
2. GitHub Actions automatically:
   - Builds and pushes Docker images to ECR
   - Deploys Helm chart to EKS
   - Runs database migrations
   - Tests endpoints

**Time: ~15-20 minutes**

---

## 📦 Full Production Deployment

### Step 1: Setup GitHub Secrets

Add these secrets to your GitHub repository (Settings → Secrets → Actions):

```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=<your-access-key>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
EKS_CLUSTER_NAME=bookmyevent-cluster
ECR_REGISTRY=<account-id>.dkr.ecr.us-east-1.amazonaws.com/bookmyevent

# RDS Connection Strings
RDS_ENDPOINT=<your-rds-endpoint>
USER_SERVICE_DB_URL=postgresql://postgres:<password>@<rds-endpoint>:5432/users_db?sslmode=require
EVENT_SERVICE_DB_URL=postgresql://postgres:<password>@<rds-endpoint>:5432/events_db?sslmode=require
BOOKING_SERVICE_DB_URL=postgresql://postgres:<password>@<rds-endpoint>:5432/bookings_db?sslmode=require

# Security Secrets
JWT_SECRET=<your-secure-jwt-secret>
INTERNAL_API_KEY=<your-secure-api-key>
ADMIN_JWT_SECRET=<your-admin-jwt-secret>
POSTGRES_PASSWORD=<your-rds-password>
```

### Step 2: Deploy EKS Cluster & Infrastructure

This creates:
- EKS cluster with 3 t3.medium nodes across availability zones
- ECR repositories for all microservices
- Redis and Elasticsearch in-cluster
- ALB Ingress Controller
- AWS Load Balancer Controller

**Time: ~25-30 minutes**

---

### Step 3: Setup AWS RDS PostgreSQL (Production Database)

Replace in-cluster PostgreSQL with managed AWS RDS:

#### 3.1 Create RDS Instance

```bash
# Get your VPC and Subnet IDs from EKS cluster
aws eks describe-cluster --name bookmyevent-cluster \
  --query "cluster.resourcesVpcConfig.{VpcId:vpcId,SubnetIds:subnetIds}" \
  --region us-east-1

# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name bookmyevent-rds-subnet-group \
  --db-subnet-group-description "Subnet group for BookMyEvent RDS" \
  --subnet-ids subnet-xxxxx subnet-yyyyy subnet-zzzzz \
  --region us-east-1

# Create security group for RDS
VPC_ID=$(aws eks describe-cluster --name bookmyevent-cluster \
  --query "cluster.resourcesVpcConfig.vpcId" --output text --region us-east-1)

aws ec2 create-security-group \
  --group-name bookmyevent-rds-sg \
  --description "Security group for BookMyEvent RDS" \
  --vpc-id $VPC_ID \
  --region us-east-1

# Allow PostgreSQL from EKS nodes
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=bookmyevent-rds-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region us-east-1)

NODE_SG=$(aws eks describe-cluster --name bookmyevent-cluster \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text --region us-east-1)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $NODE_SG \
  --region us-east-1

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier bookmyevent-rds \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.3 \
  --master-username postgres \
  --master-user-password "YourSecurePassword123!" \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --vpc-security-group-ids $SG_ID \
  --db-subnet-group-name bookmyevent-rds-subnet-group \
  --backup-retention-period 7 \
  --multi-az false \
  --region us-east-1
```

#### 3.2 Wait for RDS and Create Databases

```bash
# Wait for RDS (~10-15 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier bookmyevent-rds \
  --region us-east-1

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier bookmyevent-rds \
  --query "DBInstances[0].Endpoint.Address" \
  --output text --region us-east-1)

echo "RDS Endpoint: $RDS_ENDPOINT"
```

Databases will be created automatically by the migration job in GitHub Actions workflow.

#### 3.3 Update GitHub Secrets

Add/update these secrets with your RDS information:

```bash
RDS_ENDPOINT=<your-rds-endpoint>
POSTGRES_PASSWORD=YourSecurePassword123!
USER_SERVICE_DB_URL=postgresql://postgres:YourSecurePassword123!@<rds-endpoint>:5432/users_db?sslmode=require
EVENT_SERVICE_DB_URL=postgresql://postgres:YourSecurePassword123!@<rds-endpoint>:5432/events_db?sslmode=require
BOOKING_SERVICE_DB_URL=postgresql://postgres:YourSecurePassword123!@<rds-endpoint>:5432/bookings_db?sslmode=require
```

#### 3.4 Trigger Deployment

Push to the `build` branch or manually trigger the `Deploy BookMyEvent` workflow. The pipeline will:
- Create databases on RDS
- Run migrations
- Deploy services with RDS connection strings

---

### Step 4: Setup Custom Domain with HTTPS (ALB + ACM)

#### 4.1 Request ACM Certificate

```bash
# Request certificate for your domain
aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names "*.yourdomain.com" \
  --validation-method DNS \
  --region us-east-1

# Get certificate ARN
CERT_ARN=$(aws acm list-certificates --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='yourdomain.com'].CertificateArn" \
  --output text)

# Get DNS validation records
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions"
```

#### 4.2 Create DNS Validation Records

Add the CNAME records from step 4.1 to your DNS provider (Route53, DNSExit, etc.)

Wait for validation:
```bash
aws acm wait certificate-validated \
  --certificate-arn $CERT_ARN \
  --region us-east-1
```

#### 4.3 Update Helm Values for HTTPS

Update `helm/values.yaml`:

```yaml
ingress:
  enabled: true
  className: alb
  host: "yourdomain.com"  # Your custom domain
  tls:
    enabled: true
    certificateArn: "arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID"
```

#### 4.4 Create DNS Record for ALB

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress bookmyevent-ingress -n bookmyevent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "ALB DNS: $ALB_DNS"

# Get ALB Hosted Zone ID (always Z26RNL4JYFTOTI for us-east-1)
ALB_ZONE_ID="Z26RNL4JYFTOTI"
```

**Option A: Using Route53 (if you have a hosted zone)**

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='yourdomain.com.'].Id" \
  --output text | sed 's|/hostedzone/||')

# Create A record pointing to ALB
cat <<EOF > dns-record.json
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "yourdomain.com",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "$ALB_ZONE_ID",
        "DNSName": "$ALB_DNS",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://dns-record.json
```

**Option B: Using DNSExit or other provider**

Create an A record or CNAME pointing `yourdomain.com` to the ALB DNS name.

#### 4.5 Redeploy with HTTPS Enabled

```bash
# Push updated helm/values.yaml to GitHub
git add helm/values.yaml
git commit -m "Enable HTTPS with custom domain"
git push origin build
```

The pipeline will redeploy with HTTPS enabled. After deployment:
- HTTP requests will redirect to HTTPS
- Frontend will be accessible at https://yourdomain.com
- API accessible at https://yourdomain.com/api/

---

### Step 5: Setup Monitoring (Prometheus & Grafana)

The monitoring stack is deployed via a separate workflow:

```bash
# Trigger manually from GitHub Actions UI:
# Actions → Setup Monitoring Stack → Run workflow → select 'build' branch

# Or via GitHub CLI:
gh workflow run setup-monitoring.yml --ref build
```

This deploys:
- Prometheus (metrics collection)
- Grafana (visualization dashboards)
- Alertmanager (alert routing)
- Custom alert rules for BookMyEvent services

**Access URLs** (after deployment):
```bash
# Get LoadBalancer URLs
kubectl get svc -n monitoring

# Grafana: http://<grafana-lb-url> (admin/admin)
# Prometheus: http://<prometheus-lb-url>:9090
# Alertmanager: http://<alertmanager-lb-url>:9093
```

---

##  Verify Deployment

### Check Application Status

```bash
# Get ALB URL
kubectl get ingress bookmyevent-ingress -n bookmyevent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test health endpoint
curl http://<alb-dns>/health

# Test API endpoints
curl http://<alb-dns>/api/event/events

# Or with HTTPS if configured
curl https://yourdomain.com
curl https://yourdomain.com/api/event/events
```

### Check Pods
```bash
kubectl get pods -n bookmyevent
```

All pods should show `1/1 Running`.

### View Logs
```bash
# Service logs
kubectl logs -f deployment/user-service -n bookmyevent
kubectl logs -f deployment/event-service -n bookmyevent

# Check recent events
kubectl get events -n bookmyevent --sort-by='.lastTimestamp'
```

### Test Credentials
- **User:** atlanuser1@mail.com / 11111111
- **Admin:** atlanadmin@mail.com / 11111111

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS (443) / HTTP (80)
                   ┌───────▼────────┐
                   │  AWS ALB       │
                   │  (Ingress)     │
                   │  + ACM Cert    │
                   └───────┬────────┘
                           │
┌──────────────────────────┴───────────────────────────────────┐
│                     AWS EKS Cluster                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              nginx-gateway (ClusterIP)                  │ │
│  │    Routes: /api/user → user-service:8081              │ │
│  │            /api/event → event-service:8082            │ │
│  │            /api/search → search-service:8083          │ │
│  │            /api/booking → booking-service:8084        │ │
│  │            / → frontend:80                            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              NetworkPolicy Applied                    │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │   │
│  │  │  User    │ │  Event   │ │ Booking  │ │  Search  │ │   │
│  │  │ Service  │ │ Service  │ │ Service  │ │ Service  │ │   │
│  │  │(non-root)│ │(non-root)│ │(non-root)│ │(non-root)│ │   │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ │   │
│  └───────┼────────────┼────────────┼────────────┼───────┘   │
│          │            │            │            │            │
│  ┌───────▼────────────▼────────────▼────┐  ┌───▼───┐       │
│  │              Redis                    │  │Elastic│       │
│  └───────────────────────────────────────┘  │Search │       │
│                                              └───────┘       │
└─────────────────────────┬────────────────────────────────────┘
                          │ SSL/TLS
              ┌───────────▼───────────┐
              │    AWS RDS PostgreSQL │
              │  (Encrypted at Rest)  │
              │  ├── users_db         │
              │  ├── events_db        │
              │  └── bookings_db      │
              └───────────────────────┘

         ┌───────────────────────────┐
         │   Monitoring Stack        │
         │  (separate namespace)     │
         │  ┌──────────────────┐    │
         │  │   Prometheus     │    │
         │  │   (LoadBalancer) │    │
         │  ├──────────────────┤    │
         │  │   Grafana        │    │
         │  │   (LoadBalancer) │    │
         │  ├──────────────────┤    │
         │  │   Alertmanager   │    │
         │  │   (LoadBalancer) │    │
         │  └──────────────────┘    │
         └───────────────────────────┘
```

---

## 💰 Cost Estimation

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| EKS Control Plane | Managed | ~$72 |
| EC2 Nodes (3x t3.medium) | On-demand | ~$90 |
| RDS (db.t3.micro) | PostgreSQL | ~$15 |
| ALB | Application Load Balancer | ~$18 |
| Monitoring (3x NLB for Prometheus/Grafana/Alertmanager) | Network Load Balancers | ~$30 |
| Route53 Hosted Zone | DNS (optional) | ~$0.50 |
| ECR Storage | Container Images (~5 GB) | ~$0.50 |
| **Total** | | **~$225/month** |

**Cost Optimization Tips:**
- Use Spot Instances for worker nodes (~70% savings)
- Enable Cluster Autoscaler to scale down during low traffic
- Delete monitoring stack if not needed ($30/month savings)
- Use in-cluster PostgreSQL instead of RDS ($15/month savings)

---

## 🧹 Cleanup

### Automated Cleanup

```bash
# Delete Helm release
helm uninstall bookmyevent -n bookmyevent

# Delete namespace (this removes all resources)
kubectl delete namespace bookmyevent

# Delete monitoring stack
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring

# Wait for load balancers to be deleted (~2 minutes)
sleep 120

# Delete RDS
aws rds delete-db-instance \
  --db-instance-identifier bookmyevent-rds \
  --skip-final-snapshot \
  --delete-automated-backups \
  --region us-east-1

# Delete security groups and subnet groups (after RDS deletion completes)
aws ec2 delete-security-group --group-id <rds-sg-id> --region us-east-1
aws rds delete-db-subnet-group \
  --db-subnet-group-name bookmyevent-rds-subnet-group \
  --region us-east-1

# Delete ECR repositories
aws ecr delete-repository --repository-name bookmyevent/user-service --force --region us-east-1
aws ecr delete-repository --repository-name bookmyevent/event-service --force --region us-east-1
aws ecr delete-repository --repository-name bookmyevent/booking-service --force --region us-east-1
aws ecr delete-repository --repository-name bookmyevent/search-service --force --region us-east-1
aws ecr delete-repository --repository-name bookmyevent/frontend --force --region us-east-1
aws ecr delete-repository --repository-name bookmyevent/init-container --force --region us-east-1

# Delete EKS cluster (takes 10-15 minutes)
eksctl delete cluster --name bookmyevent-cluster --region us-east-1

# Optional: Delete Route53 hosted zone and ACM certificate
ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='yourdomain.com.'].Id" \
  --output text | sed 's|/hostedzone/||')
aws route53 delete-hosted-zone --id $ZONE_ID

aws acm delete-certificate --certificate-arn <cert-arn> --region us-east-1
```

---

## 🔧 Troubleshooting

### Certificate shows "Not Secure"
- Clear browser cache or use incognito window
- Verify certificate covers both root and wildcard domains
- Check listener is using correct certificate ARN

### Pods in CrashLoopBackOff
```powershell
kubectl logs POD_NAME -n bookmyevent
kubectl describe pod POD_NAME -n bookmyevent
```

### InvalidImageName Error
```powershell
# Set correct image
kubectl set image deployment/SERVICE_NAME SERVICE_NAME=ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/bookmyevent/SERVICE_NAME:latest -n bookmyevent
```

### Database Connection Issues
- Check RDS security group allows port 5432
- Verify secrets are updated with correct RDS endpoint
- Restart services after updating secrets

### DNS Not Resolving
- Verify nameservers are updated at domain registrar
- Check Route53 hosted zone has correct records
- DNS propagation can take up to 48 hours

---

## 📊 Security Checklist

### Docker/Container Security
-  Multi-stage Docker builds (reduced image size)
-  Non-root containers (appuser UID 1000)
-  HEALTHCHECK in Dockerfiles (liveness detection)
-  Alpine-based minimal images (reduced attack surface)
-  .dockerignore created (exclude sensitive files)

### Kubernetes Security
-  Resource limits on pods (CPU/memory quotas)
-  Liveness/Readiness probes (automatic pod recovery)
-  NetworkPolicy applied (pod-to-pod communication control)
-  Kubernetes Secrets for credentials (encrypted etcd storage)
-  Service Accounts with RBAC (least privilege)

### Network Security
-  TLS/HTTPS on load balancers (ACM certificates)
-  Private ClusterIP services (internal-only access)
-  ALB + nginx gateway routing (single entry point)
-  Security groups restricting RDS access (EKS nodes only)

### Data Security
-  RDS encryption at rest (AES-256)
-  SSL database connections (sslmode=require)
-  Password hashing with bcrypt (user passwords)
-  JWT token authentication (stateless auth)

### Infrastructure Security
-  Private ECR registry (authenticated image pulls)
-  IAM roles for EKS nodes (AWS service access)
-  Automated backups enabled (RDS 7-day retention)
-  GitHub Secrets for CI/CD credentials (never committed to repo)

---

## 📚 Learning Outcomes (ENPM818R)

This deployment demonstrates proficiency in:

### Virtualization & Containerization Concepts
1. **Docker:** Multi-stage builds, layer optimization, non-root users, health checks
2. **Container Orchestration:** Kubernetes deployments, services, ingress, secrets, configmaps
3. **Microservices Architecture:** Service mesh, API gateway pattern, inter-service communication
4. **Infrastructure as Code:** Helm charts, Kubernetes manifests, declarative configuration

### Cloud-Native Technologies
1. **AWS EKS:** Managed Kubernetes, node groups, cluster autoscaling
2. **Container Registry:** ECR private repositories, image scanning
3. **Managed Databases:** RDS PostgreSQL, automated backups, multi-AZ
4. **Load Balancing:** ALB Ingress Controller, SSL/TLS termination

### DevOps & CI/CD
1. **GitHub Actions:** Automated build, test, deploy pipelines
2. **GitOps:** Git as source of truth, declarative deployments
3. **Monitoring:** Prometheus metrics, Grafana dashboards, Alertmanager

### Production Best Practices
1. **High Availability:** Multi-AZ deployments, health checks, auto-recovery
2. **Security:** Encryption at rest/transit, network policies, least privilege
3. **Observability:** Logging, metrics, tracing, alerting
4. **Cost Optimization:** Resource limits, spot instances, autoscaling

---

**Happy Deploying! 🚀**
