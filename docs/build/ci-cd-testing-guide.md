# CI/CD Pipeline Testing Guide

**Course:** ENPM818R - Virtualization & Containerization  
**Team:** Group 5 | Fall 2025

---

## Overview

This guide covers testing and validation of the GitHub Actions CI/CD pipeline for the BookMyEvent platform.

---

## Test Suite: Integration Tests

### Location
`scripts/testing/test-endpoints.sh`

### Purpose
Validates complete user authentication flow through production ALB and nginx-gateway.

### Test Coverage (11 Tests)

#### 1. Health Check
```bash
Test: GET /api/v1/users/health
Expected: 200 OK
Validates: Service availability, ALB routing
```

#### 2. User Registration
```bash
Test: POST /api/v1/users/register
Payload: {
  "email": "test_<timestamp>@example.com",
  "password": "SecurePass123",
  "full_name": "Test User"
}
Expected: 201 Created
Returns: user_id, access_token, refresh_token
Validates: User creation, JWT token generation
```

#### 3. Login Authentication
```bash
Test: POST /api/v1/users/login
Payload: {
  "email": "test_<timestamp>@example.com",
  "password": "SecurePass123"
}
Expected: 200 OK
Returns: access_token, refresh_token
Validates: Authentication, token refresh
```

#### 4. Profile Access (Protected Route)
```bash
Test: GET /api/v1/users/profile
Header: Authorization: Bearer <access_token>
Expected: 200 OK
Returns: User profile data
Validates: JWT validation, protected routes
```

#### 5. Token Refresh
```bash
Test: POST /api/v1/users/refresh
Payload: {
  "refresh_token": "<refresh_token>"
}
Expected: 200 OK
Returns: new access_token, new refresh_token
Validates: Token rotation, session management
```

#### 6. Logout
```bash
Test: POST /api/v1/users/logout
Payload: {
  "refresh_token": "<refresh_token>"
}
Expected: 200 OK
Validates: Token invalidation
```

#### 7. Revoked Token Test
```bash
Test: POST /api/v1/users/refresh (with revoked token)
Expected: 401 Unauthorized
Validates: Token blacklist, security
```

#### 8. Expired Token Test
```bash
Test: GET /api/v1/users/profile (without token)
Expected: 401 Unauthorized
Validates: Authentication requirement
```

#### 9. Duplicate Email Test
```bash
Test: POST /api/v1/users/register (same email)
Expected: 409 Conflict
Validates: Unique constraint, error handling
```

#### 10. Invalid Credentials Test
```bash
Test: POST /api/v1/users/login (wrong password)
Expected: 401 Unauthorized
Validates: Authentication failure handling
```

#### 11. Protected Route Without Auth
```bash
Test: GET /api/v1/users/profile (no Authorization header)
Expected: 401 Unauthorized
Validates: Security enforcement
```

---

## Running Tests

### Automated (CI/CD Pipeline)
Tests run automatically after deployment:
```yaml
# In .github/workflows/deploy-bookmyevent.yaml
- name: Run Integration Tests
  run: |
    chmod +x scripts/testing/test-endpoints.sh
    ./scripts/testing/test-endpoints.sh
```

### Manual (Local)
```bash
# From repository root
cd tests-scripts
chmod +x test-endpoints.sh
./test-endpoints.sh
```

**Expected Output:**
```
=== BookMyEvent Integration Tests ===
Testing endpoint: k8s-bookmyev-bookmyev-xxxxx.us-east-1.elb.amazonaws.com

1. Testing Health Check...
✓ PASS: Health check returned 200

2. Testing User Registration...
✓ PASS: User registration returned 201
   User ID: 1234

3. Testing Login...
✓ PASS: Login returned 200

4. Testing Protected Route (Profile)...
✓ PASS: Profile access returned 200

5. Testing Token Refresh...
✓ PASS: Token refresh returned 200

6. Testing Logout...
✓ PASS: Logout returned 200

7. Testing Revoked Token...
✓ PASS: Revoked token returned 401

8. Testing Expired Token...
✓ PASS: Expired token returned 401

9. Testing Duplicate Email...
✓ PASS: Duplicate email returned 409

10. Testing Invalid Credentials...
✓ PASS: Invalid credentials returned 401

11. Testing Protected Route Without Auth...
✓ PASS: Unauthorized access returned 401

=== All Integration Tests Passed Successfully! ===
Total: 11/11 tests passed
```

---

## Additional Test Scripts

### 1. Booking Flow Test
**File:** `scripts/testing/test_booking_flow.py`

**Purpose:** Test complete booking workflow

**Tests:**
- User registration (unique emails with timestamp)
- Admin registration
- Event creation
- Event search
- Booking creation
- Booking verification

**Run:**
```bash
python3 scripts/testing/test_booking_flow.py
```

**Known Issue:** Admin registration returns 500 (under investigation)

---

### 2. Search API Test
**File:** `scripts/testing/comprehensive_search_api_test.py`

**Purpose:** Comprehensive search functionality testing

**Tests:**
- Gateway health check
- Search by keyword
- Search by location
- Search by date range
- Search by category
- Pagination
- Sorting
- Filter combinations

**Run:**
```bash
python3 scripts/testing/comprehensive_search_api_test.py
```

**Note:** Uses conditional health check logic:
- **Localhost:** Checks individual service `/healthz` endpoints
- **Production:** Checks nginx-gateway `/health` endpoint

---

## Pipeline Validation

### Build Stage Validation

#### Docker Build Test
```bash
# Each service must build successfully
docker build -f Dockerfile-user-service -t user-service:test .
docker build -f Dockerfile-event-service -t event-service:test .
docker build -f Dockerfile-search-service -t search-service:test .
docker build -f Dockerfile-booking-service -t booking-service:test .
docker build -f Dockerfile-frontend -t frontend:test .
docker build -f Dockerfile-init-container -t init-container:test .
```

**Expected:** All builds complete without errors

#### Trivy Scan Test
```bash
# Scan for vulnerabilities
trivy image --severity HIGH,CRITICAL user-service:test

# Expected: No HIGH or CRITICAL vulnerabilities
# If vulnerabilities found: Pipeline blocks deployment
```

**Acceptable Results:**
- 0 HIGH/CRITICAL vulnerabilities: ✅ Pass
- Any HIGH/CRITICAL: ❌ Fail (update base image or suppress)

#### ECR Push Test
```bash
# Tag and push
docker tag user-service:test ${ECR_REGISTRY}/bookmyevent/user-service:${TAG}
docker push ${ECR_REGISTRY}/bookmyevent/user-service:${TAG}

# Verify in ECR
aws ecr describe-images \
  --repository-name bookmyevent/user-service \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1]'
```

**Expected:** Image appears in ECR with correct tag

---

### Deploy Stage Validation

#### Migration Job Test
```bash
# Check job status
kubectl get jobs -n bookmyevent

# Expected:
NAME                        COMPLETIONS   DURATION   AGE
run-migrations-rds-xxxxx    1/1           45s        2m

# Check logs
kubectl logs -n bookmyevent job/run-migrations-rds-xxxxx

# Expected output includes:
# - Database creation statements
# - Migration execution
# - Success confirmation
```

**Timeout:** 120 seconds  
**Expected:** Job completes successfully

#### Helm Deployment Test
```bash
# Check Helm release
helm list -n bookmyevent

# Expected:
NAME         NAMESPACE    REVISION  STATUS    CHART
bookmyevent  bookmyevent  5         deployed  bookmyevent-1.0.0

# Check all pods
kubectl get pods -n bookmyevent

# Expected: All pods Running with 1/1 Ready
```

**Resources Deployed:**
- 6 Deployments (user, event, search, booking, frontend, nginx-gateway)
- 6 Services
- 1 Ingress (ALB)
- 2 ConfigMaps
- 1 Secret

#### ALB Provisioning Test
```bash
# Check ingress
kubectl get ingress -n bookmyevent bookmyevent-gateway

# Expected:
NAME                 ADDRESS                                          PORTS
bookmyevent-gateway  k8s-bookmyev-bookmyev-xxxxx.us-east-1.elb...    80, 443

# Test ALB health
curl -I http://k8s-bookmyev-bookmyev-xxxxx.us-east-1.elb.amazonaws.com/api/v1/users/health

# Expected: HTTP/1.1 200 OK
```

**Provisioning Time:** 2-3 minutes

---

### Test Stage Validation

#### Integration Test Execution
```bash
# Pipeline runs test-endpoints.sh
# All 11 tests must pass for deployment to succeed
```

**Pass Criteria:**
- All 11 tests return expected status codes
- No timeout errors
- ALB routing working correctly

**Failure Handling:**
If tests fail, pipeline marks deployment as failed but does NOT rollback (manual intervention required).

---

## Performance Metrics

### Build Stage
- **Target:** < 7 minutes
- **Typical:** 5-7 minutes
- **Parallel builds:** 6 services simultaneously

### Deploy Stage
- **Target:** < 10 minutes
- **Typical:** 8-10 minutes
- **Migration:** 30-90 seconds
- **Helm upgrade:** 5-8 minutes
- **ALB provisioning:** 2-3 minutes

### Test Stage
- **Target:** < 3 minutes
- **Typical:** 2-3 minutes
- **11 sequential tests**

### Total Pipeline
- **Target:** < 20 minutes
- **Typical:** 15-20 minutes
- **Success rate:** ~97%

---

## Troubleshooting Test Failures

### Integration Tests Fail: Connection Refused
**Cause:** ALB not fully provisioned

**Solution:**
```bash
# Wait additional 2-3 minutes
sleep 180

# Verify ALB address
kubectl get ingress -n bookmyevent

# Test directly
curl http://<ALB-ADDRESS>/api/v1/users/health
```

### Integration Tests Fail: 404 Not Found
**Cause:** nginx-gateway routing issue

**Solution:**
```bash
# Check nginx-gateway logs
kubectl logs -n bookmyevent deploy/nginx-gateway

# Verify ConfigMap
kubectl get configmap nginx-config -n bookmyevent -o yaml

# Expected: Proxy pass rules for all services
```

### Integration Tests Fail: 401 Unauthorized
**Cause:** JWT secret mismatch

**Solution:**
```bash
# Verify GitHub Secret matches Kubernetes Secret
# GitHub: Repository → Settings → Secrets → JWT_SECRET
# K8s: kubectl get secret bookmyevent-secrets -n bookmyevent -o yaml

# Redeploy if mismatch
kubectl delete secret bookmyevent-secrets -n bookmyevent
# Re-run pipeline to recreate
```

### Integration Tests Fail: 500 Internal Server Error
**Cause:** Database connection issue

**Solution:**
```bash
# Check RDS connectivity
kubectl run -it --rm debug --image=postgres:15-alpine \
  --env="PGPASSWORD=$RDS_PASSWORD" -n bookmyevent -- \
  psql -h $RDS_ENDPOINT -U postgres -c "SELECT version();"

# Check user-service logs
kubectl logs -n bookmyevent deploy/user-service

# Look for database errors
```

### Booking Flow Test Fails: Admin Registration 500
**Current Known Issue:** Admin registration endpoint returns 500

**Status:** Under investigation

**Workaround:** Skip admin tests for now

---

## Test Data Management

### Unique Email Generation
Tests use timestamp + random number to avoid conflicts:
```python
import time
import random

timestamp = int(time.time())
rand_suffix = random.randint(10000, 99999)
user_email = f"testuser_{timestamp}_{rand_suffix}@example.com"
```

### Database Cleanup
Tests do NOT clean up after themselves. To reset:
```bash
# Connect to RDS
psql -h $RDS_ENDPOINT -U postgres -d users_db

# Delete test users
DELETE FROM users WHERE email LIKE 'test%@example.com';
```

---

## Continuous Improvement

### Metrics to Track
1. **Pipeline success rate:** Target >95%, Current ~97%
2. **Average execution time:** Target <20min, Current 15-20min
3. **Test pass rate:** Target 100%, Current 100%
4. **Time to detect failures:** Target <5min, Current ~3min

### Future Enhancements
1. **Load testing:** Add k6 performance tests
2. **Security testing:** OWASP ZAP scans
3. **Database testing:** Automated data integrity checks
4. **Rollback automation:** Auto-rollback on test failure
5. **Smoke tests:** Quick health checks before full tests

---

## Related Documentation

- **[CI/CD Guide](ci-cd-guide.md)** - Full pipeline documentation
- **[Quick Start](ci-cd-quickstart.md)** - 3-step setup
- **[Deployment Guide](../deployment/eks-deployment-guide.md)** - Infrastructure details

---

**Test Coverage:** 11 automated integration tests  
**Success Rate:** 100% (11/11 passing)  
**Last Updated:** December 2025  
**Maintained by:** ENPM818R Group 5
