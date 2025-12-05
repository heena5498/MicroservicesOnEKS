# Monitoring setup for this repository

Purpose
- This document explains how to install Prometheus and Grafana for the application and how to apply the repository's monitoring manifests located in `k8s/monitoring`.

Prerequisites
- `kubectl` (cluster access with permission to create namespaces, CRDs, and resources).
- `helm` (v3+).
- Access to the Kubernetes cluster context you intend to use (run `kubectl config current-context`).
- Optional: Ingress controller installed in your cluster if you plan to use `grafana-ingress.yaml` / `prometheus-ingress.yaml`.

What the included script does
- `scripts/apply-monitoring.ps1` will:
  - Add Helm repos (`prometheus-community` and `grafana`) and update them.
  - Install or upgrade the `prometheus-community/kube-prometheus-stack` Helm chart using `k8s/monitoring/values-monitoring.yaml`.
  - Apply application-specific `ServiceMonitor`, `Ingress`, and alerting YAMLs in `k8s/monitoring` (it skips `values-monitoring.yaml`).

Usage (PowerShell)
- From the repository root in PowerShell run:

```powershell
# Default: installs to namespace 'monitoring'
.\n+\scripts\apply-monitoring.ps1

# Custom namespace or release name
.
\scripts\apply-monitoring.ps1 -Namespace my-monitoring -ReleaseName my-monitoring-release

# If you already installed Prometheus/Grafana another way and only want to apply manifests
.
\scripts\apply-monitoring.ps1 -SkipHelmInstall
```

Notes on `values-monitoring.yaml`
- The file `k8s/monitoring/values-monitoring.yaml` is used as the Helm values file for the `kube-prometheus-stack` chart. Edit it to configure:
  - Grafana settings (ingress, service type, resources)
  - Prometheus scrape config overrides
  - Alertmanager configuration

Verify installation
- Check pods and services:

```powershell
kubectl get pods -n monitoring
kubectl get svc -n monitoring
kubectl get servicemonitors -A
```

- Retrieve Grafana admin password (example):

```powershell
# Replace release name if you used a different one
$secret = kubectl get secret -n monitoring kube-prom-stack-grafana -o jsonpath="{.data.admin-password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret))
```

Uninstall
- To remove the Helm release:

```powershell
helm uninstall kube-prom-stack -n monitoring
kubectl delete namespace monitoring
```

Troubleshooting
- If Helm fails to install, run `helm install` with `--debug` and `--dry-run` to inspect rendered templates.
- If ServiceMonitors are not picked up, confirm Prometheus operator has permissions and the ServiceMonitor CRD exists.
- If ingress doesn't show up, verify your cluster has an Ingress controller and that the hostnames in the ingress match DNS or `/etc/hosts` entries.

If you want, I can also add a small `Makefile` target or a bash wrapper for non-Windows usage. Would you like that?
