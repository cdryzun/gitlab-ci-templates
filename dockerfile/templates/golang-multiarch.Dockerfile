# Golang Multi-Architecture Dockerfile Template
# Supports multi-architecture builds for linux/amd64, linux/arm64, linux/arm/v7, etc.
# Uses Docker Buildx for cross-platform compilation and image building

# ============================================
# Build Stage: Compilation stage (multi-architecture)
# ============================================
ARG GO_VERSION=1.23
FROM golang:${GO_VERSION}-alpine AS builder

# Buildx auto-injected platform variables
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# Build arguments
ARG CGO_ENABLED=0
ARG APP_NAME="app"
ARG BUILD_LDFLAGS="-s -w"

# Print build information (for debugging)
RUN echo "Building for platform: ${TARGETPLATFORM}" && \
    echo "  OS: ${TARGETOS}" && \
    echo "  ARCH: ${TARGETARCH}" && \
    echo "  VARIANT: ${TARGETVARIANT}"

# Install necessary build tools
RUN apk add --no-cache git make

# Set working directory
WORKDIR /build

# Copy go.mod and go.sum (leverage Docker cache layer)
COPY go.mod go.sum* ./

# Download dependencies (separate layer to speed up subsequent builds)
RUN go mod download

# Copy source code
COPY . .

# Cross-compile (automatically compiled based on TARGETOS and TARGETARCH)
RUN GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    CGO_ENABLED=${CGO_ENABLED} \
    go build \
    -ldflags "${BUILD_LDFLAGS}" \
    -o /build/${APP_NAME} \
    ./

# Verify binary file (optional, for debugging)
RUN file /build/${APP_NAME} && \
    ls -lh /build/${APP_NAME}

# ============================================
# Runtime Stage: Runtime stage (multi-architecture)
# ============================================
FROM alpine:3.22

LABEL maintainer="DevOps Team <devops@cpinnov.run>"

# 构建参数（运行时元数据）
ARG PORT=2025
ARG APP_NAME="app"
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""
ARG CI_PROJECT_NAME=""

# 环境变量
ENV PORT=${PORT} \
    APP_NAME=${APP_NAME} \
    TZ="Asia/Shanghai"

# 元数据标签
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
    CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
    CI_BUILD_DATE=${CI_BUILD_DATE} \
    CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME} \
    CI_PROJECT_NAME=${CI_PROJECT_NAME} \
    app.name=${APP_NAME}

# 安装运行时依赖（精简版）
RUN apk update && \
    apk add --no-cache \
    tzdata \
    ca-certificates \
    curl && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    update-ca-certificates && \
    mkdir -p /app/logs && \
    rm -rf /var/cache/apk/*

# 设置工作目录
WORKDIR /app

# Copy binary file from build stage
COPY --from=builder /build/${APP_NAME} /app/${APP_NAME}

# Ensure executable permission
RUN chmod +x /app/${APP_NAME}

# Expose port
EXPOSE ${PORT}

# Health check
# Customize according to application's health endpoint
HEALTHCHECK --start-period=10s --interval=20s --timeout=3s --retries=3 \
    CMD curl -fs http://localhost:${PORT}/health || exit 1

# Start command
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
