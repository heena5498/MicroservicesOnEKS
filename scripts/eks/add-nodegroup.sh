#!/bin/bash
# =============================================================================
# Script: add-nodegroup.sh
# Description: Adds a nodegroup to existing EKS cluster
# =============================================================================

set -e

# Configuration - matches your cluster settings
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"
export NODEGROUP_NAME="${NODEGROUP_NAME:-bookmyevent-nodes}"
export NODE_TYPE="${NODE_TYPE:-t3.medium}"
export NODE_COUNT="${NODE_COUNT:-3}"
export NODE_MIN="${NODE_MIN:-3}"
export NODE_MAX="${NODE_MAX:-6}"

echo "======================================"
echo "Adding Nodegroup to EKS Cluster"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Nodegroup: $NODEGROUP_NAME"
echo "Node Type: $NODE_TYPE"
echo "Node Count: $NODE_COUNT (min: $NODE_MIN, max: $NODE_MAX)"
echo "======================================"

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo "❌ eksctl is not installed. Please install it first:"
    echo "   https://eksctl.io/installation/"
    exit 1
fi

# Check if cluster exists
echo ""
echo "Checking if cluster exists..."
if ! eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "❌ Cluster $CLUSTER_NAME does not exist in region $AWS_REGION"
    exit 1
fi

echo "✅ Cluster found"

# Check if nodegroup already exists
echo ""
echo "Checking existing nodegroups..."
if eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$AWS_REGION" --name="$NODEGROUP_NAME" 2>/dev/null; then
    echo "⚠️  Nodegroup $NODEGROUP_NAME already exists"
    echo ""
    echo "Current nodes:"
    kubectl get nodes
    exit 0
fi

echo ""
echo "Creating nodegroup (this takes 5-10 minutes)..."
eksctl create nodegroup \
    --cluster="$CLUSTER_NAME" \
    --region="$AWS_REGION" \
    --name="$NODEGROUP_NAME" \
    --node-type="$NODE_TYPE" \
    --nodes="$NODE_COUNT" \
    --nodes-min="$NODE_MIN" \
    --nodes-max="$NODE_MAX" \
    --managed

echo ""
echo "======================================"
echo "✅ Nodegroup Created Successfully!"
echo "======================================"

# Verify nodes
echo ""
echo "Verifying nodes..."
kubectl get nodes -o wide

echo ""
echo "Checking pod status in bookmyevent namespace..."
kubectl get pods -n bookmyevent

echo ""
echo "✅ Done! Your pods should now start scheduling on the new nodes."
echo "   Monitor with: kubectl get pods -n bookmyevent -w"
