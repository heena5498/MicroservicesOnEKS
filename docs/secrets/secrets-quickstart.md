# 🔐 AWS Secrets Manager - Quick Start

## ⚡ Fast Setup (2 Commands)

```bash
# 1. Create secrets in AWS Secrets Manager
./scripts/secrets/setup-secrets-manager.sh

# 2. Deploy External Secrets Operator
./scripts/secrets/deploy-external-secrets.sh
```

## Verify It's Working

```bash
# Check sync status
kubectl get externalsecrets -n bookmyevent

# Should show:
# NAME                     STATUS   SYNCED   AGE
# database-credentials     Valid    True     30s
# application-secrets      Valid    True     30s

# Check secrets created
kubectl get secrets -n bookmyevent | grep bookmyevent
```

## 📁 Files Created

```
k8s/secrets-management/
├── 00-namespace-and-irsa.yaml          # Service account with IRSA
├── 01-external-secrets-operator.yaml   # External Secrets deployment
├── 02-secret-store.yaml                # Connection to AWS
└── 03-external-secrets.yaml            # Secret mappings

scripts/secrets/
├── setup-secrets-manager.sh            # Setup AWS secrets & IAM
└── deploy-external-secrets.sh          # Deploy operator

secrets-manager-guide.md                # Full documentation
```

## 🔑 What Secrets Are Managed

**AWS Secrets Manager → Kubernetes Secrets**

1. `bookmyevent/database` → `bookmyevent-secrets`
   - POSTGRES_USER
   - POSTGRES_PASSWORD
   - USER_SERVICE_DB_URL
   - EVENT_SERVICE_DB_URL
   - BOOKING_SERVICE_DB_URL

2. `bookmyevent/application` → `bookmyevent-app-secrets`
   - JWT_SECRET
   - INTERNAL_API_KEY

## 🔄 How It Works

```
1. You run setup script
   ↓
2. Secrets stored in AWS Secrets Manager (encrypted)
   ↓
3. External Secrets Operator (with IRSA role)
   ↓
4. Syncs to Kubernetes secrets every 1 hour
   ↓
5. Your pods use Kubernetes secrets (no change needed!)
```

## 🎯 Benefits

**No secrets in Git** - Everything in AWS Secrets Manager
**Auto-rotation ready** - Change in AWS, auto-syncs to K8s
**Secure authentication** - IRSA (no API keys needed)
**Audit trail** - CloudTrail logs all secret access
**Encryption at rest** - AWS KMS encryption
**Auto-refresh** - Secrets sync every 1 hour

## 🔧 Common Operations

### Rotate Database Password

```bash
# Update in AWS
aws secretsmanager update-secret \
  --secret-id bookmyevent/database \
  --secret-string '{"username":"postgres","password":"NEW_PASSWORD",...}'

# Wait up to 1 hour or force refresh
kubectl delete externalsecret database-credentials -n bookmyevent
kubectl apply -f k8s/secrets-management/03-external-secrets.yaml

# Restart database-dependent services
kubectl rollout restart deployment/user-service -n bookmyevent
kubectl rollout restart deployment/postgres -n bookmyevent
```

### View Secrets

```bash
# In AWS
aws secretsmanager get-secret-value \
  --secret-id bookmyevent/database \
  --region us-east-1 \
  --query SecretString --output text | jq .

# In Kubernetes (base64 encoded)
kubectl get secret bookmyevent-secrets -n bookmyevent -o yaml

# Decode specific key
kubectl get secret bookmyevent-secrets -n bookmyevent \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

## 🆘 Troubleshooting

### ExternalSecret not syncing?

```bash
# Check status
kubectl describe externalsecret database-credentials -n bookmyevent

# Check operator logs
kubectl logs deployment/external-secrets -n bookmyevent

# Verify IRSA role
kubectl get sa external-secrets-sa -n bookmyevent -o yaml
```

### "Access Denied" errors?

```bash
# Verify IAM policy exists
aws iam list-policies --query 'Policies[?PolicyName==`BookMyEventSecretsManagerPolicy`]'

# Re-create IRSA role
eksctl create iamserviceaccount \
  --name external-secrets-sa \
  --namespace bookmyevent \
  --cluster bookmyevent-cluster \
  --region us-east-1 \
  --role-name BookMyEventExternalSecretsRole \
  --attach-policy-arn <POLICY_ARN> \
  --approve \
  --override-existing-serviceaccounts
```

## 💡 Pro Tips

1. **Test in staging first** before updating production secrets
2. **Use AWS Secrets Manager rotation** for automatic password changes
3. **Monitor CloudTrail** for unauthorized secret access attempts
4. **Set up SNS alerts** for secret access failures
5. **Keep backup** of secrets in secure offline storage

## 📚 Full Documentation

See `secrets-manager-guide.md` for:
- Detailed architecture
- Manual operations
- Security best practices
- Cost breakdown
- Migration guide

## 💰 Cost

~$0.81/month for 2 secrets with hourly refresh

---

**Need help?** Check `secrets-manager-guide.md` or run:
```bash
kubectl describe externalsecret <name> -n bookmyevent
kubectl logs deployment/external-secrets -n bookmyevent
```
