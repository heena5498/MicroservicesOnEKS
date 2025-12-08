#!/bin/bash

# Monitoring Setup Script
# This script installs Prometheus and Grafana using Helm and applies monitoring manifests

set -e

# Default values
NAMESPACE="${1:-monitoring}"
RELEASE_NAME="${2:-kube-prometheus-stack}"
SKIP_HELM_INSTALL="${3:-false}"

echo "========================================="
echo "Monitoring Setup for BookMyEvent"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "Release Name: $RELEASE_NAME"
echo "========================================="

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed or not in PATH"
        exit 1
    fi
    echo "✓ kubectl found"
}

# Function to check if helm is available
check_helm() {
    if ! command -v helm &> /dev/null; then
        echo "Error: helm is not installed or not in PATH"
        exit 1
    fi
    echo "✓ helm found"
}

# Function to create namespace if it doesn't exist
create_namespace() {
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo "✓ Namespace '$NAMESPACE' already exists"
    else
        echo "Creating namespace '$NAMESPACE'..."
        kubectl create namespace "$NAMESPACE"
        echo "✓ Namespace created"
    fi
}

# Function to add and update Helm repos
setup_helm_repos() {
    echo "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    echo "Updating Helm repositories..."
    helm repo update
    echo "✓ Helm repos configured"
}

# Function to install or upgrade monitoring stack
install_monitoring_stack() {
    if [ "$SKIP_HELM_INSTALL" = "true" ]; then
        echo "Skipping Helm installation (SKIP_HELM_INSTALL=true)"
        return
    fi

    echo "Installing/upgrading kube-prometheus-stack..."
    
    # Check if values file exists
    VALUES_FILE="k8s/monitoring/values-monitoring.yaml"
    if [ -f "$VALUES_FILE" ]; then
        helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
            --namespace "$NAMESPACE" \
            --values "$VALUES_FILE" \
            --wait
    else
        echo "Warning: $VALUES_FILE not found, using default values"
        helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
            --namespace "$NAMESPACE" \
            --wait
    fi
    
    echo "✓ kube-prometheus-stack installed/upgraded"
}

# Function to apply custom monitoring manifests
apply_monitoring_manifests() {
    echo "Applying custom monitoring manifests from k8s/monitoring/..."
    
    MONITORING_DIR="k8s/monitoring"
    
    if [ ! -d "$MONITORING_DIR" ]; then
        echo "Warning: $MONITORING_DIR directory not found, skipping custom manifests"
        return
    fi
    
    # Apply all YAML files except values-monitoring.yaml
    for file in "$MONITORING_DIR"/*.yaml "$MONITORING_DIR"/*.yml; do
        if [ -f "$file" ] && [[ ! "$file" =~ values-monitoring.yaml ]]; then
            echo "Applying $file..."
            kubectl apply -f "$file" -n "$NAMESPACE" || echo "Warning: Failed to apply $file"
        fi
    done
    
    echo "✓ Custom monitoring manifests applied"
}

# Function to display access information
display_access_info() {
    echo ""
    echo "========================================="
    echo "Monitoring Stack Deployed Successfully!"
    echo "========================================="
    echo ""
    echo "Checking services..."
    kubectl get svc -n "$NAMESPACE"
    echo ""
    
    # Get Grafana admin password
    echo "Retrieving Grafana admin password..."
    GRAFANA_PASSWORD=$(kubectl get secret -n "$NAMESPACE" "$RELEASE_NAME-grafana" -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode)
    
    if [ -n "$GRAFANA_PASSWORD" ]; then
        echo ""
        echo "========================================="
        echo "Access Information:"
        echo "========================================="
        echo "Grafana:"
        echo "  Username: admin"
        echo "  Password: $GRAFANA_PASSWORD"
        echo ""
        echo "To access Grafana, run:"
        echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-grafana 3000:80"
        echo "  Then visit: http://localhost:3000"
        echo ""
        echo "To access Prometheus, run:"
        echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-kube-prome-prometheus 9090:9090"
        echo "  Then visit: http://localhost:9090"
        echo "========================================="
    else
        echo "Warning: Could not retrieve Grafana password"
    fi
}

# Main execution
main() {
    echo "Starting monitoring setup..."
    
    check_kubectl
    check_helm
    create_namespace
    setup_helm_repos
    install_monitoring_stack
    apply_monitoring_manifests
    display_access_info
    
    echo ""
    echo "✓ Monitoring setup completed successfully!"
}

# Run main function
main
