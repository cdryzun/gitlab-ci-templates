# Golang Multi-Architecture Dockerfile Template (Precompile Mode)
# Uses pre-compiled multi-architecture binary files
# Suitable for GOLANG_MULTIARCH_MODE=precompile mode

# ============================================
# Runtime Stage: Runtime stage (multi-architecture)
# ============================================
FROM alpine:3.22

LABEL maintainer="DevOps Team <devops@example.com>"

# Auto-injected Buildx platform variables
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# Build arguments
ARG PORT=2025
ARG APP_NAME="app"
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""
ARG CI_PROJECT_NAME=""

# Environment variables
ENV PORT=${PORT} \
    APP_NAME=${APP_NAME} \
    TZ="Asia/Shanghai"

# Metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
      CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
      CI_BUILD_DATE=${CI_BUILD_DATE} \
      CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME} \
      CI_PROJECT_NAME=${CI_PROJECT_NAME} \
      app.name=${APP_NAME}

# Install runtime dependencies (minimal)
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

# Set working directory
WORKDIR /app

# Copy pre-compiled binary (using naming convention: ${APP_NAME}-${os}-${arch}${variant})
# For example: app-linux-amd64, app-linux-arm64, app-linux-armv7
# The build script should place these binaries in the binaries/ directory
COPY binaries/${APP_NAME}-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} /app/${APP_NAME}

# Ensure executable permission
RUN chmod +x /app/${APP_NAME} && \
    echo "Binary info:" && \
    ls -lh /app/${APP_NAME}

# Health check
HEALTHCHECK --start-period=10s --interval=20s --timeout=3s --retries=3 \
    CMD curl -fs http://localhost:${PORT}/health || exit 1

# Expose port
EXPOSE ${PORT}

# Startup command
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
