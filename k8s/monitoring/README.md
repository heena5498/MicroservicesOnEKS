# BookMyEvent - Monitoring Setup Guide

Complete guide for deploying Prometheus and Grafana monitoring stack with Helm, configured to work with the existing ALB via nginx-gateway.

## 📋 Prerequisites

### Required Tools
- **kubectl** - Configured to access your EKS cluster
- **Helm 3** - For installing the monitoring stack
- **AWS CLI** - Configured with appropriate credentials

### Verify Prerequisites
```bash
kubectl version --client
helm version
aws sts get-caller-identity
```

### Required Permissions
- EKS cluster access
- Ability to create namespaces, services, deployments
- Helm repository access

## 🚀 Quick Start

### Option 1: Using GitHub Actions (Recommended)

1. Go to GitHub Actions → "Setup Monitoring Stack"
2. Click "Run workflow"
3. Wait for deployment to complete (~10-15 minutes)
4. Access via ALB URL shown in the workflow summary

### Option 2: Using Script

```bash
# Make script executable
chmod +x scripts/apply-monitoring.sh

# Run the script
./scripts/apply-monitoring.sh monitoring prometheus
```

### Option 3: Manual Installation

```bash
# 1. Create namespace
kubectl create namespace monitoring

# 2. Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. Install Prometheus stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/monitoring/values-monitoring.yaml \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --wait

# 4. Apply ServiceMonitors
kubectl apply -f k8s/monitoring/*-servicemonitor.yaml

# 5. Apply alert rules
kubectl apply -f k8s/monitoring/app-alerts.yaml

# 6. Update nginx-gateway
kubectl apply -f k8s/services/nginx-gateway/nginx-gateway.yaml
kubectl rollout restart deployment/nginx-gateway -n bookmyevent
```

## 📊 Accessing Dashboards

### Via ALB (nginx-gateway)

After deployment, access via your ALB URL:

- **Grafana**: `http://<your-alb-url>/grafana/`
  - Username: `admin`
  - Password: Get with: `kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d`

- **Prometheus**: `http://<your-alb-url>/prometheus/`

- **Alertmanager**: `http://<your-alb-url>/alertmanager/` (if configured)

### Via Port Forward (Alternative)

```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Visit: http://localhost:3000

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090

# Alertmanager
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
# Visit: http://localhost:9093
```

## 📈 Grafana Dashboards

### Required Dashboards

You need to create/import dashboards for:
1. **Latency Metrics** - p50, p95, p99 response times
2. **Error Rate** - HTTP status codes, error rates by service
3. **Resource Utilization** - CPU, memory, network by pod/service

### Importing Dashboards

1. Access Grafana at `http://<alb-url>/grafana/`
2. Go to **Dashboards** → **Import**
3. Upload JSON files from `k8s/monitoring/grafana-dashboards/` (if available)
4. Or create dashboards manually using Prometheus as data source

### Dashboard Queries

**Latency (p95):**
```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))
```

**Error Rate:**
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service) * 100
```

**CPU Usage:**
```promql
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod, namespace)
```

**Memory Usage:**
```promql
sum(container_memory_working_set_bytes) by (pod, namespace) / 1024 / 1024
```

## 🚨 Alert Rules

### Current Alerts

The following alerts are configured in `app-alerts.yaml`:

1. **HighErrorRate** - Error rate > 1 req/sec for 5 minutes
2. **PodCrashLoop** - Pod restarting frequently
3. **HighMemoryUsage** - Memory > 80% of limit
4. **HighCPUUsage** - CPU > 80% of limit

### Viewing Alerts

```bash
# List all alert rules
kubectl get prometheusrules -n monitoring

# View specific rule
kubectl describe prometheusrule event-service-alerts -n monitoring

# Check active alerts in Prometheus
# Visit: http://<alb-url>/prometheus/alerts
```

### Testing Alerts

```bash
# Simulate high error rate by scaling down a service
kubectl scale deployment/user-service -n bookmyevent --replicas=0

# Wait 5+ minutes for alert to fire
# Check Alertmanager: http://<alb-url>/alertmanager/
```

## 🔍 ServiceMonitors

### Current ServiceMonitors

- `user-servicemonitor.yaml` - Scrapes user-service metrics (port 8001)
- `event-servicemonitor.yaml` - Scrapes event-service metrics (port 8002)
- `search-servicemonitor.yaml` - Scrapes search-service metrics (port 8003)
- `booking-servicemonitor.yaml` - Scrapes booking-service metrics (port 8004)

### Verify ServiceMonitors

```bash
# List all ServiceMonitors
kubectl get servicemonitor -n monitoring

# Check if Prometheus is discovering targets
# Visit: http://<alb-url>/prometheus/targets
```

### ServiceMonitor Configuration

Each ServiceMonitor:
- Scrapes from `bookmyevent` namespace
- Uses port 8001-8004 (matching service ports)
- Scrapes `/metrics` endpoint
- Interval: 15 seconds

**Note:** Your services must expose `/metrics` endpoint for this to work.

## 📝 Configuration Files

### values-monitoring.yaml

Main Helm values file containing:
- Grafana configuration (ClusterIP, subpath support)
- Prometheus retention settings
- ServiceMonitor selector configuration

### app-alerts.yaml

Custom PrometheusRule with alert definitions for:
- High error rates
- Pod crashes
- Resource usage

### ServiceMonitor Files

Individual ServiceMonitor CRDs for each microservice.

## 🔧 Troubleshooting

### Prometheus Not Scraping Metrics

1. **Check ServiceMonitors:**
   ```bash
   kubectl get servicemonitor -n monitoring
   kubectl describe servicemonitor <name> -n monitoring
   ```

2. **Check Prometheus Targets:**
   - Visit: `http://<alb-url>/prometheus/targets`
   - Look for targets in "Down" state

3. **Verify Service Endpoints:**
   ```bash
   kubectl get endpoints -n bookmyevent
   kubectl get svc -n bookmyevent
   ```

4. **Check if services expose /metrics:**
   ```bash
   kubectl port-forward -n bookmyevent svc/user-service 8001:8001
   curl http://localhost:8001/metrics
   ```

### Grafana Not Accessible

1. **Check nginx-gateway:**
   ```bash
   kubectl get pods -n bookmyevent | grep nginx-gateway
   kubectl logs -n bookmyevent deployment/nginx-gateway
   ```

2. **Verify Grafana service:**
   ```bash
   kubectl get svc -n monitoring | grep grafana
   kubectl get pods -n monitoring | grep grafana
   ```

3. **Check ALB ingress:**
   ```bash
   kubectl get ingress -n bookmyevent
   kubectl describe ingress bookmyevent-ingress -n bookmyevent
   ```

### Alerts Not Firing

1. **Check PrometheusRules:**
   ```bash
   kubectl get prometheusrules -n monitoring
   kubectl describe prometheusrule <name> -n monitoring
   ```

2. **Verify alert expressions in Prometheus:**
   - Visit: `http://<alb-url>/prometheus/alerts`
   - Check if rules are loaded and evaluated

3. **Check Alertmanager:**
   ```bash
   kubectl get pods -n monitoring | grep alertmanager
   kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager
   ```

## 📚 Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [ServiceMonitor CRD](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#servicemonitor)

## ✅ Acceptance Criteria Checklist

- [x] Prometheus deployed with Helm
- [x] Grafana deployed with Helm
- [x] ServiceMonitors configured for all microservices
- [x] Alert rules configured (app-alerts.yaml)
- [x] Accessible via ALB at `/prometheus/` and `/grafana/`
- [ ] Dashboards created and imported (latency, error rate, resource utilization)
- [ ] Alerts tested with simulated failures
- [ ] Alert notifications configured (email/SNS)

## 🔄 Updating Configuration

### Update Helm Values

```bash
# Edit values file
vim k8s/monitoring/values-monitoring.yaml

# Upgrade Helm release
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/monitoring/values-monitoring.yaml
```

### Add New ServiceMonitor

1. Create new ServiceMonitor YAML in `k8s/monitoring/`
2. Apply: `kubectl apply -f k8s/monitoring/<new>-servicemonitor.yaml`
3. Verify in Prometheus targets

### Update Alert Rules

1. Edit `k8s/monitoring/app-alerts.yaml`
2. Apply: `kubectl apply -f k8s/monitoring/app-alerts.yaml`
3. Verify in Prometheus: `http://<alb-url>/prometheus/alerts`

---

**Last Updated**: [Date]  
**Maintained By**: DevOps Team

