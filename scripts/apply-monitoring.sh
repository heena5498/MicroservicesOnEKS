#!/bin/bash

# Monitoring Setup Script
# This script installs Prometheus and Grafana using Helm and applies monitoring manifests
# Usage: ./scripts/apply-monitoring.sh [namespace] [release-name] [skip-helm-install]

set -e

# Default values
NAMESPACE="${1:-monitoring}"
RELEASE_NAME="${2:-prometheus}"
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
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
            --wait \
            --timeout 15m
    else
        echo "Warning: $VALUES_FILE not found, using default values"
        helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
            --namespace "$NAMESPACE" \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
            --wait \
            --timeout 15m
    fi
    
    echo "✓ kube-prometheus-stack installed/upgraded"
}

# Function to apply ServiceMonitors
apply_servicemonitors() {
    echo "Applying ServiceMonitors for microservices..."
    
    MONITORING_DIR="k8s/monitoring"
    
    if [ ! -d "$MONITORING_DIR" ]; then
        echo "Warning: $MONITORING_DIR directory not found"
        return
    fi
    
    # Apply all ServiceMonitor files
    for file in "$MONITORING_DIR"/*servicemonitor.yaml; do
        if [ -f "$file" ]; then
            echo "  Applying $(basename $file)..."
            kubectl apply -f "$file" || echo "    Warning: Failed to apply $file"
        fi
    done
    
    echo "✓ ServiceMonitors applied"
    kubectl get servicemonitor -n "$NAMESPACE"
}

# Function to apply alert rules
apply_alert_rules() {
    echo "Applying alert rules..."
    
    if [ -f "k8s/monitoring/app-alerts.yaml" ]; then
        kubectl apply -f k8s/monitoring/app-alerts.yaml
        echo "✓ Alert rules applied"
        kubectl get prometheusrules -n "$NAMESPACE"
    else
        echo "  Warning: app-alerts.yaml not found"
    fi
}

# Function to update nginx-gateway
update_nginx_gateway() {
    echo "Updating nginx-gateway with monitoring routes..."
    
    if [ -f "k8s/services/nginx-gateway/nginx-gateway.yaml" ]; then
        kubectl apply -f k8s/services/nginx-gateway/nginx-gateway.yaml
        if kubectl get deployment nginx-gateway -n bookmyevent &> /dev/null; then
            kubectl rollout restart deployment/nginx-gateway -n bookmyevent
            echo "✓ nginx-gateway updated and restarted"
        else
            echo "  Warning: nginx-gateway not found in bookmyevent namespace"
            echo "  You may need to deploy nginx-gateway separately"
        fi
    else
        echo "  Warning: nginx-gateway.yaml not found"
    fi
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
    GRAFANA_SECRET="$RELEASE_NAME-grafana"
    GRAFANA_PASSWORD=$(kubectl get secret -n "$NAMESPACE" "$GRAFANA_SECRET" -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d || echo "admin")
    
    # Get ALB URL
    ALB_URL=$(kubectl get ingress bookmyevent-ingress -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "<your-alb-url>")
    
    if [ -n "$GRAFANA_PASSWORD" ]; then
        echo ""
        echo "========================================="
        echo "Access Information:"
        echo "========================================="
        echo ""
        echo "Access via ALB (nginx-gateway):"
        echo "  Grafana:    http://${ALB_URL}/grafana/"
        echo "  Prometheus: http://${ALB_URL}/prometheus/"
        echo ""
        echo "Grafana Credentials:"
        echo "  Username: admin"
        echo "  Password: $GRAFANA_PASSWORD"
        echo ""
        echo "Port Forward (Alternative):"
        echo "  kubectl port-forward -n $NAMESPACE svc/$GRAFANA_SECRET 3000:80"
        echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-kube-prometheus-prometheus 9090:9090"
        echo ""
        echo "ServiceMonitors:"
        kubectl get servicemonitor -n "$NAMESPACE" 2>/dev/null || echo "  No ServiceMonitors found"
        echo ""
        echo "PrometheusRules:"
        kubectl get prometheusrules -n "$NAMESPACE" 2>/dev/null || echo "  No PrometheusRules found"
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
    apply_servicemonitors
    apply_alert_rules
    update_nginx_gateway
    display_access_info
    
    echo ""
    echo "✓ Monitoring setup completed successfully!"
}

# Run main function
main
