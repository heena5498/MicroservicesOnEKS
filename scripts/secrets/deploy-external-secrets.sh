#!/bin/bash
# =============================================================================
# Script: deploy-external-secrets.sh
# Description: Deploys External Secrets Operator and syncs AWS secrets
# Usage: ./scripts/secrets/deploy-external-secrets.sh
# =============================================================================

set -e

echo "============================================================"
echo "  Deploying External Secrets Operator"
echo "============================================================"

# Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"

echo ""
echo "[1/4] Installing External Secrets CRDs..."
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml

echo ""
echo "[2/4] Waiting for CRDs to be established..."
sleep 5

echo ""
echo "[3/4] Deploying External Secrets Operator..."
kubectl apply -f k8s/secrets-management/

echo ""
echo "[4/4] Waiting for External Secrets Operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets -n bookmyevent || true

echo ""
echo "Checking External Secrets status..."
sleep 10

echo ""
echo "ExternalSecrets status:"
kubectl get externalsecrets -n bookmyevent

echo ""
echo "Synced Kubernetes Secrets:"
kubectl get secrets -n bookmyevent | grep -E "bookmyevent-secrets|bookmyevent-app-secrets"

echo ""
echo "============================================================"
echo "  External Secrets Operator Deployed!"
echo "============================================================"
echo ""
echo "Your secrets from AWS Secrets Manager are now synced to:"
echo "  - bookmyevent-secrets (Database credentials)"
echo "  - bookmyevent-app-secrets (JWT & API keys)"
echo ""
echo "The secrets will refresh every 1 hour automatically."
echo ""
echo "To view secret sync status:"
echo "  kubectl describe externalsecret database-credentials -n bookmyevent"
echo "  kubectl describe externalsecret application-secrets -n bookmyevent"
echo ""
echo "============================================================"
