# Contributing to BookMyEvent

Thank you for your interest in contributing to BookMyEvent! This document provides guidelines and information for contributors.

## 🎓 Project Team

This project was developed as part of **ENPM818R - Virtualization & Containerization** at the University of Maryland, Fall 2025.

### Team Members & Responsibilities

| Team Member | Role | Responsibilities |
|-------------|------|------------------|
| **Heena Khan** | Project Lead & CI/CD Engineer | Oversaw end-to-end project execution, coordinated team activities, and implemented the CI/CD pipeline for automated builds and deployments. |
| **Anish Chamuah** | Infrastructure Engineer | Designed and deployed the core AWS infrastructure, including VPC, EKS cluster, networking components, and load balancers. |
| **Sundara Sasi Koushik Diwakaruni** | Backend Developer | Built and maintained backend microservices, implemented business logic, and integrated services with databases and internal APIs. |
| **March Gabiel Nazal Badilla** | Frontend Developer and Security Contributor | Developed the user-facing interface, integrated frontend components with backend services, and contributed to application and API security controls. |
| **Divya Kamila** | Monitoring & Observability Engineer | Deployed and configured Prometheus and Grafana for cluster-level monitoring and visualization of system performance. |
| **Long Phuoc Bao Lee** | CloudWatch & Logging Engineer | Set up AWS CloudWatch dashboards, logs, and alarms to support centralized monitoring and operational visibility. |
| **Solomon Njie** | Security Engineer | Led the security hardening efforts, implemented IAM least privilege, reviewed SG/WAF policies, and ensured adherence to security best practices. |

---

## 🚀 Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Go 1.21+** installed
- **Node.js 18+** and npm
- **Docker** and Docker Compose
- **kubectl** configured for EKS access
- **AWS CLI** configured with appropriate credentials
- **Helm 3.x** for Kubernetes deployments
- **Git** for version control

### Local Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/heena5498/eks-microservices.git
   cd eks-microservices-build
   ```

2. **Set up environment variables:**
   ```bash
   cp .env.example .env
   # Edit .env with your local configuration
   ```

3. **Start local services:**
   ```bash
   docker-compose up -d
   ```

4. **Run database migrations:**
   ```bash
   make migrate-up-all
   ```

5. **Build and run services:**
   ```bash
   make build-all
   make run SERVICE=user-service
   ```

---

## 📝 Development Workflow

### Branch Strategy

We follow a **feature branch workflow**:

- `main` - Production-ready code
- `build` - Development integration branch
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `hotfix/*` - Urgent production fixes

### Creating a Pull Request

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following our coding standards

3. **Write tests** for new functionality

4. **Commit with descriptive messages:**
   ```bash
   git commit -m "feat: add event search filtering"
   ```

5. **Push to your branch:**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open a Pull Request** on GitHub targeting the `build` branch

7. **Address review comments** and ensure CI/CD checks pass

### Commit Message Convention

We follow **Conventional Commits** specification:

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

**Examples:**
```
feat(booking): add seat reservation timeout
fix(auth): resolve JWT expiration issue
docs(readme): update deployment instructions
test(event): add integration tests for event creation
```

---

## 🏗️ Code Standards

### Go Code Guidelines

- Follow [Effective Go](https://golang.org/doc/effective_go.html) principles
- Use `gofmt` for code formatting
- Run `golangci-lint` before committing
- Write unit tests for new functions
- Maintain test coverage above 70%

**Example:**
```go
// Good
func (s *UserService) GetUserByEmail(ctx context.Context, email string) (*User, error) {
    if email == "" {
        return nil, ErrInvalidEmail
    }
    return s.repo.FindByEmail(ctx, email)
}

// Bad
func GetUser(e string) *User {
    // Missing error handling, context, validation
}
```

### JavaScript/React Guidelines

- Use **ESLint** configuration provided
- Follow **React Hooks** best practices
- Use functional components with hooks
- Implement proper error boundaries
- Write PropTypes or TypeScript types

**Example:**
```jsx
// Good
const EventCard = ({ event, onBook }) => {
  const [loading, setLoading] = useState(false);
  
  const handleBooking = async () => {
    setLoading(true);
    try {
      await onBook(event.id);
    } catch (error) {
      console.error('Booking failed:', error);
    } finally {
      setLoading(false);
    }
  };
  
  return (
    <Card>
      <h3>{event.name}</h3>
      <Button onClick={handleBooking} disabled={loading}>
        {loading ? 'Booking...' : 'Book Now'}
      </Button>
    </Card>
  );
};
```

### Docker Best Practices

- Use multi-stage builds
- Specify exact version tags (not `latest`)
- Run containers as non-root user
- Minimize layers and image size
- Include health checks

### Kubernetes Manifests

- Use Helm templates for reusability
- Set resource limits and requests
- Include readiness and liveness probes
- Apply security contexts
- Document all custom annotations

---

## 🧪 Testing

### Running Tests

**Backend (Go):**
```bash
# Run all tests
make test

# Run service-specific tests
make test-service SERVICE=booking

# Run with coverage
go test -v -cover ./...
```

**Frontend (React):**
```bash
cd frontend
npm test
npm run test:coverage
```

**Integration Tests:**
```bash
# Local integration tests
./scripts/testing/test-endpoints.sh

# Full test suite
python scripts/testing/test_booking_flow.py
python scripts/testing/comprehensive_search_api_test.py
```

### Test Requirements

- **Unit tests** for all new functions
- **Integration tests** for API endpoints
- **E2E tests** for critical user flows
- Minimum **70% code coverage**

---

## 🔒 Security Guidelines

### Security Checklist

- [ ] No secrets or credentials in code
- [ ] Use environment variables for configuration
- [ ] Validate and sanitize all user inputs
- [ ] Use parameterized queries (prevent SQL injection)
- [ ] Implement rate limiting on public endpoints
- [ ] Use HTTPS for all external communication
- [ ] Apply least-privilege IAM roles
- [ ] Scan container images for vulnerabilities

### Reporting Security Issues

**Do not** open public issues for security vulnerabilities. Instead:

1. Email security concerns to: [heena@umd.edu](mailto:heena@umd.edu)
2. Include detailed description and reproduction steps
3. Allow 48 hours for initial response

---

## 📚 Documentation

### Documentation Standards

- Update README.md for user-facing changes
- Document all public APIs in code comments
- Update architecture diagrams when changing system design
- Provide deployment guides for infrastructure changes
- Include runbooks for operational procedures

### Adding Documentation

Documentation is organized in the `docs/` folder:

```
docs/
├── architecture.md          # System architecture
├── build/                   # CI/CD documentation
│   ├── ci-cd-guide.md
│   ├── ci-cd-quickstart.md
│   └── ci-cd-testing-guide.md
├── deployment/              # Deployment guides
│   └── eks-deployment-guide.md
└── secrets/                 # Secrets management
    ├── secrets-manager-guide.md
    └── secrets-quickstart.md
```

---

## 🐛 Issue Reporting

### Bug Reports

Include:
- Clear, descriptive title
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, versions)
- Error messages and logs
- Screenshots if applicable

### Feature Requests

Include:
- Use case description
- Proposed solution
- Alternative approaches considered
- Impact on existing functionality

---

## 🔄 CI/CD Pipeline

Our GitHub Actions pipeline automatically:

1. **Builds** all Docker images
2. **Runs** unit and integration tests
3. **Scans** for security vulnerabilities
4. **Pushes** images to ECR
5. **Deploys** to EKS cluster
6. **Validates** deployment with health checks

All PRs must pass CI/CD checks before merging.

---

## 📞 Getting Help

- **Documentation:** Check the `docs/` folder first
- **Issues:** Search existing GitHub issues
- **Team Chat:** Contact project team members
- **Office Hours:** Schedule with project lead

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Course:** ENPM818R - Virtualization & Containerization
- **Institution:** University of Maryland - College Park
- **Instructor:** Professor Everett Daviage
- **Semester:** Fall 2025

---

**Thank you for contributing to BookMyEvent! 🎉**
