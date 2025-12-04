#!/bin/bash
# =============================================================================
# Script: 3-create-eks-cluster.sh
# Description: Creates an EKS cluster using eksctl
# =============================================================================

set -e

# Configuration - UPDATE THESE
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-bookmyevent-cluster}"
export NODE_TYPE="${NODE_TYPE:-t3.medium}"
export NODE_COUNT="${NODE_COUNT:-3}"
export NODE_MIN="${NODE_MIN:-3}"
export NODE_MAX="${NODE_MAX:-6}"

echo "======================================"
echo "Creating EKS Cluster"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Node Type: $NODE_TYPE"
echo "Node Count: $NODE_COUNT (min: $NODE_MIN, max: $NODE_MAX)"
echo "======================================"

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo "eksctl is not installed. Please install it first:"
    echo "   https://eksctl.io/installation/"
    exit 1
fi

# Check if cluster already exists
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "Cluster $CLUSTER_NAME already exists."
    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
    
    # Check if nodegroup exists, if not create it
    echo ""
    echo "Checking for nodegroups..."
    if eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$AWS_REGION" --name="bookmyevent-nodes" 2>/dev/null; then
        echo "Nodegroup 'bookmyevent-nodes' already exists."
    else
        echo "No nodegroup found. Creating nodegroup..."
        eksctl create nodegroup \
            --cluster="$CLUSTER_NAME" \
            --region="$AWS_REGION" \
            --name="bookmyevent-nodes" \
            --node-type="$NODE_TYPE" \
            --nodes="$NODE_COUNT" \
            --nodes-min="$NODE_MIN" \
            --nodes-max="$NODE_MAX" \
            --managed
    fi
else
    echo "Creating EKS cluster (this takes 15-20 minutes)..."
    
    # Check if SSH key exists
    if [ -f ~/.ssh/id_rsa.pub ]; then
        echo "Using SSH key for node access..."
        eksctl create cluster \
            --name "$CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --version 1.30 \
            --nodegroup-name "bookmyevent-nodes" \
            --node-type "$NODE_TYPE" \
            --nodes "$NODE_COUNT" \
            --nodes-min "$NODE_MIN" \
            --nodes-max "$NODE_MAX" \
            --managed \
            --with-oidc \
            --ssh-access \
            --ssh-public-key ~/.ssh/id_rsa.pub \
            --full-ecr-access
    else
        echo "No SSH key found, creating cluster without SSH access..."
        eksctl create cluster \
            --name "$CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --version 1.30 \
            --nodegroup-name "bookmyevent-nodes" \
            --node-type "$NODE_TYPE" \
            --nodes "$NODE_COUNT" \
            --nodes-min "$NODE_MIN" \
            --nodes-max "$NODE_MAX" \
            --managed \
            --with-oidc \
            --full-ecr-access
    fi
fi

# Install/Update AWS VPC CNI addon
echo ""
echo "Installing/Updating AWS VPC CNI addon..."
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.18.0/config/master/aws-k8s-cni.yaml
echo "✓ AWS VPC CNI addon installed/updated"

# Wait for CNI pods to be ready
echo "Waiting for CNI pods to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=aws-node -n kube-system --timeout=120s || true

# Install EBS CSI Driver addon
echo ""
echo "Installing EBS CSI Driver addon..."
eksctl create addon --name aws-ebs-csi-driver --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --force 2>/dev/null || true
echo "✓ EBS CSI Driver addon installed"

echo ""
echo "======================================"
echo "EKS Cluster Ready!"
echo "======================================"

# Verify connection
echo ""
echo "Verifying cluster connection..."
kubectl get nodes

echo ""
echo "Cluster info:"
kubectl cluster-info

echo ""
echo "Next step: Run ./4-deploy-to-eks.sh"




