param(
    [string]$Namespace = "monitoring",
    [string]$ReleaseName = "kube-prom-stack",
    [string]$ValuesFile = "k8s/monitoring/values-monitoring.yaml",
    [switch]$SkipHelmInstall
)

function Check-Command($cmd) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $found) {
        Write-Error "Required command '$cmd' not found in PATH. Please install it and retry."
        exit 1
    }
}

Write-Host "Checking prerequisites: kubectl and helm..."
Check-Command kubectl
Check-Command helm

Write-Host "Ensuring namespace '$Namespace' exists..."
$ns = kubectl get namespace $Namespace -o name 2>$null
if (-not $ns) {
    kubectl create namespace $Namespace
}

if (-not $SkipHelmInstall) {
    Write-Host "Adding Helm repositories (prometheus-community, grafana) and updating..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null
    helm repo add grafana https://grafana.github.io/helm-charts 2>$null
    helm repo update

    Write-Host "Installing or upgrading Prometheus + Grafana via kube-prometheus-stack Helm chart..."
    helm upgrade --install $ReleaseName prometheus-community/kube-prometheus-stack `
        --namespace $Namespace --values $ValuesFile --create-namespace
}
else {
    Write-Host "Skipping Helm install as requested (use -SkipHelmInstall to skip)."
}

Write-Host "Applying application-specific monitoring manifests from 'k8s/monitoring'..."
$monitoringDir = "k8s/monitoring"
if (-not (Test-Path $monitoringDir)) {
    Write-Error "Directory '$monitoringDir' not found in repository root. Aborting."
    exit 1
}

Get-ChildItem -Path $monitoringDir -Filter *.yaml | Where-Object { $_.Name -ne "values-monitoring.yaml" } | ForEach-Object {
    Write-Host "Applying: $($_.Name)"
    kubectl apply -f $_.FullName -n $Namespace
}

Write-Host "Waiting a few seconds for core components to reconcile..."
Start-Sleep -Seconds 8

Write-Host "Helpful verification commands:"
Write-Host "  - kubectl get pods -n $Namespace"
Write-Host "  - kubectl get svc -n $Namespace"
Write-Host "  - kubectl get servicemonitors -A"

# Try to print Grafana admin password (best-effort)
$grafanaSecret = "${ReleaseName}-grafana"
Write-Host "Attempting to retrieve Grafana admin password from secret '$grafanaSecret' in namespace '$Namespace'..."
$pwdBase64 = kubectl get secret -n $Namespace $grafanaSecret -o jsonpath="{.data.admin-password}" 2>$null
if ($pwdBase64) {
    try {
        $pwd = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pwdBase64))
        Write-Host "Grafana admin password: $pwd"
    } catch {
        Write-Host "Password found but could not decode it with this script. Use kubectl to inspect the secret manually."
    }
} else {
    Write-Host "Grafana secret not found with name '$grafanaSecret'. Check release name or the Helm chart's generated secret name."
}

Write-Host "If Grafana was installed with an Ingress (see 'grafana-ingress.yaml'), retrieve the ingress host and open it in your browser."
Write-Host "To remove the monitoring Helm release: helm uninstall $ReleaseName -n $Namespace"
