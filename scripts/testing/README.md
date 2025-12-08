# Testing Scripts

This directory contains integration tests and validation scripts for the BookMyEvent application.

## 📋 Available Tests

### Integration Tests (Used by CI/CD)

**`test-endpoints.sh`** - Main integration test suite
- Tests complete user authentication flow through production ALB
- Validates all API endpoints (register, login, profile, refresh, logout)
- Checks error handling (401, 409 status codes)
- **Status:** All 11 tests passing
- **Usage:** `./test-endpoints.sh`

### Additional Test Scripts

**`test_booking_flow.py`** - Booking flow integration tests
- Tests user registration with unique emails
- Validates event creation and booking
- **Usage:** `python3 test_booking_flow.py`

**`comprehensive_search_api_test.py`** - Search API comprehensive tests
- Tests search functionality through nginx-gateway
- Validates pagination, filtering, and sorting
- **Usage:** `python3 comprehensive_search_api_test.py`

## 📖 Documentation

- **[Testing Quick Start](testing-quickstart.md)** - Quick testing reference
- **[CI/CD Testing Guide](../docs/build/ci-cd-testing-guide.md)** - Pipeline testing documentation

## 🚀 Quick Start

Run all integration tests:
```bash
# Make executable
chmod +x test-endpoints.sh

# Run tests
./test-endpoints.sh
```

Expected output: All 11 tests pass

## 🔗 Related Documentation

- CI/CD pipeline testing: `../docs/build/ci-cd-testing-guide.md`
- Main README: `../README.md`

## 📝 Notes

- Tests use the production ALB endpoint or custom domain
- Integration tests run automatically in GitHub Actions CI/CD pipeline
- All tests validate against live AWS EKS deployment
- Test data uses unique timestamps to avoid conflicts

---

**Last Updated:** December 2025  
**Maintained by:** ENPM818R Group 5
