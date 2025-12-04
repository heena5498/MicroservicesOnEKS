# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install git for go modules
RUN apk add --no-cache git

# Copy everything first
COPY . .

# Download dependencies and generate go.sum
RUN go mod tidy && go mod download

# Build the booking service binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o booking-service ./cmd/booking-service

# Final stage
FROM alpine:latest

# Install ca-certificates and curl for health checks
RUN apk --no-cache add ca-certificates curl

# Create non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/booking-service .

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8004

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8004/healthz || exit 1

# Run the binary
CMD ["./booking-service"]