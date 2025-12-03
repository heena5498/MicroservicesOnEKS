# =============================================================================
# Script: cleanup-all.ps1
# Description: Complete cleanup of all AWS resources
# Usage: .\scripts\eks\cleanup-all.ps1 -DomainName "yourdomain.com"
# =============================================================================

param(
    [string]$DomainName = "",
    [string]$Region = "us-east-1",
    [string]$ClusterName = "bookmyevent-cluster"
)

$ErrorActionPreference = "Continue"

Write-Host @"
============================================================
  BookMyEvent - Complete Cleanup Script
============================================================
"@ -ForegroundColor Red

Write-Host "`nWARNING: This will delete ALL resources!" -ForegroundColor Yellow
Write-Host "Press Ctrl+C within 10 seconds to cancel..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Get AWS Account ID
$AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)

# Step 1: Delete Kubernetes namespace (deletes all K8s resources)
Write-Host "`n[1/7] Deleting Kubernetes namespace..." -ForegroundColor Yellow
kubectl delete namespace bookmyevent --ignore-not-found=true
Write-Host "  Namespace deleted" -ForegroundColor Green

# Wait for load balancers to be deleted
Write-Host "  Waiting for load balancers to be cleaned up..." -ForegroundColor White
Start-Sleep -Seconds 60

# Step 2: Delete RDS
Write-Host "`n[2/7] Deleting RDS instance..." -ForegroundColor Yellow
aws rds delete-db-instance `
    --db-instance-identifier bookmyevent-rds `
    --skip-final-snapshot `
    --delete-automated-backups `
    --region $Region 2>$null
Write-Host "  RDS deletion initiated (takes 5-10 minutes)" -ForegroundColor Green

# Step 3: Delete Route53 resources
if ($DomainName) {
    Write-Host "`n[3/7] Deleting Route53 resources..." -ForegroundColor Yellow
    
    # Get hosted zone ID
    $hostedZoneId = aws route53 list-hosted-zones --query "HostedZones[?Name=='$DomainName.'].Id" --output text 2>$null
    
    if ($hostedZoneId) {
        $hostedZoneId = $hostedZoneId -replace '/hostedzone/', ''
        
        # List and delete all non-NS/SOA records
        $records = aws route53 list-resource-record-sets --hosted-zone-id $hostedZoneId --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" --output json | ConvertFrom-Json
        
        foreach ($record in $records) {
            $deleteJson = @{
                Changes = @(
                    @{
                        Action = "DELETE"
                        ResourceRecordSet = $record
                    }
                )
            } | ConvertTo-Json -Depth 10
            
            $deleteJson | Out-File -FilePath "temp-delete.json" -Encoding utf8
            aws route53 change-resource-record-sets --hosted-zone-id $hostedZoneId --change-batch file://temp-delete.json 2>$null
            Remove-Item "temp-delete.json" -Force
        }
        
        # Delete hosted zone
        aws route53 delete-hosted-zone --id $hostedZoneId 2>$null
        Write-Host "  Route53 hosted zone deleted" -ForegroundColor Green
    } else {
        Write-Host "  No hosted zone found for $DomainName" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[3/7] Skipping Route53 (no domain specified)..." -ForegroundColor Yellow
}

# Step 4: Delete ACM certificates
Write-Host "`n[4/7] Deleting ACM certificates..." -ForegroundColor Yellow
$certs = aws acm list-certificates --region $Region --query "CertificateSummaryList[*].CertificateArn" --output text 2>$null
if ($certs) {
    foreach ($cert in $certs.Split()) {
        if ($cert) {
            aws acm delete-certificate --certificate-arn $cert --region $Region 2>$null
            Write-Host "  Deleted certificate: $cert" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  No certificates found" -ForegroundColor Yellow
}

# Step 5: Delete ECR repositories
Write-Host "`n[5/7] Deleting ECR repositories..." -ForegroundColor Yellow
$repos = @("bookmyevent/user-service", "bookmyevent/event-service", "bookmyevent/search-service", "bookmyevent/booking-service", "bookmyevent/init-container", "bookmyevent/frontend")
foreach ($repo in $repos) {
    aws ecr delete-repository --repository-name $repo --region $Region --force 2>$null
    Write-Host "  Deleted: $repo" -ForegroundColor Green
}

# Step 6: Delete RDS subnet group and security group (after RDS is deleted)
Write-Host "`n[6/7] Waiting for RDS deletion to complete..." -ForegroundColor Yellow
Write-Host "  This may take several minutes. You can also delete these manually from AWS Console:" -ForegroundColor White
Write-Host "  - RDS Subnet Group: bookmyevent-rds-subnet-group" -ForegroundColor White
Write-Host "  - Security Group: bookmyevent-rds-sg" -ForegroundColor White

# Step 7: Delete EKS cluster
Write-Host "`n[7/7] Deleting EKS cluster (takes 10-15 minutes)..." -ForegroundColor Yellow
eksctl delete cluster --name $ClusterName --region $Region 2>$null

Write-Host @"

============================================================
  CLEANUP INITIATED
============================================================

Resources being deleted:
  - Kubernetes namespace and all resources
  - AWS RDS PostgreSQL instance
  - Route53 hosted zone and DNS records
  - ACM SSL certificates
  - ECR repositories and images
  - EKS cluster and node groups

Note: Some resources (RDS, EKS) take 10-15 minutes to fully delete.
Check AWS Console to verify complete deletion.

Manual cleanup may be needed for:
  - RDS subnet groups
  - Security groups
  - VPC (if stuck)

============================================================
"@ -ForegroundColor Cyan
