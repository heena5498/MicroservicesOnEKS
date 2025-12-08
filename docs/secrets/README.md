# Secrets Management Documentation

This directory contains documentation for AWS Secrets Manager integration with the BookMyEvent application.

## Quick Start

**2-Command Setup:**
```bash
./scripts/secrets/setup-secrets-manager.sh
./scripts/secrets/deploy-external-secrets.sh
```

See [secrets-quickstart.md](secrets-quickstart.md) for details.

## Documentation

### [secrets-manager-guide.md](secrets-manager-guide.md)
Complete guide to AWS Secrets Manager integration:
- Architecture overview
- Setup instructions
- IRSA configuration
- External Secrets Operator
- Troubleshooting
- Best practices

### [secrets-quickstart.md](secrets-quickstart.md)
Quick reference for:
- 2-command setup
- Verification steps
- Common issues
- Quick health checks

## Overview

The BookMyEvent application uses AWS Secrets Manager for secure secret storage, integrated with Kubernetes via the External Secrets Operator (ESO). This approach provides:

- ✅ Centralized secret management
- ✅ Automatic rotation support
- ✅ Audit logging via CloudTrail
- ✅ No secrets in Git
- ✅ Auto-sync to Kubernetes

## Architecture

```
AWS Secrets Manager (Source of Truth)
    ↓
External Secrets Operator (Sync every 1h)
    ↓
Kubernetes Secrets (Consumed by Pods)
```

## Related Resources

- Setup scripts: `scripts/secrets/`
- Kubernetes manifests: `k8s/secrets-management/`
- CI/CD integration: `../build/ci-cd-guide.md`
