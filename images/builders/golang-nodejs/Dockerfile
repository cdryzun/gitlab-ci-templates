# Golang + Node.js Multi-language Builder Image
# For projects that embed frontend static files into Go binaries
# Supports: Go backend + Node.js frontend (embedded via go:embed)

ARG GO_VERSION=1.23
ARG NODE_VERSION=20

# Stage 1: Node.js stage to copy binaries
FROM node:${NODE_VERSION}-bookworm-slim AS node-stage

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

# Install dependencies and copy Node.js from official image
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy Node.js from the official node image
COPY --from=node-stage /usr/local/bin/node /usr/local/bin/node
COPY --from=node-stage /usr/local/lib/node_modules /usr/local/lib/node_modules

# Create symlinks for npm, npx, corepack
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -s /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

# Enable corepack and install package managers
RUN corepack enable \
    && corepack prepare pnpm@latest --activate \
    && npm install -g yarn

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
