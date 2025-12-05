
**Project Title:** Cloud-Native Application Deployment using AWS EKS, Kubernetes, and Load Balancing

**Team Size:** 5–6 students per group

**Duration:** Approximately 5 weeks

## Project Overview

Your team will design, containerize, deploy, and scale a multi-service web application using Docker, Kubernetes, and AWS Elastic Kubernetes Service (EKS). The final deliverable demonstrates a production-ready EKS cluster orchestrating multiple containerized microservices, complete with load balancing, monitoring, and CI/CD.

## Learning Objectives

- Deploy and manage a Kubernetes cluster on AWS EKS
- Design and build Dockerized microservices
- Configure Kubernetes services, Ingress, and load balancers
- Implement CI/CD pipelines for container builds and EKS deployments
- Apply observability tools for monitoring (CloudWatch, Prometheus, Grafana)
- Manage persistent storage and secrets within EKS
- Collaborate using GitHub or GitLab with branch workflows

## Smart Campus Event Management System

### Scenario

Design a cloud-native application for managing campus events (lectures, workshops, club activities). Students, faculty, and organizers interact via web and API services.

### Example Microservices

- **Frontend Service:** Event registration and search portal (React or Angular)
- **Events API:** CRUD operations for events, schedules, and RSVPs (Node.js, Flask, or Go)
- **Notification Service:** Sends email or SMS reminders using AWS SNS
- **Database:** RDS (PostgreSQL/MySQL) or MongoDB for event metadata

## Technical Requirements

### Infrastructure

- **AWS EKS cluster** (CloudFormation, eksctl, or Terraform): CloudFormation
- At least 3 worker nodes
- IAM roles for nodes and EKS service accounts
- VPC with private and public subnets

### Application Architecture

- Minimum of 3 microservices (frontend, API, database)
- Each service containerized
- **Ingress Controller:** ALB or NGINX
- **Persistent storage:** EFS, RDS, or S3
- **Secrets management:** AWS Secrets Manager

### Automation

- CI/CD pipeline (GitHub Actions or GitLab CI)
- Automated build → push → deploy workflow

### Observability

- Application logs via CloudWatch or ELK
- Metrics dashboards (Prometheus/Grafana)
- Health checks and rolling updates

## Project Milestones

| Week | Focus | Deliverables |
|------|-------|--------------|
| 1 | Planning & Design | Architecture diagram, service definitions, Git repo setup, IaC plan for EKS |
| 2 | Containerization | Dockerfiles for each service, Docker Compose for local testing |
| 3 | EKS Cluster Setup | Working EKS cluster with worker nodes and basic deployments |
| 4 | Load Balancing & Scaling | Ingress/ALB setup, HPA, service networking verified |
| 5 | CI/CD & Observability | Automated pipeline, dashboards, presentation, and documentation |

## Team Roles (Recommended)

- **Project Lead / DevOps:** Oversees architecture and CI/CD pipeline
- **Infrastructure Engineer:** EKS setup, IaC templates, networking
- **Backend Developer(s):** API services and integration
- **Frontend Developer:** UI design and connection to backend APIs
- **Monitoring/Automation Lead:** Logging, monitoring, scaling
- **Documentation Lead:** Architecture diagrams and final report

## Guidance for Deliverables and Objectives

### 1. Deploy and Manage a Kubernetes Cluster on AWS EKS

#### Guidance

- Provision EKS via Infrastructure-as-Code (CloudFormation, Terraform, or eksctl)
- Create at least two node groups across 2+ Availability Zones; enable the cluster autoscaler
- Configure namespaces for dev/staging/prod and apply RBAC least-privilege roles
- Install AWS Load Balancer Controller and enable IAM Roles for Service Accounts (IRSA)
- Document kubeconfig access, bootstrap steps, and maintenance procedures

#### Suggested Deliverables

- IaC templates for VPC, subnets, node groups, and the EKS control plane
- RBAC manifests for namespaces and service accounts (including IRSA)
- Installed add-ons (ALB Controller, Cluster Autoscaler) with configs
- Architecture diagram (VPC layout, node groups, AZs, endpoints)

#### Acceptance Criteria

- `kubectl get nodes -o wide` shows nodes in multiple AZs
- Autoscaler responds to load changes and logs scale events
- At least one workload uses IRSA for AWS access
- ALB or NGINX Ingress Controller routes public traffic correctly

#### Evidence to Submit

- Screenshots from the EKS console and terminal (`kubectl get nodes`, add-ons)
- YAML/JSON exports of critical resources and deployment plan outputs

### 2. Design and Build Dockerized Microservices

#### Guidance

- Build at least three microservices (frontend, API, worker, etc.) with REST/gRPC interfaces
- Provide a local Docker Compose file to validate services before EKS deployment
- Push images to Amazon ECR with versioned tags and perform vulnerability scans

#### Suggested Deliverables

- Dockerfiles for all services (commented, optimized, secure)
- `.dockerignore` and `HEALTHCHECK` directives
- Local `docker-compose.yml` or Makefile for smoke tests
- ECR repositories and scan reports (Trivy, Grype, etc.)

#### Acceptance Criteria

- `docker compose up` runs all containers locally
- Images are non-root and pass security scans with no critical issues
- Images are tagged and pushed to ECR with semantic versioning

#### Evidence to Submit

- Screenshot of containers running locally
- ECR listing with tagged versions

### 3. Configure Kubernetes Services, Ingress, and Load Balancers

#### Guidance

- Internal communication via ClusterIP; external access via Ingress (AWS ALB Controller or NGINX)
- Implement readiness/liveness probes, and use ConfigMaps/Secrets for configuration
- Configure path-based routing, optionally integrate with Route53 using ExternalDNS
- Define NetworkPolicies for namespace traffic control

#### Suggested Deliverables

- Kubernetes manifests or Helm charts for Deployments, Services, Ingress, ConfigMaps, Secrets
- ALB or Ingress annotations (e.g., target type, scheme, health check path)
- NetworkPolicies restricting cross-service traffic

#### Acceptance Criteria

- ALB routes to services correctly; endpoints respond to requests
- Probes maintain pod health and ensure rolling updates are smooth
- NetworkPolicies correctly block unauthorized namespace traffic

#### Evidence to Submit

- ALB console screenshot (target health OK)
- Output of `kubectl describe ingress` and curl/Postman test results

### 4. Implement CI/CD Pipelines for Builds and EKS Deployments

#### Guidance

- Use GitHub Actions or GitLab CI/CD to build, test, scan, and deploy
- PR builds run tests and scans; merges trigger image push and EKS deployment
- Employ Helm or Kustomize for environment-specific configs
- Implement protected branches and approval gates for production

#### Suggested Deliverables

- Workflow YAML files (`.github/workflows/*.yml` or `.gitlab-ci.yml`)
- Helm charts or overlays for dev/staging/prod
- Documentation describing pipeline triggers, secrets, and rollback steps

#### Acceptance Criteria

- Merging to main triggers image build, push, and deployment to EKS
- Approval required for staging/production
- Failed deploys rollback automatically

#### Evidence to Submit

- Screenshots of successful pipeline runs and logs
- Release notes or GitHub Releases showing version history

### 5. Apply Observability Tools (CloudWatch, Prometheus, Grafana)

#### Guidance

- Ship logs to CloudWatch (structured JSON preferred)
- Deploy Prometheus and Grafana with Helm
- Create dashboards for latency, error rate, and resource utilization
- Configure alerting (Alertmanager or SNS) for key SLO violations

#### Suggested Deliverables

- Helm values for Prometheus and Grafana setup
- Dashboards (JSON or screenshots) and at least one alert rule
- Runbook for handling alerts (e.g., scaling, pod crash loops)

#### Acceptance Criteria

- Grafana displays live metrics; alerts trigger on simulated failures
- Logs searchable by pod/service with correlation fields

#### Evidence to Submit

- Dashboard screenshots and example alert notification
- Sample CloudWatch query output

### 6. Manage Persistent Storage and Secrets within EKS

#### Guidance

- Use EBS/EFS CSI drivers and define StorageClasses with retention policies
- Prefer AWS RDS for persistent databases, accessed via Kubernetes Secrets
- Integrate AWS Secrets Manager or External Secrets Operator
- Document backup/restore steps using Velero or snapshots

#### Suggested Deliverables

- PVCs, StorageClasses, and example StatefulSets
- ExternalSecrets or IRSA-based access to AWS Secrets Manager
- Backup/restore runbook

#### Acceptance Criteria

- Stateful workloads retain data across restarts
- Secrets not stored in Git; access controlled via IRSA
- Backup and restore tested in staging

#### Evidence to Submit

- `kubectl get pvc,pv` outputs showing Bound state
- Logs/screenshots from backup and restore tests

### 7. Collaborate Using GitHub/GitLab with Branch Workflows

#### Guidance

- Adopt trunk-based or GitFlow branching; protect main branches
- Use PR templates, issue templates, and CODEOWNERS
- Follow Conventional Commits and pre-commit hooks for consistency
- Track progress in GitHub Projects or GitLab Boards; document retrospectives

#### Suggested Deliverables

- `CONTRIBUTING.md`, PR/issue templates, `CODEOWNERS`
- Project board export or screenshots
- Meeting notes and retrospective summary

#### Acceptance Criteria

- All changes merged via reviewed PRs with passing checks
- Clear commit history tied to issues
- Retrospective identifies at least 3 improvement items

#### Evidence to Submit

- PR screenshots, project board progress, contribution graphs
- Logs showing pre-commit or lint checks passing

## Security & Compliance

### Guidance

Security should be integrated into every phase of your project lifecycle—from image design to cluster deployment and CI/CD automation. Teams must demonstrate how they've applied Defense-in-Depth principles within their EKS environment.

You should focus on the following areas and implement security where necessary:

#### Image and Supply Chain Security

- Use trusted base images (e.g., Amazon Linux, Ubuntu LTS, or Distroless)
- Scan all images for vulnerabilities using Trivy, Grype, or ECR scanning
- Sign and verify images (e.g., cosign or Notary v2) to prevent tampering
- Enforce immutability by using semantic or SHA-based image tags only

#### Cluster and Node Security

- Apply least-privilege for each service
- Disable direct SSH access to worker nodes
- Use Security Groups and NetworkPolicies to restrict inbound/outbound traffic
- Enable Amazon GuardDuty for threat detection and EKS Control Plane Logging for audit trails
- Disable public access to the EKS API endpoint unless absolutely necessary

#### Pod and Workload Security

- Enforce Pod Security Standards (restricted baseline or PSP replacement policies)
- Require non-root containers (`securityContext.runAsNonRoot: true`)
- Define CPU/memory limits to prevent resource abuse
- Enable read-only root filesystems where possible
- Use Kubernetes Secrets (mounted as environment variables or volumes) rather than hard-coded credentials
- Rotate secrets and tokens periodically

#### Network & Data Security

- All inter-service traffic within the cluster should use TLS (Mutual TLS optional)
- Configure Ingress with HTTPS using AWS Certificate Manager (ACM) or Let's Encrypt certificates
- Store sensitive data in AWS Secrets Manager or Parameter Store, integrated via IRSA
- Encrypt all data at rest (EBS, S3, RDS) and in transit
- Optionally enable Service Mesh (e.g., AWS App Mesh or Istio) for secure mTLS communication between pods

#### CI/CD and Access Security

- Store secrets in CI/CD using encrypted vaults (e.g., GitHub Actions Secrets)
- Implement branch protection rules, mandatory reviews, and signed commits (GPG or S/MIME)
- Run automated security scans as part of your pipeline
- Validate Kubernetes manifests with OPA Gatekeeper or Kyverno before deployment
- Restrict deploy tokens and use short-lived AWS credentials for automation

### Suggested Deliverables

- Security Configuration Document (outlining IAM roles, RBAC, and policies)
- Trivy/Grype/ECR Scan Reports from image builds
- NetworkPolicy YAMLs demonstrating restricted communication paths
- Encrypted Secrets Configuration (YAML + explanation)
- Screenshots or outputs from GuardDuty or AWS Security Hub findings

### Acceptance Criteria

- All container images are scanned and free of critical vulnerabilities
- Pods and services adhere to Kubernetes securityContext standards (non-root, least privilege)
- TLS is enforced on all external endpoints (Ingress)
- Sensitive credentials and API keys are never stored in Git
- NetworkPolicies and IAM policies demonstrate least privilege
- GuardDuty, Security Hub, or CloudWatch alerts detect and log potential security events