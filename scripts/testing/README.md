# Testing Scripts

This directory contains all testing and validation scripts for the BookMyEvent application.

## Documentation

- `testing-quickstart.md` - Quick testing reference and commands
- `search_service_testing_guide.md` - Search service testing documentation

## Test Categories

### CI/CD Pipeline Tests

- `test-cicd-pipeline.sh` - Automated CI/CD pipeline validation

### Service-Specific Tests

**Event Service:**
- `event-service-test.sh` - Event service API tests
- `event-service-test-config.sh` - Configuration for event service tests
- `test_event_service.sh` - Comprehensive event service testing

**Search Service:**
- `test-search-endpoints.sh` - Search API endpoint tests
- `test-search-endpoints.py` - Python-based search tests
- `test-event-search-integration.sh` - Event-search integration tests
- `search-service-data-generator.sh` - Test data generation for search
- `search-service-data-generator.py` - Python data generator
- `comprehensive_search_api_test.py` - Full search API test suite
- `quick_search_test.sh` - Quick search functionality test
- `step_by_step_search_test.py` - Step-by-step search validation

**Booking Service:**
- `booking-service-test.sh` - Booking service tests
- `test_booking_flow.py` - End-to-end booking flow
- `test_booking_flow_complete.py` - Complete booking scenarios
- `test_concurrent_booking.py` - Concurrent booking tests
- `test_extreme_concurrency.py` - High-concurrency stress tests
- `test_waitlist.py` - Waitlist functionality tests

**User Service:**
- `user-service-seed.py` - User data seeding

### Integration Tests

- `test-endpoints.sh` - All endpoints validation
- `test-env.config` - Test environment configuration

### Load Testing

- `stress-test.sh` - Basic load testing
- `stress-test-concurrent.sh` - Concurrent user simulation

## Quick Start

### Run CI/CD Validation

```bash
./scripts/testing/test-cicd-pipeline.sh
```

### Run Service Tests

```bash
# Test event service
./scripts/testing/event-service-test.sh

# Test search service
./scripts/testing/test-search-endpoints.sh

# Test booking service
./scripts/testing/booking-service-test.sh
```

### Run Load Tests

```bash
# Basic stress test
./scripts/testing/stress-test.sh

# Concurrent stress test
./scripts/testing/stress-test-concurrent.sh
```

### Run Python Tests

```bash
# Booking flow tests
python3 scripts/testing/test_booking_flow.py

# Search tests
python3 scripts/testing/comprehensive_search_api_test.py

# Concurrency tests
python3 scripts/testing/test_concurrent_booking.py
```

## Test Environment

Configure test environment variables in `test-env.config`:

```bash
source scripts/testing/test-env.config
```

## Documentation

Detailed testing guides:
- `testing-quickstart.md` - Quick testing reference (this directory)
- `search_service_testing_guide.md` - Search service testing (this directory)
- `../../build/ci-cd-testing-guide.md` - CI/CD pipeline testing

## CI Integration

These tests are automatically run by GitHub Actions:
- PR validation: `.github/workflows/pr-validation.yml`
- Post-deployment: `.github/workflows/cd-deploy-to-eks.yml`
