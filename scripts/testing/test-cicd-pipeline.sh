#!/bin/bash
# =============================================================================
# Script: test-cicd-pipeline.sh
# Description: Interactive testing script for CI/CD pipeline
# Usage: ./scripts/testing/test-cicd-pipeline.sh
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo "============================================================"
echo "  CI/CD Pipeline Testing Script"
echo "============================================================"
echo ""

# Helper function for tests
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -ne "${BLUE}Testing:${NC} $test_name ... "
    
    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Check if IAM user exists
echo -e "${YELLOW}[Phase 1: IAM Setup]${NC}"
echo "============================================================"

run_test "IAM user 'github-actions-bookmyevent' exists" \
    "aws iam get-user --user-name github-actions-bookmyevent"

run_test "IAM user has ECR policy attached" \
    "aws iam list-attached-user-policies --user-name github-actions-bookmyevent | grep -q AmazonEC2ContainerRegistryPowerUser"

run_test "IAM user has EKS policy attached" \
    "aws iam list-user-policies --user-name github-actions-bookmyevent | grep -q EKSAccess"

echo ""

# Test 2: Check GitHub workflows
echo -e "${YELLOW}[Phase 2: GitHub Workflows]${NC}"
echo "============================================================"

run_test "CI workflow file exists" \
    "test -f .github/workflows/ci-build-and-push.yml"

run_test "CD workflow file exists" \
    "test -f .github/workflows/cd-deploy-to-eks.yml"

run_test "PR validation workflow exists" \
    "test -f .github/workflows/pr-validation.yml"

echo ""

# Test 3: Check EKS access
echo -e "${YELLOW}[Phase 3: EKS Configuration]${NC}"
echo "============================================================"

run_test "kubectl can access cluster" \
    "kubectl cluster-info"

run_test "GitHub Actions user in aws-auth ConfigMap" \
    "kubectl get configmap aws-auth -n kube-system -o yaml | grep -q github-actions-bookmyevent"

run_test "Namespace 'bookmyevent' exists" \
    "kubectl get namespace bookmyevent"

echo ""

# Test 4: Check ECR repositories
echo -e "${YELLOW}[Phase 4: ECR Repositories]${NC}"
echo "============================================================"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="${AWS_REGION:-us-east-1}"

for SERVICE in user-service event-service search-service booking-service frontend init-container; do
    run_test "ECR repository 'bookmyevent/$SERVICE' exists" \
        "aws ecr describe-repositories --repository-names bookmyevent/$SERVICE --region $AWS_REGION"
done

echo ""

# Test 5: Validate workflow syntax
echo -e "${YELLOW}[Phase 5: Workflow Validation]${NC}"
echo "============================================================"

if command -v yamllint &> /dev/null; then
    run_test "CI workflow YAML is valid" \
        "yamllint -d relaxed .github/workflows/ci-build-and-push.yml"
    
    run_test "CD workflow YAML is valid" \
        "yamllint -d relaxed .github/workflows/cd-deploy-to-eks.yml"
    
    run_test "PR workflow YAML is valid" \
        "yamllint -d relaxed .github/workflows/pr-validation.yml"
else
    echo -e "${YELLOW}⚠️  yamllint not installed, skipping YAML validation${NC}"
fi

echo ""

# Test 6: Check Kubernetes deployments
echo -e "${YELLOW}[Phase 6: Current Deployment Status]${NC}"
echo "============================================================"

if kubectl get namespace bookmyevent > /dev/null 2>&1; then
    run_test "PostgreSQL deployment exists" \
        "kubectl get deployment postgres -n bookmyevent"
    
    run_test "Redis deployment exists" \
        "kubectl get deployment redis -n bookmyevent"
    
    run_test "Elasticsearch deployment exists" \
        "kubectl get deployment elasticsearch -n bookmyevent"
    
    for SERVICE in user-service event-service search-service booking-service; do
        run_test "$SERVICE deployment exists" \
            "kubectl get deployment $SERVICE -n bookmyevent"
    done
    
    run_test "NGINX gateway deployment exists" \
        "kubectl get deployment nginx-gateway -n bookmyevent"
    
    run_test "Frontend deployment exists" \
        "kubectl get deployment frontend -n bookmyevent"
else
    echo -e "${YELLOW}⚠️  Namespace 'bookmyevent' not found. Deployments may not exist yet.${NC}"
fi

echo ""

# Test 7: Check if services have external IPs
echo -e "${YELLOW}[Phase 7: LoadBalancer Status]${NC}"
echo "============================================================"

if kubectl get svc -n bookmyevent nginx-gateway > /dev/null 2>&1; then
    API_URL=$(kubectl get svc nginx-gateway -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "$API_URL" ] && [ "$API_URL" != "<pending>" ]; then
        echo -e "${GREEN}✅ PASSED${NC} API Gateway has external URL: $API_URL"
        ((TESTS_PASSED++))
        
        # Try to access health endpoint
        if curl -f -s "http://$API_URL/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ PASSED${NC} API Gateway health check responds"
            ((TESTS_PASSED++))
        else
            echo -e "${YELLOW}⚠️  WARNING${NC} API Gateway exists but health check not responding"
        fi
    else
        echo -e "${YELLOW}⚠️  WARNING${NC} API Gateway LoadBalancer IP is pending"
    fi
    
    FRONTEND_URL=$(kubectl get svc frontend -n bookmyevent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "$FRONTEND_URL" ] && [ "$FRONTEND_URL" != "<pending>" ]; then
        echo -e "${GREEN}✅ PASSED${NC} Frontend has external URL: $FRONTEND_URL"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠️  WARNING${NC} Frontend LoadBalancer IP is pending"
    fi
else
    echo -e "${YELLOW}⚠️  Services not deployed yet${NC}"
fi

echo ""

# Summary
echo "============================================================"
echo "  Test Summary"
echo "============================================================"
echo ""
echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    echo ""
    echo "Your CI/CD pipeline is ready!"
    echo ""
    echo "Next steps:"
    echo "  1. Add GitHub secrets (see CI_CD_QUICKSTART.md)"
    echo "  2. Push code to trigger the pipeline"
    echo "  3. Watch workflows in GitHub Actions tab"
    echo ""
    exit 0
else
    echo -e "${RED}⚠️  Some tests failed. Please review the errors above.${NC}"
    echo ""
    echo "Common issues:"
    echo "  - Run setup script: ./scripts/github-actions/setup-github-actions.sh"
    echo "  - Verify AWS credentials are configured"
    echo "  - Check EKS cluster is running"
    echo ""
    echo "See CI_CD_TESTING_GUIDE.md for troubleshooting"
    echo ""
    exit 1
fi
