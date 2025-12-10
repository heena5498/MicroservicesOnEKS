# Backup and Restore Runbook

## Overview
This document provides procedures for backing up and restoring data for the BookMyEvent application running on EKS.

---

## Components Requiring Backup

### 1. RDS PostgreSQL Database  **MOST CRITICAL**
- **Data**: User accounts, events, bookings
- **Backup Method**: AWS RDS Automated Snapshots
- **Retention**: 7-35 days (configurable)
- **RPO (Recovery Point Objective)**: 5 minutes (transaction logs)
- **RTO (Recovery Time Objective)**: 15-30 minutes

### 2. Elasticsearch Indices
- **Data**: Indexed events for search
- **Backup Method**: Elasticsearch Snapshots to S3
- **Retention**: 14 days
- **Note**: Can be rebuilt from RDS if needed

### 3. Kubernetes Resources
- **Data**: Deployments, ConfigMaps, Secrets
- **Backup Method**: Git repository + Helm charts
- **Retention**: Indefinite (version controlled)

### 4. Application Logs
- **Data**: CloudWatch Logs
- **Backup Method**: CloudWatch retention + S3 export
- **Retention**: 14 days

---

## 1. RDS PostgreSQL Backup Procedures

### 1.1 Verify Automated Backups

Check that automated backups are enabled:

\`\`\`bash
# Describe RDS instance
aws rds describe-db-instances \\
  --db-instance-identifier bookmyevent-rds \\
  --region us-east-1 \\
  --query 'DBInstances[0].{BackupRetention:BackupRetentionPeriod,BackupWindow:PreferredBackupWindow,Encrypted:StorageEncrypted}'

# Expected output:
# {
#     "BackupRetention": 7,
#     "BackupWindow": "03:00-04:00",
#     "Encrypted": true
# }
\`\`\`

### 1.2 Create Manual Snapshot

Create an on-demand backup before major changes:

\`\`\`bash
# Create manual snapshot
aws rds create-db-snapshot \\
  --db-instance-identifier bookmyevent-rds \\
  --db-snapshot-identifier bookmyevent-manual-$(date +%Y%m%d-%H%M%S) \\
  --region us-east-1

# Monitor snapshot creation
aws rds describe-db-snapshots \\
  --db-snapshot-identifier bookmyevent-manual-<timestamp> \\
  --region us-east-1 \\
  --query 'DBSnapshots[0].{Status:Status,Progress:PercentProgress}'
\`\`\`

### 1.3 List Available Snapshots

\`\`\`bash
# List all snapshots
aws rds describe-db-snapshots \\
  --db-instance-identifier bookmyevent-rds \\
  --region us-east-1 \\
  --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \\
  --output table
\`\`\`

### 1.4 Restore from RDS Snapshot

**⚠️ CAUTION: This creates a NEW RDS instance**

\`\`\`bash
# 1. Restore to new instance
aws rds restore-db-instance-from-db-snapshot \\
  --db-instance-identifier bookmyevent-rds-restored \\
  --db-snapshot-identifier <snapshot-id> \\
  --db-instance-class db.t3.micro \\
  --vpc-security-group-ids sg-xxxxxxxxx \\
  --db-subnet-group-name bookmyevent-db-subnet \\
  --publicly-accessible false \\
  --region us-east-1

# 2. Wait for instance to be available (10-15 minutes)
aws rds wait db-instance-available \\
  --db-instance-identifier bookmyevent-rds-restored \\
  --region us-east-1

# 3. Get new endpoint
aws rds describe-db-instances \\
  --db-instance-identifier bookmyevent-rds-restored \\
  --region us-east-1 \\
  --query 'DBInstances[0].Endpoint.Address' \\
  --output text

# 4. Update Kubernetes secret with new endpoint
kubectl create secret generic bookmyevent-secrets \\
  --from-literal=DB_HOST=<new-rds-endpoint> \\
  --from-literal=DB_PASSWORD=<password> \\
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Restart pods to use new connection
kubectl rollout restart deployment/user-service -n bookmyevent
kubectl rollout restart deployment/event-service -n bookmyevent
kubectl rollout restart deployment/booking-service -n bookmyevent

# 6. Verify connectivity
kubectl logs -n bookmyevent deployment/user-service --tail=20
\`\`\`

---

## 2. Elasticsearch Backup Procedures

### 2.1 Configure S3 Snapshot Repository

\`\`\`bash
# Port-forward to Elasticsearch
kubectl port-forward -n bookmyevent svc/elasticsearch 9200:9200 &

# Create S3 bucket for snapshots (if not exists)
aws s3 mb s3://bookmyevent-es-snapshots-$(aws sts get-caller-identity --query Account --output text) --region us-east-1

# Register snapshot repository
curl -X PUT "localhost:9200/_snapshot/s3_backup" -H 'Content-Type: application/json' -d'
{
  "type": "s3",
  "settings": {
    "bucket": "bookmyevent-es-snapshots-<account-id>",
    "region": "us-east-1",
    "base_path": "elasticsearch-backups"
  }
}
'
\`\`\`

### 2.2 Create Elasticsearch Snapshot

\`\`\`bash
# Create snapshot
curl -X PUT "localhost:9200/_snapshot/s3_backup/snapshot_$(date +%Y%m%d_%H%M%S)?wait_for_completion=false" -H 'Content-Type: application/json' -d'
{
  "indices": "events,events-index",
  "ignore_unavailable": true,
  "include_global_state": false
}
'

# Check snapshot status
curl -X GET "localhost:9200/_snapshot/s3_backup/_all?pretty"
\`\`\`

### 2.3 Restore Elasticsearch Snapshot

\`\`\`bash
# Close indices before restore
curl -X POST "localhost:9200/events/_close?pretty"

# Restore snapshot
curl -X POST "localhost:9200/_snapshot/s3_backup/<snapshot-name>/_restore?pretty" -H 'Content-Type: application/json' -d'
{
  "indices": "events",
  "ignore_unavailable": true,
  "include_global_state": false
}
'

# Monitor restore progress
curl -X GET "localhost:9200/_recovery?pretty"

# Open indices after restore
curl -X POST "localhost:9200/events/_open?pretty"
\`\`\`

---

## 3. Kubernetes Resources Backup

### 3.1 Export All Resources

\`\`\`bash
# Create backup directory
mkdir -p backups/k8s-$(date +%Y%m%d)
cd backups/k8s-$(date +%Y%m%d)

# Export all resources from bookmyevent namespace
kubectl get all,configmap,secret,ingress,networkpolicy,pvc -n bookmyevent -o yaml > bookmyevent-full-backup.yaml

# Export individual resource types
kubectl get deployments -n bookmyevent -o yaml > deployments.yaml
kubectl get services -n bookmyevent -o yaml > services.yaml
kubectl get configmaps -n bookmyevent -o yaml > configmaps.yaml
kubectl get secrets -n bookmyevent -o yaml > secrets.yaml
kubectl get ingress -n bookmyevent -o yaml > ingress.yaml

# Create tarball
cd ../..
tar -czf k8s-backup-$(date +%Y%m%d).tar.gz backups/k8s-$(date +%Y%m%d)

echo "✅ Kubernetes backup created: k8s-backup-$(date +%Y%m%d).tar.gz"
\`\`\`

### 3.2 Restore Kubernetes Resources

\`\`\`bash
# Extract backup
tar -xzf k8s-backup-<date>.tar.gz

# Restore resources
kubectl apply -f backups/k8s-<date>/bookmyevent-full-backup.yaml

# Verify
kubectl get all -n bookmyevent
\`\`\`

---

## 4. Using Velero (Optional - Advanced)

### 4.1 Install Velero

\`\`\`bash
# Download Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xzf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Create S3 bucket for Velero
aws s3 mb s3://bookmyevent-velero-backups-$(aws sts get-caller-identity --query Account --output text) --region us-east-1

# Install Velero in cluster
velero install \\
  --provider aws \\
  --plugins velero/velero-plugin-for-aws:v1.8.0 \\
  --bucket bookmyevent-velero-backups-<account-id> \\
  --backup-location-config region=us-east-1 \\
  --snapshot-location-config region=us-east-1 \\
  --use-node-agent
\`\`\`

### 4.2 Create Velero Backup

\`\`\`bash
# Backup entire namespace
velero backup create bookmyevent-backup-$(date +%Y%m%d) \\
  --include-namespaces bookmyevent \\
  --wait

# Backup with specific resources
velero backup create bookmyevent-full-$(date +%Y%m%d) \\
  --include-namespaces bookmyevent \\
  --include-cluster-resources=true \\
  --snapshot-volumes=true

# Check backup status
velero backup describe bookmyevent-backup-<date>
velero backup logs bookmyevent-backup-<date>
\`\`\`

### 4.3 Restore from Velero

\`\`\`bash
# List available backups
velero backup get

# Restore from backup
velero restore create --from-backup bookmyevent-backup-<date>

# Monitor restore
velero restore describe <restore-name>

# Check restored resources
kubectl get all -n bookmyevent
\`\`\`

---

## 5. Disaster Recovery Scenarios

### Scenario 1: Accidental Data Deletion in RDS

**Problem**: Critical data deleted from database

**Recovery Steps**:
1. Identify the last good snapshot before deletion
2. Restore RDS from snapshot (creates new instance)
3. Update connection strings in Kubernetes
4. Verify data integrity
5. Switch traffic to restored database

**Time**: 20-30 minutes

---

### Scenario 2: Elasticsearch Cluster Failure

**Problem**: Elasticsearch pod corrupted or data lost

**Recovery Steps**:
1. If snapshot exists, restore from S3
2. If no snapshot, rebuild index from RDS:
   \`\`\`bash
   # Trigger reindex from search-service
   kubectl exec -it deployment/search-service -n bookmyevent -- sh
   curl -X POST localhost:8083/admin/reindex
   \`\`\`

**Time**: 5-60 minutes (depending on data size)

---

### Scenario 3: Complete Namespace Deletion

**Problem**: Entire bookmyevent namespace accidentally deleted

**Recovery Steps**:
1. Restore from Git repository (preferred):
   \`\`\`bash
   helm upgrade --install bookmyevent ./helm -n bookmyevent --create-namespace
   \`\`\`

2. Or restore from Velero backup:
   \`\`\`bash
   velero restore create --from-backup bookmyevent-backup-latest
   \`\`\`

3. Restore RDS data if needed

**Time**: 10-20 minutes

---

## 6. Backup Schedule Recommendations

| Component | Frequency | Retention | Method |
|-----------|-----------|-----------|--------|
| RDS | Daily (automated) | 7 days | AWS RDS Snapshots |
| RDS | Weekly (manual) | 30 days | Manual snapshots before changes |
| Elasticsearch | Daily | 14 days | S3 snapshots |
| K8s Resources | On change | Indefinite | Git commits |
| Full Velero | Weekly | 4 weeks | Velero backup |

---

## 7. Testing Backup & Restore

### 7.1 Quarterly DR Drill

\`\`\`bash
# 1. Create test namespace
kubectl create namespace bookmyevent-dr-test

# 2. Restore backup to test namespace
velero restore create dr-test-$(date +%Y%m%d) \\
  --from-backup bookmyevent-backup-latest \\
  --namespace-mappings bookmyevent:bookmyevent-dr-test

# 3. Verify all pods start
kubectl get pods -n bookmyevent-dr-test

# 4. Test API endpoints
# 5. Clean up
kubectl delete namespace bookmyevent-dr-test
\`\`\`

---

## 8. Monitoring and Alerts

- **CloudWatch Alarm**: Alert if RDS snapshot age > 25 hours
- **Prometheus Alert**: Alert if backup job fails
- **Weekly Report**: Email with backup status

---

## 9. Important Notes

⚠️ **Before Any Major Change**:
- [ ] Create manual RDS snapshot
- [ ] Create Elasticsearch snapshot
- [ ] Commit all Kubernetes manifests to Git
- [ ] Verify snapshots are available

⚠️ **Recovery Checklist**:
- [ ] Document incident timeline
- [ ] Identify root cause
- [ ] Restore from appropriate backup
- [ ] Verify data integrity
- [ ] Test application functionality
- [ ] Update runbook with lessons learned

---

## 10. Contact Information

- **Incident Commander**: [Team Lead]
- **Database Admin**: [DBA Contact]
- **AWS Support**: Support case via AWS Console
- **On-Call Rotation**: See PagerDuty schedule
