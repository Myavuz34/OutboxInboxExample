# Use the official Golang image to build your application
FROM golang:1.24 AS builder

WORKDIR /app

# Copy the Go Modules manifests
COPY go.mod go.sum ./

# Download Go modules
RUN go mod download

# Copy the rest of the application source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 go build -o /app/main ./main.go

# Use a minimal image to run the application
FROM alpine:latest

WORKDIR /app

# Copy the compiled executable from the builder stage
COPY --from=builder /app/main .

# Expose any necessary ports (if your Go service listens on one)
EXPOSE 8080

# Command to run the executable
CMD ["/app/main"]