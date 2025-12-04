# Changelog

All notable changes to the BookMyEvent project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Helm chart for Kubernetes deployment
- Multi-environment support (dev/prod)
- Comprehensive CI/CD pipeline with GitHub Actions
- Security scanning with Trivy
- Service-specific folder organization

### Changed
- Reorganized Dockerfiles into service-specific folders
- Moved YAML manifests to service directories
- Updated deployment scripts for new structure

### Fixed
- EKS nodegroup creation logic

## [1.0.0] - 2025-12-03

### Added
- Initial release of BookMyEvent microservices platform
- User Service - User authentication and profile management
- Event Service - Event CRUD and management
- Search Service - Elasticsearch-based event search
- Booking Service - Event booking with concurrency control
- Frontend - React-based web interface
- Infrastructure - PostgreSQL, Redis, Elasticsearch
- CI/CD - GitHub Actions workflow
- Documentation - Comprehensive deployment and API docs
- Database migrations for all services
- Docker and Kubernetes support
- EKS deployment scripts

### Infrastructure
- AWS EKS cluster support
- Amazon ECR for container registry
- Load balancer with NGINX gateway
- Secrets management with AWS Secrets Manager
- Persistent storage with EBS CSI driver

### Security
- JWT-based authentication
- Secret scanning with gitleaks
- Container vulnerability scanning
- Non-root container execution
- Network policies

## [0.1.0] - 2025-11-15

### Added
- Initial project structure
- Basic microservices skeleton
- Local development with Docker Compose
- Database schema design
- API endpoint definitions

---

## Categories

### Added
For new features.

### Changed
For changes in existing functionality.

### Deprecated
For soon-to-be removed features.

### Removed
For now removed features.

### Fixed
For any bug fixes.

### Security
In case of vulnerabilities.
