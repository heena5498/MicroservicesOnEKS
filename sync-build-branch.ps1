# Script to sync with latest build branch and apply local changes
$ErrorActionPreference = "Stop"

Write-Host "=== Syncing with latest build branch ===" -ForegroundColor Cyan

# Step 1: Check current branch
Write-Host "`n[1/4] Checking current branch..." -ForegroundColor Yellow
$currentBranch = git rev-parse --abbrev-ref HEAD
Write-Host "Current branch: $currentBranch" -ForegroundColor Green

if ($currentBranch -ne "build") {
    Write-Host "Switching to build branch..." -ForegroundColor Yellow
    git checkout build
}

# Step 2: Stash local changes
Write-Host "`n[2/4] Stashing local changes..." -ForegroundColor Yellow
git stash push -m "Session changes: HPA, Cluster Autoscaler, TLS config, event-service fix"

# Step 3: Fetch and pull latest
Write-Host "`n[3/4] Fetching latest from origin/build..." -ForegroundColor Yellow
git fetch origin build
git pull origin build

# Step 4: Apply stashed changes
Write-Host "`n[4/4] Applying local changes..." -ForegroundColor Yellow
git stash pop

Write-Host "`n=== Sync Complete ===" -ForegroundColor Green
Write-Host "`nCurrent status:" -ForegroundColor Cyan
git status --short




