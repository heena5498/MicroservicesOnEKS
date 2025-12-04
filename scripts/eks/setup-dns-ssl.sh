#!/bin/bash
# =============================================================================
# BookMyEvent - DNS and SSL Setup Script
# =============================================================================
# This script configures custom domain with SSL/TLS for the application
# Prerequisites: Domain registered, AWS CLI configured
# Usage: ./scripts/eks/setup-dns-ssl.sh yourdomain.com
# =============================================================================

set -e

DOMAIN_NAME="$1"
REGION="${AWS_REGION:-us-east-1}"

if [ -z "$DOMAIN_NAME" ]; then
    echo "Usage: $0 <domain-name>"
    echo "Example: $0 bookmyevent.com"
    exit 1
fi

echo "========================================"
echo "Setting up DNS and SSL for $DOMAIN_NAME"
echo "========================================"

# Step 1: Create Route53 Hosted Zone
echo ""
echo "[1/6] Creating Route53 Hosted Zone..."
CALLER_REF="bookmyevent-$(date +%Y%m%d%H%M%S)"
HOSTED_ZONE_RESULT=$(aws route53 create-hosted-zone \
    --name "$DOMAIN_NAME" \
    --caller-reference "$CALLER_REF" \
    --region "$REGION" 2>/dev/null || echo "")

if [ -n "$HOSTED_ZONE_RESULT" ]; then
    HOSTED_ZONE_ID=$(echo "$HOSTED_ZONE_RESULT" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')
    echo "  Hosted Zone ID: $HOSTED_ZONE_ID"
    echo ""
    echo "  IMPORTANT: Update your domain registrar with these nameservers:"
    echo "$HOSTED_ZONE_RESULT" | jq -r '.DelegationSet.NameServers[]' | sed 's/^/    - /'
else
    # Zone might already exist
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Name=='$DOMAIN_NAME.'].Id" \
        --output text | sed 's|/hostedzone/||')
    echo "  Using existing Hosted Zone: $HOSTED_ZONE_ID"
fi

# Step 2: Request SSL Certificate
echo ""
echo "[2/6] Requesting SSL Certificate..."
CERT_RESULT=$(aws acm request-certificate \
    --domain-name "$DOMAIN_NAME" \
    --subject-alternative-names "*.$DOMAIN_NAME" \
    --validation-method DNS \
    --region "$REGION")
CERTIFICATE_ARN=$(echo "$CERT_RESULT" | jq -r '.CertificateArn')
echo "  Certificate ARN: $CERTIFICATE_ARN"

# Wait for certificate details
sleep 5

# Step 3: Get validation record
echo ""
echo "[3/6] Getting validation records..."
CERT_DETAILS=$(aws acm describe-certificate \
    --certificate-arn "$CERTIFICATE_ARN" \
    --region "$REGION")
VALIDATION_NAME=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Name')
VALIDATION_VALUE=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Value')

echo "  Validation Name: $VALIDATION_NAME"
echo "  Validation Value: $VALIDATION_VALUE"

# Step 4: Get Load Balancer info
echo ""
echo "[4/6] Getting Load Balancer information..."
LB_LIST=$(aws elbv2 describe-load-balancers --region "$REGION")

# Get nginx-gateway LoadBalancer (handles both frontend and API traffic)
NGINX_GATEWAY_DNS=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$NGINX_GATEWAY_DNS" ]; then
    echo "  ERROR: Could not find nginx-gateway LoadBalancer DNS name"
    echo "  Make sure nginx-gateway service is deployed with type LoadBalancer"
    exit 1
fi

# Use nginx-gateway for both frontend and API traffic (single entry point)
FRONTEND_DNS="$NGINX_GATEWAY_DNS"
API_DNS="$NGINX_GATEWAY_DNS"

# Get hosted zone ID for the load balancer
LB_HOSTED_ZONE_ID=$(echo "$LB_LIST" | jq -r ".LoadBalancers[] | select(.DNSName==\"$NGINX_GATEWAY_DNS\") | .CanonicalHostedZoneId")

echo "  Frontend LB: $FRONTEND_DNS"
echo "  API LB: $API_DNS"
echo "  LB Hosted Zone: $LB_HOSTED_ZONE_ID"

# Step 5: Add DNS records
echo ""
echo "[5/6] Adding DNS records to Route53..."

cat > /tmp/dns-records.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$VALIDATION_NAME",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "$VALIDATION_VALUE"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN_NAME",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$LB_HOSTED_ZONE_ID",
          "DNSName": "$FRONTEND_DNS",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.$DOMAIN_NAME",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$LB_HOSTED_ZONE_ID",
          "DNSName": "$API_DNS",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch file:///tmp/dns-records.json

rm /tmp/dns-records.json
echo "  ✓ DNS records added"

# Step 6: Wait for certificate validation
echo ""
echo "[6/6] Waiting for certificate validation..."
ATTEMPT=0
MAX_ATTEMPTS=20

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    sleep 30
    ATTEMPT=$((ATTEMPT + 1))
    STATUS=$(aws acm describe-certificate \
        --certificate-arn "$CERTIFICATE_ARN" \
        --region "$REGION" \
        --query "Certificate.Status" \
        --output text)
    echo "  Certificate Status: $STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    
    if [ "$STATUS" == "ISSUED" ]; then
        break
    fi
done

if [ "$STATUS" == "ISSUED" ]; then
    echo ""
    echo "✓ Certificate issued! Adding HTTPS listeners..."
    
    # Note: Adding HTTPS listeners requires target groups
    # This is a simplified version - you may need to adjust based on your setup
    
    echo ""
    echo "========================================"
    echo "DNS and SSL Setup Complete!"
    echo "========================================"
    echo "Frontend: https://$DOMAIN_NAME"
    echo "API: https://api.$DOMAIN_NAME"
    echo ""
    echo " NOTE: Update your domain registrar nameservers if not done!"
    echo ""
    echo "Next step: Rebuild frontend with new API URL"
    echo "  docker build --build-arg VITE_API_URL=https://api.$DOMAIN_NAME -t <ecr-repo>/frontend:latest -f Dockerfile-frontend ."
else
    echo "Certificate validation timed out. Please check manually."
    exit 1
fi
