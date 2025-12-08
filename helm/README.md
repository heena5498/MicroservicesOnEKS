# BookMyEvent Helm Chart

This Helm chart deploys the BookMyEvent microservices application to Kubernetes/EKS.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- AWS EKS cluster (for production)
- kubectl configured to communicate with your cluster

## Installation

### Quick Start

```bash
# Install with default values
helm install bookmyevent ./helm/bookmyevent \
  --namespace bookmyevent \
  --create-namespace

# Install with custom values
helm install bookmyevent ./helm/bookmyevent \
  --namespace bookmyevent \
  --create-namespace \
  -f helm/bookmyevent/values-prod.yaml
```

### Production Installation

```bash
# Set required secrets
export DB_PASSWORD="your-secure-password"
export JWT_SECRET="your-jwt-secret"
export INTERNAL_API_KEY="your-api-key"
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"

# Install
helm upgrade --install bookmyevent ./helm/bookmyevent \
  --namespace bookmyevent \
  --create-namespace \
  --set global.imageRegistry="${ECR_REGISTRY}" \
  --set secrets.postgresPassword="${DB_PASSWORD}" \
  --set secrets.jwtSecret="${JWT_SECRET}" \
  --set secrets.internalApiKey="${INTERNAL_API_KEY}" \
  --set imageTags.userService="v1.0.0" \
  --set imageTags.eventService="v1.0.0" \
  --set imageTags.searchService="v1.0.0" \
  --set imageTags.bookingService="v1.0.0" \
  --set imageTags.frontend="v1.0.0" \
  -f helm/bookmyevent/values-prod.yaml \
  --wait
```

### Development Installation

```bash
helm upgrade --install bookmyevent ./helm/bookmyevent \
  --namespace bookmyevent-dev \
  --create-namespace \
  -f helm/bookmyevent/values-dev.yaml \
  --set global.imageRegistry="${ECR_REGISTRY}" \
  --set secrets.postgresPassword="devpassword" \
  --set secrets.jwtSecret="dev-jwt-secret" \
  --set secrets.internalApiKey="dev-api-key"
```

## Configuration

### Image Registry

Set your ECR registry:

```bash
--set global.imageRegistry="123456789012.dkr.ecr.us-east-1.amazonaws.com"
```

### Image Tags

Override individual service image tags:

```bash
--set imageTags.userService="v1.0.1" \
--set imageTags.eventService="v1.0.2"
```

### Secrets

Required secrets (must be set):

```bash
--set secrets.postgresPassword="your-password" \
--set secrets.jwtSecret="your-jwt-secret" \
--set secrets.internalApiKey="your-api-key"
```

### Resource Limits

Modify resource limits in `values.yaml` or override:

```bash
--set resources.userService.limits.cpu="1000m" \
--set resources.userService.limits.memory="1Gi"
```

### Autoscaling

Enable HPA for production:

```bash
--set autoscaling.enabled=true \
--set autoscaling.minReplicas=2 \
--set autoscaling.maxReplicas=10
```

## Upgrading

```bash
# Upgrade with new image tags
helm upgrade bookmyevent ./helm/bookmyevent \
  --namespace bookmyevent \
  --set imageTags.userService="v1.0.1" \
  --reuse-values

# Upgrade with new values file
helm upgrade bookmyevent ./helm/bookmyevent \
  --namespace bookmyevent \
  -f helm/bookmyevent/values-prod.yaml
```

## Uninstallation

```bash
# Uninstall release
helm uninstall bookmyevent --namespace bookmyevent

# Delete namespace
kubectl delete namespace bookmyevent
```

## Verification

```bash
# Check release status
helm status bookmyevent -n bookmyevent

# List all resources
kubectl get all -n bookmyevent

# Check pod logs
kubectl logs -f deployment/user-service -n bookmyevent

# Get LoadBalancer URL
kubectl get service nginx-gateway -n bookmyevent
```

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n bookmyevent

# Describe problematic pod
kubectl describe pod <pod-name> -n bookmyevent

# Check logs
kubectl logs <pod-name> -n bookmyevent
```

### Image pull errors

Ensure your nodes have access to ECR:

```bash
# Verify ECR access
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com
```

### Database connection issues

```bash
# Check postgres pod
kubectl get pod -l app=postgres -n bookmyevent

# Check postgres logs
kubectl logs -l app=postgres -n bookmyevent

# Exec into service pod and test connection
kubectl exec -it deployment/user-service -n bookmyevent -- /bin/sh
```

## Values Files

- `values.yaml` - Default values
- `values-dev.yaml` - Development environment
- `values-prod.yaml` - Production environment

## Chart Structure

```
helm/bookmyevent/
├── Chart.yaml                  # Chart metadata
├── values.yaml                 # Default values
├── values-dev.yaml            # Dev environment values
├── values-prod.yaml           # Prod environment values
├── templates/
│   ├── _helpers.tpl           # Template helpers
│   ├── namespace.yaml         # Namespace
│   ├── configmap.yaml         # ConfigMap
│   ├── secrets.yaml           # Secrets
│   ├── infrastructure/        # Infrastructure components
│   │   ├── postgres.yaml
│   │   ├── redis.yaml
│   │   └── elasticsearch.yaml
│   └── services/              # Microservices
│       ├── user-service.yaml
│       ├── event-service.yaml
│       ├── search-service.yaml
│       ├── booking-service.yaml
│       ├── frontend.yaml
│       └── nginx-gateway.yaml
```

## CI/CD Integration

The chart is designed to work with GitHub Actions:

```yaml
- name: Deploy with Helm
  run: |
    helm upgrade --install bookmyevent ./helm/bookmyevent \
      --namespace bookmyevent \
      --set global.imageRegistry="${ECR_REGISTRY}" \
      --set imageTags.userService="${IMAGE_TAG}" \
      --wait
```

## Support

For issues and questions:
- Check the main project README
- Review CI/CD documentation in `build/`
- Check deployment guides in `docs/deployment/`
