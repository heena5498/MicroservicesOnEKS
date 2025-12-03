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

# Install ca-certificates and wget for health checks
RUN apk --no-cache add ca-certificates wget

WORKDIR /root/

# Copy the binary from builder
COPY --from=builder /app/booking-service .

# Expose port
EXPOSE 8004

# Run the binary
CMD ["./booking-service"]
