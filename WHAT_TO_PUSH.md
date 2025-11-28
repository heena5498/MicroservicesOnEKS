# What to Push to GitHub - Checklist

This document outlines what should and should NOT be pushed to GitHub for the BookMyEvent project.

## ✅ What TO Push

### Source Code
- ✅ All Go source files (`cmd/`, `services/`, `internal/`)
- ✅ Frontend source code (`frontend/src/`, `frontend/public/`)
- ✅ Database migrations (`migrations/`)
- ✅ SQLC queries and schemas (`sqlc/`)
- ✅ Configuration files (templates, examples)

### Configuration Files
- ✅ `docker-compose.yml` (development defaults are OK)
- ✅ `Makefile`
- ✅ `go.mod` and `go.sum` (for reproducible builds)
- ✅ `package.json` and `bun.lock` (frontend dependencies)
- ✅ Kubernetes manifests (`k8s/*.yaml`) - **with development defaults**
- ✅ `nginx.conf`
- ✅ **All Dockerfiles** (`Dockerfile-*`) - **These are build files and WILL be pushed**:
  - ✅ `Dockerfile-booking-service`
  - ✅ `Dockerfile-event-service`
  - ✅ `Dockerfile-frontend`
  - ✅ `Dockerfile-init-container`
  - ✅ `Dockerfile-search-service`
  - ✅ `Dockerfile-user-service`

### Documentation
- ✅ `README.md`
- ✅ `GITHUB_SETUP.md`
- ✅ `WHAT_TO_PUSH.md` (this file)
- ✅ `DEPLOYMENT_GUIDE.md`
- ✅ `EKS_DEPLOYMENT_GUIDE.md`
- ✅ All files in `docs/` directory
- ✅ README files in subdirectories
- ✅ Architecture diagrams and schemas
- ❌ **Excluded**: `DNS_SETUP_GUIDE.md`, `DNS_SETUP_INSTRUCTIONS.md`
- ❌ **Excluded**: `QUICK_REFERENCE.md`, `HOW_TO_TEST.md`, `BOOKING_EVENT_ARCHITECTURE.md`
- ❌ **Excluded**: PDF files (ENPM818R*.pdf)

### Scripts
- ✅ **EKS Deployment Scripts** (required):
  - ✅ `scripts/eks/deploy-complete.ps1` - Main deployment script
  - ✅ `scripts/eks/5-cleanup.ps1` - Cleanup script
- ✅ Shell scripts (`.sh`) in `scripts/` directory
- ✅ Python scripts for testing/utilities
- ✅ Other utility scripts in `scripts/` (migrations, seeding, etc.)
- ❌ **Excluded**: Root-level PowerShell scripts (build-push-all.ps1, fix-*.ps1, etc.)
- ❌ **Excluded**: Other EKS scripts (1-create-ecr-repos.ps1, 2-build-push-images.ps1, etc.)

### Example/Template Files
- ✅ `k8s/02-secrets.yaml.example`
- ✅ `k8s/03-env-file-configmap.yaml.example`
- ✅ Any `.example` or `.template` files

### Project Structure
- ✅ `.gitignore`
- ✅ `dbml-schemas/` (database schema definitions)
- ✅ `init-container/` (initialization container code)

---

## ❌ What NOT to Push

### Secrets and Credentials
- ❌ Real production secrets in `k8s/02-secrets.yaml`
- ❌ Real production values in `k8s/03-env-file-configmap.yaml`
- ❌ `.env` files with real credentials
- ❌ AWS access keys or credentials
- ❌ Private keys (`.pem`, `.key` files)
- ❌ Any file containing real passwords, tokens, or API keys

### Build Artifacts
- ❌ `bin/` directory (compiled binaries)
- ❌ `dist/` or `build/` directories
- ❌ `*.exe`, `*.dll`, `*.so` files
- ❌ Frontend build output (`frontend/dist/`)

### Dependencies
- ❌ `node_modules/` (frontend dependencies)
- ❌ `vendor/` (if using Go vendoring)

### IDE and Editor Files
- ❌ `.vscode/` (unless sharing workspace settings)
- ❌ `.idea/` (IntelliJ IDEA)
- ❌ `*.swp`, `*.swo` (Vim swap files)

### OS Files
- ❌ `.DS_Store` (macOS)
- ❌ `Thumbs.db` (Windows)
- ❌ `desktop.ini`

### Logs and Temporary Files
- ❌ `*.log` files
- ❌ `tmp/`, `temp/` directories
- ❌ `*.tmp`, `*.bak` files

### Docker Data
- ❌ Docker volumes (`postgres_data/`, `redis_data/`, etc.)
- ❌ Docker data directories

### Test Data (if large)
- ❌ Large test datasets
- ❌ Generated test files

---

## 🔐 Security Best Practices

### Before Pushing

1. **Review Secrets Files**:
   ```bash
   # Check for hardcoded secrets
   grep -r "password\|secret\|key\|token" --include="*.yaml" --include="*.yml" k8s/
   ```

2. **Verify .gitignore**:
   - Ensure `.env` is in `.gitignore`
   - Ensure `node_modules/` is ignored
   - Ensure build artifacts are ignored

3. **Use Example Files**:
   - Keep `k8s/02-secrets.yaml` with development defaults (OK for team repo)
   - Provide `k8s/02-secrets.yaml.example` with placeholders
   - Document in `GITHUB_SETUP.md` how to set up secrets

4. **Check for Accidental Commits**:
   ```bash
   # Before committing, check what will be added
   git status
   git diff --cached
   ```

### If You Accidentally Commit Secrets

1. **Immediately rotate the secrets** (change passwords, regenerate keys)
2. **Remove from Git history**:
   ```bash
   # Remove file from history (use with caution)
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch path/to/secret-file" \
     --prune-empty --tag-name-filter cat -- --all
   ```
3. **Force push** (coordinate with team):
   ```bash
   git push origin --force --all
   ```

---

## 📋 Pre-Push Checklist

Before pushing to GitHub, verify:

- [ ] No `.env` files are staged
- [ ] No real production secrets in `k8s/02-secrets.yaml`
- [ ] `go.sum` is included (for reproducible builds)
- [ ] `node_modules/` is not included
- [ ] Build artifacts (`bin/`, `dist/`) are not included
- [ ] All documentation is up to date
- [ ] Example/template files are provided for secrets
- [ ] `.gitignore` is properly configured
- [ ] No large binary files or test datasets
- [ ] No IDE-specific files (unless intentionally shared)

---

## 🚀 Initial Push Commands

```bash
# 1. Initialize git (if not already done)
git init

# 2. Add all files (respects .gitignore)
git add .

# 3. Review what will be committed
git status

# 4. Commit
git commit -m "Initial commit: BookMyEvent microservices platform"

# 5. Add remote (replace with your GitHub repo URL)
git remote add origin https://github.com/your-org/bookmyevent-ily.git

# 6. Push to GitHub
git branch -M main
git push -u origin main
```

---

## 📝 Notes

- **Development Defaults**: It's OK to keep development defaults (like `postgres/postgres` passwords) in the repository for team collaboration, as long as:
  - They're clearly marked as development-only
  - Production deployment instructions emphasize changing them
  - Example files with placeholders are provided

- **Team Repository**: Since this is for team access, some development defaults are acceptable. For public repositories, use placeholders everywhere.

- **CI/CD**: If setting up CI/CD, use GitHub Secrets or your CI platform's secret management for production credentials.

---

## 🔗 Related Documentation

- **Setup Guide**: See `GITHUB_SETUP.md` for team member onboarding
- **Main README**: See `README.md` for project overview
- **Deployment**: See `DEPLOYMENT_GUIDE.md` and `EKS_DEPLOYMENT_GUIDE.md`

