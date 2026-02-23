# Node.js Builder Image
# For frontend builds with pnpm, yarn, npm

ARG NODE_VERSION=20
FROM node:${NODE_VERSION}-bookworm

LABEL maintainer="cdryzun"
LABEL description="Node.js builder image with pnpm, yarn and common tools"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Environment
ENV PNPM_HOME="/root/.local/share/pnpm" \
    PATH="${PATH}:/root/.local/share/pnpm"

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Configure npm/pnpm to use smaller registry timeout
RUN npm config set fetch-timeout 600000 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000

# Set working directory
WORKDIR /build

# Default command
CMD ["node", "--version"]
