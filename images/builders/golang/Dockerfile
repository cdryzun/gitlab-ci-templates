# Golang Builder Image
# For Go application builds

ARG GO_VERSION=1.23
FROM golang:${GO_VERSION}-bookworm

LABEL maintainer="cdryzun"
LABEL description="Golang builder image"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Environment
ENV GOPATH=/go \
    GO111MODULE=on \
    CGO_ENABLED=0

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    make \
    && rm -rf /var/lib/apt/lists/*

# Install golangci-lint using binary (much faster than go install)
# Reference: https://golangci-lint.run/welcome/install/
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin v1.56.2

# Set working directory
WORKDIR /build

# Default command
CMD ["go", "version"]
