# GitHub Setup Guide for Team Members

This guide will help you set up the BookMyEvent project from GitHub and deploy it in your own environment.

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

### Required Tools
- **Git** - [Download](https://git-scm.com/downloads)
- **Docker** & **Docker Compose** - [Download](https://www.docker.com/get-started)
- **Go** (v1.21+) - [Download](https://go.dev/dl/)
- **Make** - Usually pre-installed on Linux/Mac. For Windows, use [Chocolatey](https://chocolatey.org/) or WSL
- **Node.js** (v18+) & **Bun** - For frontend development - [Bun Download](https://bun.sh/)

### Optional (for Kubernetes/EKS deployment)
- **kubectl** - [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **AWS CLI** - [Installation Guide](https://aws.amazon.com/cli/)
- **eksctl** - [Installation Guide](https://eksctl.io/installation/)

---

## 🚀 Quick Start (Local Development)

### Step 1: Clone the Repository

```bash
git clone <repository-url>
cd bookmyevent-ily
```

### Step 2: Set Up Environment Variables

The project uses environment variables for configuration. For local development, you can use the defaults in `docker-compose.yml`, but for production or custom setups:

1. **Create a `.env` file** (optional for local dev, required for production):
   ```bash
   # Copy the example template (if available)
   # Or create your own based on the values in docker-compose.yml
   ```

2. **For Kubernetes deployments**, you'll need to create your own secrets:
   ```bash
   # Copy the example files
   cp k8s/02-secrets.yaml.example k8s/02-secrets.yaml
   cp k8s/03-env-file-configmap.yaml.example k8s/03-env-file-configmap.yaml
   
   # Edit the files and replace all placeholder values with secure secrets
   # Generate secure secrets:
   openssl rand -base64 32  # For JWT_SECRET and INTERNAL_API_KEY
   openssl rand -base64 24  # For POSTGRES_PASSWORD
   ```

### Step 3: Start Development Environment

```bash
# One command to set up everything
make dev-setup-full
```

This will:
- Start PostgreSQL, Redis, and Elasticsearch
- Run database migrations
- Start all microservices
- Seed test data

### Step 4: Access the Application

- **API Gateway**: `http://localhost/`
- **Frontend**: `http://localhost/` (served through nginx gateway)
- **Individual Services**:
  - User Service: `http://localhost:8001`
  - Event Service: `http://localhost:8002`
  - Search Service: `http://localhost:8003`
  - Booking Service: `http://localhost:8004`

### Step 5: Test the Setup

```bash
# Health check
curl http://localhost/health

# Get events
curl http://localhost/api/event/events

# Login (test user)
curl -X POST http://localhost/api/user/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "atlanuser1@mail.com", "password": "11111111"}'
```

---

## 🔐 Security Configuration

### ⚠️ Important: Before Production Deployment

**NEVER commit real secrets to Git!** The repository contains example/template files with placeholders.

### For Local Development
- Default credentials in `docker-compose.yml` are fine for local testing
- The `k8s/02-secrets.yaml` file contains development defaults

### For Production Deployment

1. **Generate Secure Secrets**:
   ```bash
   # JWT Secret (32 bytes)
   openssl rand -base64 32
   
   # Internal API Key (32 bytes)
   openssl rand -base64 32
   
   # PostgreSQL Password (24 bytes)
   openssl rand -base64 24
   ```

2. **Update Kubernetes Secrets**:
   - Edit `k8s/02-secrets.yaml` with your generated secrets
   - Edit `k8s/03-env-file-configmap.yaml` with your database URLs
   - **DO NOT commit these files with real production secrets!**

3. **Use Secret Management** (Recommended for production):
   - **Sealed Secrets**: Encrypt secrets before committing
   - **External Secrets Operator**: Pull secrets from AWS Secrets Manager, HashiCorp Vault, etc.
   - **Kubernetes Secrets**: Store in a secure secret management system

---

## 🐳 Docker Deployment

### Production Deployment with Docker Compose

```bash
# Complete deployment (deploy + migrate + seed)
make deploy-full

# Or step by step:
make deploy-production    # Start services
make setup-db            # Run migrations
make seed-data-production # Seed test data
```

### Stop Services

```bash
make stop-production
# or
docker-compose down
```

---

## ☸️ Kubernetes/EKS Deployment

### Prerequisites
- AWS account configured
- AWS CLI configured (`aws configure`)
- kubectl and eksctl installed

### Quick EKS Deployment

```bash
# Set environment variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME="bookmyevent-cluster"

# One-command deployment (takes ~20 minutes)
# Windows PowerShell:
.\scripts\eks\deploy-complete.ps1

# Linux/Mac:
./scripts/eks/deploy-complete.sh
```

### Manual EKS Deployment

See `EKS_DEPLOYMENT_GUIDE.md` for detailed step-by-step instructions.

---

## 📁 Project Structure

```
bookmyevent-ily/
├── cmd/                    # Service entry points
│   ├── user-service/
│   ├── event-service/
│   ├── search-service/
│   └── booking-service/
├── services/               # Business logic
├── internal/               # Shared packages
│   ├── auth/              # JWT, password hashing
│   ├── config/            # Configuration loading
│   ├── database/          # DB connections
│   └── repository/        # Database queries (sqlc generated)
├── k8s/                    # Kubernetes manifests
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secrets.yaml     # ⚠️ Update with your secrets
│   ├── 03-env-file-configmap.yaml
│   ├── infrastructure/    # Postgres, Redis, Elasticsearch
│   ├── services/          # Microservice deployments
│   └── jobs/              # Migration jobs
├── migrations/             # Database migrations
├── frontend/               # React frontend
├── scripts/                # Deployment and utility scripts
├── docker-compose.yml      # Local development
├── Makefile               # Common commands
└── README.md              # Main documentation
```

---

## 🛠️ Common Commands

### Development
```bash
make dev-setup-full        # Full dev setup
make kill-services         # Stop all services
make docker-down           # Stop Docker containers
make logs-production       # View service logs
```

### Database
```bash
make setup-db              # Run migrations
make seed-db               # Seed test data
make reset-data            # Clean all data
```

### Building
```bash
make build                 # Build all services
make build-frontend        # Build frontend only
```

See `Makefile` or run `make help` for all available commands.

---

## 🧪 Testing

### Test Data
The seeding script creates:
- **Test Users**: 
  - `atlanuser1@mail.com` / `11111111`
  - `atlanuser2@mail.com` / `11111111`
- **Admin**: 
  - `atlanadmin@mail.com` / `11111111`
- **Events**: 10 diverse events

### Running Tests
```bash
# See testing guides in docs/ directory
# Or use the test scripts in tests-scripts/
```

---

## 🐛 Troubleshooting

### Services won't start
1. Check Docker is running: `docker ps`
2. Check ports are available: `netstat -an | grep -E '8001|8002|8003|8004|5434|6380|9200'`
3. Check logs: `make logs-production` or `docker-compose logs`

### Database connection errors
1. Ensure PostgreSQL is running: `docker ps | grep postgres`
2. Check database URLs in your config
3. Verify migrations ran: `make setup-db`

### Frontend not loading
1. Check nginx gateway is running
2. Verify API URLs in frontend config
3. Check browser console for errors

---

## 📚 Additional Documentation

- **Main README**: `README.md` - Overview and architecture
- **API Documentation**: `docs/*_API_DOCUMENTATION.md`
- **EKS Deployment**: `EKS_DEPLOYMENT_GUIDE.md`
- **Testing Guides**: `docs/*_TESTING_GUIDE.md`
- **Architecture**: `docs/architecture.md`

---

## 🔄 Contributing

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make your changes
3. Test locally
4. Commit: `git commit -m "Add your feature"`
5. Push: `git push origin feature/your-feature`
6. Create a Pull Request

### Before Committing
- ✅ Ensure `.env` files are not committed (check `.gitignore`)
- ✅ Don't commit real secrets or credentials
- ✅ Update documentation if needed
- ✅ Test your changes locally

---

## ❓ Getting Help

- Check the documentation in `docs/` directory
- Review `README.md` for architecture details
- Check existing issues in the repository
- Contact the team lead or project maintainer

---

## ✅ Checklist for New Team Members

- [ ] Cloned the repository
- [ ] Installed all prerequisites (Docker, Go, Make, etc.)
- [ ] Successfully ran `make dev-setup-full`
- [ ] Can access the API at `http://localhost/`
- [ ] Can login with test user credentials
- [ ] Reviewed security configuration section
- [ ] Set up your own secrets for production (if deploying)
- [ ] Read the main README.md
- [ ] Familiarized yourself with the project structure

Welcome to the team! 🎉

