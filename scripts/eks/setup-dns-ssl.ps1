# =============================================================================
# BookMyEvent - DNS and SSL Setup Script
# =============================================================================
# This script configures custom domain with SSL/TLS for the application
# Prerequisites: Domain registered, AWS CLI configured
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    [string]$Region = "us-east-1"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting up DNS and SSL for $DomainName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Step 1: Create Route53 Hosted Zone
Write-Host "`n[1/6] Creating Route53 Hosted Zone..." -ForegroundColor Yellow
$callerRef = "bookmyevent-$(Get-Date -Format 'yyyyMMddHHmmss')"
$hostedZoneResult = aws route53 create-hosted-zone --name $DomainName --caller-reference $callerRef --region $Region 2>&1 | ConvertFrom-Json

if ($hostedZoneResult.HostedZone) {
    $HostedZoneId = $hostedZoneResult.HostedZone.Id -replace '/hostedzone/', ''
    $NameServers = $hostedZoneResult.DelegationSet.NameServers
    Write-Host "  Hosted Zone ID: $HostedZoneId" -ForegroundColor Green
    Write-Host "`n  IMPORTANT: Update your domain registrar with these nameservers:" -ForegroundColor Red
    $NameServers | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
} else {
    # Zone might already exist
    $HostedZoneId = aws route53 list-hosted-zones --query "HostedZones[?Name=='$DomainName.'].Id" --output text | ForEach-Object { $_ -replace '/hostedzone/', '' }
    Write-Host "  Using existing Hosted Zone: $HostedZoneId" -ForegroundColor Green
}

# Step 2: Request SSL Certificate
Write-Host "`n[2/6] Requesting SSL Certificate..." -ForegroundColor Yellow
$certResult = aws acm request-certificate --domain-name $DomainName --subject-alternative-names "*.$DomainName" --validation-method DNS --region $Region | ConvertFrom-Json
$CertificateArn = $certResult.CertificateArn
Write-Host "  Certificate ARN: $CertificateArn" -ForegroundColor Green

# Wait a moment for certificate to be created
Start-Sleep -Seconds 5

# Step 3: Get validation record
Write-Host "`n[3/6] Getting validation records..." -ForegroundColor Yellow
$certDetails = aws acm describe-certificate --certificate-arn $CertificateArn --region $Region | ConvertFrom-Json
$validationRecord = $certDetails.Certificate.DomainValidationOptions[0].ResourceRecord

Write-Host "  Validation Name: $($validationRecord.Name)" -ForegroundColor Gray
Write-Host "  Validation Value: $($validationRecord.Value)" -ForegroundColor Gray

# Step 4: Get Load Balancer info
Write-Host "`n[4/6] Getting Load Balancer information..." -ForegroundColor Yellow
$loadBalancers = aws elbv2 describe-load-balancers --region $Region | ConvertFrom-Json

$frontendLB = $loadBalancers.LoadBalancers | Where-Object { $_.LoadBalancerName -match "a03a260c3f" }
$apiLB = $loadBalancers.LoadBalancers | Where-Object { $_.LoadBalancerName -match "aa30bb4098" }

if (-not $frontendLB -or -not $apiLB) {
    $frontendLB = $loadBalancers.LoadBalancers[0]
    $apiLB = $loadBalancers.LoadBalancers[1]
}

$LBHostedZoneId = $frontendLB.CanonicalHostedZoneId
$FrontendDNS = $frontendLB.DNSName
$ApiDNS = $apiLB.DNSName

Write-Host "  Frontend LB: $FrontendDNS" -ForegroundColor Green
Write-Host "  API LB: $ApiDNS" -ForegroundColor Green

# Step 5: Add DNS records
Write-Host "`n[5/6] Adding DNS records to Route53..." -ForegroundColor Yellow

$dnsRecords = @{
    Changes = @(
        @{
            Action = "UPSERT"
            ResourceRecordSet = @{
                Name = $validationRecord.Name
                Type = "CNAME"
                TTL = 300
                ResourceRecords = @(@{Value = $validationRecord.Value})
            }
        },
        @{
            Action = "UPSERT"
            ResourceRecordSet = @{
                Name = $DomainName
                Type = "A"
                AliasTarget = @{
                    HostedZoneId = $LBHostedZoneId
                    DNSName = $FrontendDNS
                    EvaluateTargetHealth = $false
                }
            }
        },
        @{
            Action = "UPSERT"
            ResourceRecordSet = @{
                Name = "api.$DomainName"
                Type = "A"
                AliasTarget = @{
                    HostedZoneId = $LBHostedZoneId
                    DNSName = $ApiDNS
                    EvaluateTargetHealth = $false
                }
            }
        }
    )
}

$dnsRecords | ConvertTo-Json -Depth 10 | Out-File -FilePath "dns-records-temp.json" -Encoding UTF8
aws route53 change-resource-record-sets --hosted-zone-id $HostedZoneId --change-batch file://dns-records-temp.json
Remove-Item "dns-records-temp.json" -ErrorAction SilentlyContinue

Write-Host "  DNS records added" -ForegroundColor Green

# Step 6: Wait for certificate validation
Write-Host "`n[6/6] Waiting for certificate validation..." -ForegroundColor Yellow
$attempt = 0
$maxAttempts = 20

do {
    Start-Sleep -Seconds 30
    $attempt++
    $status = aws acm describe-certificate --certificate-arn $CertificateArn --region $Region --query "Certificate.Status" --output text
    Write-Host "  Certificate Status: $status (attempt $attempt/$maxAttempts)" -ForegroundColor Gray
} while ($status -eq "PENDING_VALIDATION" -and $attempt -lt $maxAttempts)

if ($status -eq "ISSUED") {
    Write-Host "`nCertificate issued! Adding HTTPS listeners..." -ForegroundColor Green
    
    # Get target groups
    $targetGroups = aws elbv2 describe-target-groups --region $Region | ConvertFrom-Json
    $frontendTG = ($targetGroups.TargetGroups | Where-Object { $_.TargetGroupName -match "frontend" }).TargetGroupArn
    $apiTG = ($targetGroups.TargetGroups | Where-Object { $_.TargetGroupName -match "nginxgat" }).TargetGroupArn
    
    # Add HTTPS listeners
    aws elbv2 create-listener --load-balancer-arn $frontendLB.LoadBalancerArn --protocol TLS --port 443 --certificates CertificateArn=$CertificateArn --default-actions Type=forward,TargetGroupArn=$frontendTG --region $Region 2>$null
    aws elbv2 create-listener --load-balancer-arn $apiLB.LoadBalancerArn --protocol TLS --port 443 --certificates CertificateArn=$CertificateArn --default-actions Type=forward,TargetGroupArn=$apiTG --region $Region 2>$null
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "DNS and SSL Setup Complete!" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Frontend: https://$DomainName" -ForegroundColor White
    Write-Host "API: https://api.$DomainName" -ForegroundColor White
    Write-Host "`nNOTE: Update your domain registrar nameservers if not done!" -ForegroundColor Yellow
    Write-Host "`nNext step: Rebuild frontend with new API URL" -ForegroundColor Yellow
    Write-Host "  docker build --build-arg VITE_API_URL=https://api.$DomainName -t <ecr-repo>/frontend:latest -f Dockerfile-frontend frontend/" -ForegroundColor Gray
} else {
    Write-Host "Certificate validation timed out. Please check manually." -ForegroundColor Red
}
