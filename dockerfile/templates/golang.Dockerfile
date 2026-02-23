# Golang Application Dockerfile Template
# Lightweight Go application container based on Alpine Linux

FROM alpine:3.22 as golang

LABEL maintainer="DevOps Team"

# Build arguments
ARG PORT=2025
ARG ARCH=""
ARG APP_NAME="app"
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""
ARG CI_PROJECT_NAME=""

# Set environment variables
ENV PORT=${PORT} \
    APP_NAME=${APP_NAME} \
    TZ="Asia/Shanghai"

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
      CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
      CI_BUILD_DATE=${CI_BUILD_DATE} \
      CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME} \
      CI_PROJECT_NAME=${CI_PROJECT_NAME} \
      app.name=${APP_NAME}

# Install required packages and setup timezone
RUN apk update && \
    apk add --no-cache tzdata ca-certificates curl && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    update-ca-certificates && \
    mkdir -p /app/logs && \
    rm -rf /var/cache/apk/*

# Set working directory
WORKDIR /app

# Copy the compiled binary
# Note: The build process should compile the binary as 'app'
# For single-arch builds:
COPY ./app /app/${APP_NAME}

# Alternative for multi-arch builds (uncomment if using buildx):
# COPY ./build/app-linux-${ARCH} /app/${APP_NAME}

# Ensure the binary is executable
RUN chmod +x /app/${APP_NAME}

# Expose the application port
EXPOSE ${PORT}

# Health check
# Customize the health endpoint based on your application
HEALTHCHECK --start-period=10s --interval=20s --timeout=3s --retries=3 \
    CMD curl -fs http://localhost:${PORT}/health || exit 1

# Use shell to allow environment variable expansion
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
