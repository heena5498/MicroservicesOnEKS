# BookMyEvent - Production Deployment Guide

Complete guide for deploying BookMyEvent to AWS EKS with RDS PostgreSQL, custom domain, SSL/TLS, and security best practices.

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

## 🚀 Quick Start (One-Command Deployment)

For a quick deployment with in-cluster PostgreSQL:

```powershell
.\scripts\eks\deploy-complete.ps1
```

**Time: ~25-30 minutes**

---

## 📦 Full Production Deployment

### Step 1: Deploy Base Infrastructure

```powershell
.\scripts\eks\deploy-complete.ps1
```

This creates:
- EKS cluster with 3 nodes across availability zones
- ECR repositories for all services
- In-cluster PostgreSQL, Redis, Elasticsearch
- All microservices with security features
- Network Load Balancers for frontend and API

**Time: ~25-30 minutes**

---

### Step 2: Setup AWS RDS PostgreSQL

Replace in-cluster PostgreSQL with managed AWS RDS:

```powershell
# Get your VPC and Subnet IDs
aws eks describe-cluster --name bookmyevent-cluster --query "cluster.resourcesVpcConfig" --region us-east-1

# Create RDS instance
aws rds create-db-instance `
    --db-instance-identifier bookmyevent-rds `
    --db-instance-class db.t3.micro `
    --engine postgres `
    --engine-version 16.3 `
    --master-username postgres `
    --master-user-password "YourSecurePassword123!" `
    --allocated-storage 20 `
    --storage-type gp2 `
    --vpc-security-group-ids YOUR_SG_ID `
    --db-subnet-group-name bookmyevent-rds-subnet-group `
    --publicly-accessible `
    --region us-east-1
```

Wait for RDS to be available (~10-15 minutes):
```powershell
aws rds describe-db-instances --db-instance-identifier bookmyevent-rds --query "DBInstances[0].DBInstanceStatus" --region us-east-1
```

Create databases:
```powershell
$RDS_ENDPOINT = aws rds describe-db-instances --db-instance-identifier bookmyevent-rds --query "DBInstances[0].Endpoint.Address" --output text --region us-east-1

kubectl exec -n bookmyevent deployment/postgres -- sh -c "PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE users_db;'"
kubectl exec -n bookmyevent deployment/postgres -- sh -c "PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE events_db;'"
kubectl exec -n bookmyevent deployment/postgres -- sh -c "PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -c 'CREATE DATABASE bookings_db;'"
```

Migrate data from in-cluster PostgreSQL to RDS:
```powershell
# Migrate schema and data
kubectl exec -n bookmyevent deployment/postgres -- sh -c "pg_dump -U postgres -d users_db --schema-only | PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -d users_db"
kubectl exec -n bookmyevent deployment/postgres -- sh -c "pg_dump -U postgres -d users_db --data-only | PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -d users_db"

kubectl exec -n bookmyevent deployment/postgres -- sh -c "pg_dump -U postgres -d events_db --schema-only | PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -d events_db"
kubectl exec -n bookmyevent deployment/postgres -- sh -c "pg_dump -U postgres -d events_db --data-only | PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -d events_db"

kubectl exec -n bookmyevent deployment/postgres -- sh -c "pg_dump -U postgres -d bookings_db --schema-only | PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -d bookings_db"
kubectl exec -n bookmyevent deployment/postgres -- sh -c "pg_dump -U postgres -d bookings_db --data-only | PGPASSWORD='YourSecurePassword123!' psql -h $RDS_ENDPOINT -U postgres -d bookings_db"
```

Update Kubernetes secrets with RDS connection:
```powershell
# Create secrets file
@"
apiVersion: v1
kind: Secret
metadata:
  name: bookmyevent-secrets
  namespace: bookmyevent
type: Opaque
stringData:
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "YourSecurePassword123!"
  USER_SERVICE_DB_URL: "postgresql://postgres:YourSecurePassword123!@$RDS_ENDPOINT:5432/users_db?sslmode=require"
  EVENT_SERVICE_DB_URL: "postgresql://postgres:YourSecurePassword123!@$RDS_ENDPOINT:5432/events_db?sslmode=require"
  BOOKING_SERVICE_DB_URL: "postgresql://postgres:YourSecurePassword123!@$RDS_ENDPOINT:5432/bookings_db?sslmode=require"
  JWT_SECRET: "your-secure-jwt-secret-change-this"
  INTERNAL_API_KEY: "your-secure-api-key-change-this"
"@ | kubectl apply -f -

# Restart services
kubectl rollout restart deployment/user-service deployment/event-service deployment/booking-service deployment/search-service -n bookmyevent
```

---

### Step 3: Setup Custom Domain with SSL

#### 3.1 Get a Domain
Get a free domain from [DNSExit](https://www.dnsexit.com/free-domain/) or use your own.

#### 3.2 Create Route53 Hosted Zone
```powershell
aws route53 create-hosted-zone --name yourdomain.com --caller-reference $(Get-Date -Format "yyyyMMddHHmmss") --region us-east-1
```

**Important:** Copy the nameservers from the output and update them at your domain registrar.

#### 3.3 Request ACM Certificate
```powershell
aws acm request-certificate `
    --domain-name yourdomain.com `
    --subject-alternative-names "*.yourdomain.com" `
    --validation-method DNS `
    --region us-east-1
```

Get validation records:
```powershell
$CERT_ARN = aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='yourdomain.com'].CertificateArn" --output text
aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query "Certificate.DomainValidationOptions"
```

Add validation CNAME records to Route53 (use the Name and Value from above).

Wait for certificate to be issued:
```powershell
aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query "Certificate.Status"
```

#### 3.4 Add DNS Records for Load Balancers

Get load balancer info:
```powershell
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[*].[LoadBalancerName,DNSName,CanonicalHostedZoneId]" --output table
```

Create DNS records pointing to your NLBs:
```powershell
$HOSTED_ZONE_ID = aws route53 list-hosted-zones --query "HostedZones[?Name=='yourdomain.com.'].Id" --output text
$HOSTED_ZONE_ID = $HOSTED_ZONE_ID -replace '/hostedzone/', ''

# Create JSON file for DNS records
@"
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z26RNL4JYFTOTI",
          "DNSName": "YOUR-FRONTEND-NLB-DNS.elb.us-east-1.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z26RNL4JYFTOTI",
          "DNSName": "YOUR-API-NLB-DNS.elb.us-east-1.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
"@ | Out-File -FilePath "dns-records.json" -Encoding utf8

aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file://dns-records.json
```

#### 3.5 Add HTTPS Listeners

Get target group ARNs:
```powershell
aws elbv2 describe-target-groups --region us-east-1 --query "TargetGroups[*].[TargetGroupName,TargetGroupArn]" --output table
```

Create HTTPS listeners:
```powershell
# Frontend HTTPS listener
aws elbv2 create-listener `
    --load-balancer-arn "YOUR-FRONTEND-LB-ARN" `
    --protocol TLS `
    --port 443 `
    --certificates CertificateArn="$CERT_ARN" `
    --default-actions Type=forward,TargetGroupArn="YOUR-FRONTEND-TG-ARN" `
    --region us-east-1

# API HTTPS listener
aws elbv2 create-listener `
    --load-balancer-arn "YOUR-API-LB-ARN" `
    --protocol TLS `
    --port 443 `
    --certificates CertificateArn="$CERT_ARN" `
    --default-actions Type=forward,TargetGroupArn="YOUR-API-TG-ARN" `
    --region us-east-1
```

#### 3.6 Rebuild Frontend with HTTPS API URL

```powershell
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

# Login to ECR
(aws ecr get-login-password --region us-east-1) | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com"

# Build frontend with HTTPS API URL
docker build --build-arg VITE_API_URL=https://api.yourdomain.com -t "$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bookmyevent/frontend:latest" -f Dockerfile-frontend .

# Push to ECR
docker push "$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/bookmyevent/frontend:latest"

# Restart frontend
kubectl rollout restart deployment/frontend -n bookmyevent
```

---

### Step 4: Enable CloudWatch Logs

Create an IRSA-backed Fluent Bit DaemonSet to push pod and node logs to CloudWatch.

**4.1 Create IAM policy for log shipping**
```powershell
@"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy"
      ],
      "Resource": "*"
    }
  ]
}
"@ | Out-File -FilePath cloudwatch-logs-policy.json -Encoding utf8

aws iam create-policy --policy-name bookmyevent-cloudwatch-logs --policy-document file://cloudwatch-logs-policy.json --region us-east-1
```

**4.2 Create IAM service account (IRSA) for Fluent Bit**
```powershell
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

eksctl create iamserviceaccount `
  --name aws-for-fluent-bit `
  --namespace kube-system `
  --cluster bookmyevent-cluster `
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/bookmyevent-cloudwatch-logs `
  --approve `
  --override-existing-serviceaccounts `
  --region us-east-1
```

**4.3 Deploy Fluent Bit with CloudWatch output**
- Update `k8s/logging/cloudwatch-fluent-bit-values.yaml` if you need a different AWS region or log group name (defaults to `us-east-1` and `/eks/bookmyevent/cluster` with 14-day retention).
```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-for-fluent-bit eks/aws-for-fluent-bit `
  --namespace kube-system `
  --create-namespace `
  --values k8s/logging/cloudwatch-fluent-bit-values.yaml
```

**4.4 Validate logs**
```powershell
kubectl get pods -n kube-system -l k8s-app=aws-for-fluent-bit
kubectl logs -n kube-system -l k8s-app=aws-for-fluent-bit --tail=20
aws logs describe-log-groups --log-group-name-prefix "/eks/bookmyevent" --region us-east-1
```

---

## ✅ Verify Deployment

### Test Endpoints
```powershell
# Test frontend
curl https://yourdomain.com

# Test API
curl https://api.yourdomain.com/api/event/events
```

### Check Pods
```powershell
kubectl get pods -n bookmyevent
```

All pods should show `1/1 Running`.

### Test Credentials
- **User:** atlanuser1@mail.com / 11111111
- **Admin:** atlanadmin@mail.com / 11111111

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└─────────────────────┬───────────────────┬───────────────────┘
                      │ HTTPS             │ HTTPS
              ┌───────▼───────┐   ┌───────▼───────┐
              │   Frontend    │   │  API Gateway  │
              │ yourdomain.com│   │api.yourdomain │
              │   (NLB/TLS)   │   │   (NLB/TLS)   │
              └───────┬───────┘   └───────┬───────┘
                      │                   │
┌─────────────────────┴───────────────────┴───────────────────┐
│                     AWS EKS Cluster                          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                NetworkPolicy Applied                  │   │
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
                          │ SSL
              ┌───────────▼───────────┐
              │    AWS RDS PostgreSQL │
              │  (Encrypted at Rest)  │
              │  ├── users_db         │
              │  ├── events_db        │
              │  └── bookings_db      │
              └───────────────────────┘
```

---

## 💰 Cost Estimation

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| EKS Control Plane | Managed | ~$72 |
| EC2 Nodes (3x t3.medium) | On-demand | ~$90 |
| RDS (db.t3.micro) | PostgreSQL | ~$15 |
| Load Balancers (2x NLB) | Network | ~$20 |
| Route53 Hosted Zone | DNS | ~$0.50 |
| **Total** | | **~$200/month** |

---

## 🧹 Cleanup

### Option 1: Automated Cleanup
```powershell
.\scripts\eks\cleanup-all.ps1 -DomainName "yourdomain.com"
```

### Option 2: Manual Cleanup

```powershell
# 1. Delete Kubernetes namespace
kubectl delete namespace bookmyevent

# 2. Wait for load balancers to be deleted
Start-Sleep -Seconds 60

# 3. Delete RDS
aws rds delete-db-instance --db-instance-identifier bookmyevent-rds --skip-final-snapshot --delete-automated-backups --region us-east-1

# 4. Delete Route53 hosted zone (after deleting records)
$ZONE_ID = aws route53 list-hosted-zones --query "HostedZones[?Name=='yourdomain.com.'].Id" --output text
aws route53 delete-hosted-zone --id $ZONE_ID

# 5. Delete ACM certificates
$CERT_ARN = aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[0].CertificateArn" --output text
aws acm delete-certificate --certificate-arn $CERT_ARN --region us-east-1

# 6. Delete ECR repositories
aws ecr delete-repository --repository-name bookmyevent/user-service --region us-east-1 --force
aws ecr delete-repository --repository-name bookmyevent/event-service --region us-east-1 --force
aws ecr delete-repository --repository-name bookmyevent/booking-service --region us-east-1 --force
aws ecr delete-repository --repository-name bookmyevent/search-service --region us-east-1 --force
aws ecr delete-repository --repository-name bookmyevent/frontend --region us-east-1 --force
aws ecr delete-repository --repository-name bookmyevent/init-container --region us-east-1 --force

# 7. Delete EKS cluster (takes 10-15 minutes)
eksctl delete cluster --name bookmyevent-cluster --region us-east-1
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

- [x] Multi-stage Docker builds
- [x] Non-root containers (appuser)
- [x] HEALTHCHECK in Dockerfiles
- [x] Alpine-based minimal images
- [x] .dockerignore created
- [x] Resource limits on pods
- [x] Liveness/Readiness probes
- [x] NetworkPolicy applied
- [x] TLS/HTTPS on load balancers
- [x] Kubernetes Secrets for credentials
- [x] RDS encryption at rest
- [x] SSL database connections
- [x] Private ECR registry

---

**Happy Deploying! 🚀**
