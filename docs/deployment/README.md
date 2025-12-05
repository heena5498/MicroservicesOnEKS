# Deployment Documentation

This directory contains deployment guides and project documentation for BookMyEvent.

## Quick Start

**One-Command Deployment:**
```bash
./scripts/eks/deploy-complete.sh
```

See [eks-deployment-guide.md](eks-deployment-guide.md) for complete instructions.

## Documentation

### [eks-deployment-guide.md](eks-deployment-guide.md)
Complete EKS deployment guide covering:
- Prerequisites and tools
- One-command deployment
- Step-by-step deployment
- Service configuration
- Monitoring and troubleshooting
- Cleanup procedures

**What it covers:**
- ✅ ECR repository creation
- ✅ Docker image building
- ✅ EKS cluster creation
- ✅ Infrastructure deployment (PostgreSQL, Redis, Elasticsearch)
- ✅ Microservices deployment
- ✅ Database migrations
- ✅ LoadBalancer configuration

### [eks-project-md.md](eks-project-md.md)
Project requirements and specifications:
- Course project overview (ENPM818R)
- Technical requirements
- Architecture specifications
- Deliverables checklist
- Evaluation criteria

## Deployment Architecture

```
AWS EKS Cluster
├── Infrastructure Services
│   ├── PostgreSQL (3 databases)
│   ├── Redis
│   └── Elasticsearch
├── Application Services
│   ├── user-service
│   ├── event-service
│   ├── search-service
│   └── booking-service
├── Frontend (React)
└── NGINX Ingress Controller
```

## Deployment Process

1. **Create ECR Repositories** (~1 min)
2. **Build & Push Images** (~10-15 min)
3. **Create EKS Cluster** (~15-20 min)
4. **Deploy Infrastructure** (~5 min)
5. **Run Migrations** (~1 min)
6. **Deploy Services** (~5 min)

**Total time:** ~25-35 minutes

## Related Resources

- Deployment scripts: `scripts/eks/`
- Kubernetes manifests: `k8s/`
- Build configuration: `build/`
- CI/CD automation: `build/ci-cd-guide.md`
- Secrets management: `docs/secrets/`

## Key Files

- `scripts/eks/deploy-complete.sh` - Full automated deployment
- `scripts/eks/1-create-ecr-repos.sh` - ECR setup
- `scripts/eks/2-build-push-images.sh` - Image building
- `scripts/eks/3-create-eks-cluster.sh` - Cluster creation
- `scripts/eks/4-deploy-to-eks.sh` - Service deployment
- `scripts/eks/5-cleanup.sh` - Resource cleanup
