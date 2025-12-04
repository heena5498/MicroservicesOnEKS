#!/bin/bash
set -e

echo "=========================================="
echo "Repository Reorganization Script"
echo "=========================================="
echo ""

REPO_ROOT="/Users/heenakhan/Documents/ENPM818R-Virtualization & Containerization/project-eks/eks-microservices"
cd "$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Creating new directory structure${NC}"
mkdir -p build
mkdir -p scripts/testing

echo -e "${GREEN}✓ Directories created${NC}"
echo ""

echo -e "${YELLOW}Step 2: Moving test scripts to scripts/testing/${NC}"
# Move all test scripts from tests-scripts to scripts/testing
if [ -d "tests-scripts" ]; then
    for file in tests-scripts/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if [ ! -f "scripts/testing/$filename" ]; then
                echo "  Moving: $filename"
                mv "$file" "scripts/testing/"
            else
                echo "  Duplicate found, removing: tests-scripts/$filename"
                rm "$file"
            fi
        fi
    done
    rmdir tests-scripts 2>/dev/null || echo "  tests-scripts directory not empty, keeping it"
fi

# Move test scripts from root scripts/ to scripts/testing/
test_scripts=(
    "scripts/test_event_service.sh"
    "scripts/stress-test.sh"
    "scripts/stress-test-concurrent.sh"
)

for script in "${test_scripts[@]}"; do
    if [ -f "$script" ]; then
        filename=$(basename "$script")
        if [ ! -f "scripts/testing/$filename" ]; then
            echo "  Moving: $script to scripts/testing/"
            mv "$script" "scripts/testing/"
        else
            echo "  Duplicate found, removing: $script"
            rm "$script"
        fi
    fi
done

echo -e "${GREEN}✓ Test scripts consolidated${NC}"
echo ""

echo -e "${YELLOW}Step 3: Moving build-related files to build/${NC}"
# Move Dockerfiles to build/
dockerfiles=(
    "Dockerfile-booking-service"
    "Dockerfile-event-service"
    "Dockerfile-frontend"
    "Dockerfile-init-container"
    "Dockerfile-search-service"
    "Dockerfile-user-service"
)

for dockerfile in "${dockerfiles[@]}"; do
    if [ -f "$dockerfile" ]; then
        echo "  Moving: $dockerfile to build/"
        mv "$dockerfile" "build/"
    fi
done

# Move docker-compose and Makefile to build/
if [ -f "docker-compose.yml" ]; then
    echo "  Moving: docker-compose.yml to build/"
    mv "docker-compose.yml" "build/"
fi

if [ -f "Makefile" ]; then
    echo "  Moving: Makefile to build/"
    mv "Makefile" "build/"
fi

# Move root nginx.conf to build/ (frontend has its own)
if [ -f "nginx.conf" ]; then
    echo "  Moving: nginx.conf to build/"
    mv "nginx.conf" "build/"
fi

echo -e "${GREEN}✓ Build files moved${NC}"
echo ""

echo -e "${YELLOW}Step 4: Removing PowerShell scripts${NC}"
ps1_files=(
    "scripts/eks/deploy-complete.ps1"
    "scripts/eks/5-cleanup.ps1"
)

for ps1 in "${ps1_files[@]}"; do
    if [ -f "$ps1" ]; then
        echo "  Removing: $ps1"
        rm "$ps1"
    fi
done

echo -e "${GREEN}✓ PowerShell scripts removed${NC}"
echo ""

echo -e "${YELLOW}Step 5: Removing redundant documentation${NC}"
redundant_docs=(
    "BOOKING_EVENT_ARCHITECTURE.md"
    "HOW_TO_TEST.md"
    "SSL_SETUP_GUIDE.md"
    ".env.production"
    "WHAT_TO_PUSH.md"
)

for doc in "${redundant_docs[@]}"; do
    if [ -f "$doc" ]; then
        echo "  Removing: $doc"
        rm "$doc"
    fi
done

# Remove .DS_Store if exists
if [ -f ".DS_Store" ]; then
    echo "  Removing: .DS_Store"
    rm ".DS_Store"
fi

echo -e "${GREEN}✓ Redundant files removed${NC}"
echo ""

echo -e "${YELLOW}Step 6: Consolidating deployment guides${NC}"
# Keep EKS_DEPLOYMENT_GUIDE.md (more comprehensive), remove DEPLOYMENT_GUIDE.md
if [ -f "DEPLOYMENT_GUIDE.md" ]; then
    echo "  Removing: DEPLOYMENT_GUIDE.md (content in EKS_DEPLOYMENT_GUIDE.md)"
    rm "DEPLOYMENT_GUIDE.md"
fi

echo -e "${GREEN}✓ Deployment guides consolidated${NC}"
echo ""

echo -e "${YELLOW}Step 7: Renaming uppercase files to lowercase${NC}"
# Rename markdown files to lowercase
uppercase_files=(
    "CI_CD_GUIDE.md:ci-cd-guide.md"
    "CI_CD_QUICKSTART.md:ci-cd-quickstart.md"
    "CI_CD_TESTING_GUIDE.md:ci-cd-testing-guide.md"
    "EKS_DEPLOYMENT_GUIDE.md:eks-deployment-guide.md"
    "GITHUB_SETUP.md:github-setup.md"
    "README.md:readme.md"
    "SECRETS_MANAGER_GUIDE.md:secrets-manager-guide.md"
    "SECRETS_QUICKSTART.md:secrets-quickstart.md"
    "TESTING_QUICKSTART.md:testing-quickstart.md"
)

for mapping in "${uppercase_files[@]}"; do
    old_name="${mapping%%:*}"
    new_name="${mapping##*:}"
    if [ -f "$old_name" ]; then
        # Skip README.md - keep it uppercase for GitHub convention
        if [ "$old_name" = "README.md" ]; then
            echo "  Skipping: README.md (GitHub convention)"
            continue
        fi
        echo "  Renaming: $old_name → $new_name"
        mv "$old_name" "$new_name"
    fi
done

# Rename docs/ files to lowercase
if [ -d "docs" ]; then
    cd docs
    for file in *.md; do
        if [ -f "$file" ]; then
            lowercase=$(echo "$file" | tr '[:upper:]' '[:lower:]')
            if [ "$file" != "$lowercase" ]; then
                # Skip README.md
                if [ "$file" = "README.md" ]; then
                    continue
                fi
                echo "  Renaming: docs/$file → docs/$lowercase"
                mv "$file" "$lowercase"
            fi
        fi
    done
    cd ..
fi

# Rename scripts/testing/ markdown files
if [ -d "scripts/testing" ]; then
    cd scripts/testing
    for file in *.md; do
        if [ -f "$file" ]; then
            lowercase=$(echo "$file" | tr '[:upper:]' '[:lower:]')
            if [ "$file" != "$lowercase" ]; then
                if [ "$file" = "README.md" ]; then
                    continue
                fi
                echo "  Renaming: scripts/testing/$file → scripts/testing/$lowercase"
                mv "$file" "$lowercase"
            fi
        fi
    done
    cd "$REPO_ROOT"
fi

echo -e "${GREEN}✓ Files renamed to lowercase${NC}"
echo ""

echo -e "${YELLOW}Step 8: Updating .gitignore${NC}"
# Update .gitignore to reflect new structure
cat > .gitignore << 'EOF'
# Go build artifacts
/bin/
*.exe
*.exe~
*.dll
*.so
*.dylib

# Go test files
*.test

# Go coverage files
*.out
coverage.html
coverage.txt

# Environment variables and secrets
.env
.env.local
.env.*.local
*.env
!*.env.example
!*.env.template

# Docker volumes and data
/data/
docker-data/
postgres_data/
redis_data/
elasticsearch_data/

# IDE files
.vscode/
.idea/
*.swp
*.swo
*.sublime-*

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
desktop.ini

# Logs
*.log
logs/
*.log.*

# Temporary files
tmp/
temp/
*.tmp
*.bak
*.swp
*~

# Node modules (frontend)
node_modules/
frontend/node_modules/
frontend/dist/
frontend/.vite/

# Python cache
__pycache__/
*.py[cod]
*$py.class
*.pyc
.pytest_cache/
*.egg-info/

# AWS credentials
.aws/
*.pem
*.key
github-actions-credentials.txt
aws-auth-backup*.yaml

# Kubernetes secrets
k8s/secrets.local.yaml
k8s/*-secrets.yaml
!k8s/02-secrets.yaml.example

# Build outputs
dist/
build/dist/
build/build/
*.tar.gz
*.zip
EOF

echo -e "${GREEN}✓ .gitignore updated${NC}"
echo ""

echo -e "${GREEN}=========================================="
echo -e "Reorganization Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Summary of changes:"
echo "  ✓ Test scripts consolidated in scripts/testing/"
echo "  ✓ Build files moved to build/"
echo "  ✓ PowerShell scripts removed"
echo "  ✓ Redundant documentation removed"
echo "  ✓ Files renamed to lowercase"
echo "  ✓ .gitignore updated"
echo ""
echo "New structure:"
echo "  build/                    - All Dockerfiles, docker-compose.yml, Makefile, nginx.conf"
echo "  scripts/testing/          - All test scripts consolidated"
echo "  docs/                     - Lowercase documentation"
echo "  Root documentation        - Lowercase filenames (except README.md)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review the changes: git status"
echo "  2. Update any hardcoded paths in scripts"
echo "  3. Update documentation references"
echo "  4. Test the reorganized structure"
echo ""
