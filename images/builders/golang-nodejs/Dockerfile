# Golang + Node.js Multi-language Builder Image
# For projects that embed frontend static files into Go binaries
# Supports: Go backend + Node.js frontend (embedded via go:embed)

ARG GO_VERSION=1.23
ARG NODE_VERSION=20

# Stage 1: Node.js builder for frontend
FROM node:${NODE_VERSION}-bookworm-slim AS node-builder

# Stage 2: Go builder with Node.js
FROM golang:${GO_VERSION}-bookworm

LABEL maintainer="cdryzun"
LABEL description="Multi-language builder for Go + Node.js projects (frontend embedded in Go binary)"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Arguments
ARG GO_VERSION
ARG NODE_VERSION
ARG TARGETARCH

# Environment variables
ENV GO_VERSION=${GO_VERSION} \
    NODE_VERSION=${NODE_VERSION} \
    GOPATH=/go \
    PATH=/usr/local/go/bin:/go/bin:/usr/local/bin:/usr/bin:/bin \
    CGO_ENABLED=0 \
    GOOS=linux \
    DEBIAN_FRONTEND=noninteractive

# Install Node.js from Node.js official repository
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    git \
    make \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@latest --activate \
    && npm install -g yarn \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install common Go tools
RUN go install github.com/swaggo/swag/cmd/swag@latest \
    && go install github.com/go-delve/delve/cmd/dlv@latest \
    && go install golang.org/x/lint/golint@latest \
    && go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# Set working directory
WORKDIR /workspace

# Verify installations
RUN go version \
    && node --version \
    && npm --version \
    && pnpm --version \
    && yarn --version

# Default command
CMD ["bash"]
