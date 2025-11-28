# SSL/TLS Setup Guide for BookMyEvent

This guide explains how to set up HTTPS/SSL for your BookMyEvent application on AWS EKS.

## 📋 Current Setup

- **Load Balancer Type**: Network Load Balancer (NLB)
- **Issue**: NLBs don't support SSL termination
- **Solution**: Switch to Application Load Balancer (ALB) with SSL termination

## 🎯 Approach: Use ALB with AWS Certificate Manager (ACM)

### Option 1: Use AWS Load Balancer Controller with ALB Ingress (Recommended)
### Option 2: Switch Service type from NLB to ALB (Simpler)

---

## 📝 Step-by-Step Process

### Step 1: Request SSL Certificate from ACM
**Time**: 5-10 minutes

1. Request certificate in AWS Certificate Manager:
   ```powershell
   # Request certificate for your domain
   aws acm request-certificate `
     --domain-name bookmyevents.work.gd `
     --subject-alternative-names "*.bookmyevents.work.gd" `
     --validation-method DNS `
     --region us-east-1
   ```

2. Get certificate ARN and validation records
3. Add DNS validation records to Route 53
4. Wait for certificate to be validated (~5-10 minutes)

**What you need:**
- Certificate ARN (will be provided after request)
- DNS validation records (CNAME records to add to Route 53)

---

### Step 2: Install AWS Load Balancer Controller
**Time**: 10-15 minutes

1. Create IAM policy and service account:
   ```powershell
   # Create IAM OIDC provider (if not exists)
   eksctl utils associate-iam-oidc-provider --cluster bookmyevent-cluster --region us-east-1 --approve
   
   # Create IAM policy for Load Balancer Controller
   # (Download policy from AWS GitHub)
   
   # Create service account
   eksctl create iamserviceaccount `
     --cluster=bookmyevent-cluster `
     --namespace=kube-system `
     --name=aws-load-balancer-controller `
     --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy `
     --override-existing-serviceaccounts `
     --approve
   ```

2. Install AWS Load Balancer Controller via Helm:
   ```powershell
   # Add Helm repo
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   
   # Install controller
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller `
     -n kube-system `
     --set clusterName=bookmyevent-cluster `
     --set serviceAccount.create=false `
     --set serviceAccount.name=aws-load-balancer-controller
   ```

**Alternative (Simpler)**: Use ALB directly with Service annotations (Step 2B)

---

### Step 2B (Alternative): Switch Services to ALB
**Time**: 5 minutes (if skipping Load Balancer Controller)

Modify service annotations to use ALB instead of NLB:
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-type: "external"
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "<CERTIFICATE_ARN>"
  service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
  service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
  service.beta.kubernetes.io/aws-load-balancer-backend-port: "80"
```

---

### Step 3: Update Service Manifests
**Time**: 5 minutes

**For Frontend Service (`k8s/services/frontend.yaml`):**
- Change annotation from `nlb` to ALB configuration
- Add SSL certificate ARN
- Add port 443 for HTTPS
- Keep port 80 for HTTP → HTTPS redirect

**For API Gateway Service (`k8s/services/nginx-gateway.yaml`):**
- Same changes as frontend

---

### Step 4: Create/Update Ingress Resources (If using Ingress)
**Time**: 10 minutes

Create Ingress resources that:
- Use ALB class
- Reference ACM certificate
- Configure SSL redirect (HTTP → HTTPS)
- Map domains to services

Example Ingress:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bookmyevent-ingress
  namespace: bookmyevent
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: <CERTIFICATE_ARN>
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
spec:
  rules:
    - host: bookmyevents.work.gd
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80
    - host: api.bookmyevents.work.gd
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-gateway
                port:
                  number: 80
```

---

### Step 5: Update DNS Records
**Time**: 2-5 minutes

1. Get new ALB DNS name (from Ingress or Service)
2. Update Route 53 records to point to ALB instead of NLB
3. Wait for DNS propagation (5-15 minutes)

---

### Step 6: Update Frontend API URL
**Time**: 5 minutes

1. Update frontend build to use HTTPS API URL:
   ```powershell
   docker build --build-arg VITE_API_URL="https://api.bookmyevents.work.gd" ...
   ```

2. Rebuild and push frontend image
3. Restart frontend deployment

---

## ⏱️ Total Time Estimate

| Step | Time |
|------|------|
| Request ACM Certificate | 5-10 min |
| Certificate Validation | 5-10 min |
| Install Load Balancer Controller | 10-15 min |
| Update Service Manifests | 5 min |
| Create/Update Ingress | 10 min |
| DNS Updates | 2-5 min |
| Frontend Rebuild | 5 min |
| DNS Propagation | 5-15 min |
| **TOTAL** | **47-75 minutes** |

**Realistic Estimate**: **1-1.5 hours** (including waiting times)

---

## 📋 Prerequisites Checklist

Before starting:
- [ ] Application is deployed and running
- [ ] Domain is configured in Route 53
- [ ] Route 53 hosted zone is set up
- [ ] You have AWS CLI configured
- [ ] kubectl is configured for your cluster
- [ ] Helm is installed (if using Load Balancer Controller)

---

## 🔧 Required Tools

- AWS CLI
- kubectl
- Helm (for Load Balancer Controller installation)
- Docker (for frontend rebuild)

---

## 💰 Cost Impact

- **ACM Certificate**: FREE
- **ALB**: ~$22/month (vs NLB ~$20/month)
- **Additional cost**: ~$2/month

---

## 📝 Files to Modify

1. `k8s/services/frontend.yaml` - Change to ALB with SSL
2. `k8s/services/nginx-gateway.yaml` - Change to ALB with SSL
3. Create new `k8s/ingress/frontend-ingress.yaml` (if using Ingress)
4. Create new `k8s/ingress/api-ingress.yaml` (if using Ingress)
5. Frontend Dockerfile - Update API URL to HTTPS

---

## ✅ Verification Steps

After setup:

1. Check certificate status:
   ```powershell
   aws acm list-certificates --region us-east-1
   ```

2. Check ALB status:
   ```powershell
   kubectl get ingress -n bookmyevent
   aws elbv2 describe-load-balancers --region us-east-1
   ```

3. Test HTTPS:
   ```powershell
   curl -I https://bookmyevents.work.gd
   curl -I https://api.bookmyevents.work.gd
   ```

4. Test HTTP redirect:
   ```powershell
   curl -I http://bookmyevents.work.gd
   # Should redirect to HTTPS
   ```

---

## 🎯 Recommended Approach

**For simplicity**: Use ALB directly with Service annotations (Step 2B)
- Faster setup
- No need for Ingress Controller
- Easier to understand
- Less moving parts

**For flexibility**: Use Ingress with AWS Load Balancer Controller
- More features
- Better for complex routing
- Easier SSL management
- Industry standard approach

---

## 🆘 Troubleshooting

**Certificate validation fails:**
- Check DNS records are correctly added to Route 53
- Wait longer (can take up to 30 minutes)

**ALB doesn't provision:**
- Check IAM permissions
- Verify service account is created
- Check Load Balancer Controller logs

**HTTPS not working:**
- Verify certificate ARN is correct
- Check ALB listener configuration
- Verify DNS points to ALB

**HTTP not redirecting:**
- Check redirect annotation is set
- Verify listener rules on ALB

---

## 📚 Additional Resources

- AWS Certificate Manager: https://aws.amazon.com/certificate-manager/
- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- ALB Ingress: https://kubernetes-sigs.github.io/aws-load-balancer-controller/guide/ingress/


