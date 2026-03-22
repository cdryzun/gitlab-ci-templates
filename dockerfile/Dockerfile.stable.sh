#!/usr/bin/env bash
set -euo pipefail

# Dockerfile generation script (stable version)
# Supports two modes:
# 1. Use static templates from templates directory (recommended)
# 2. Dynamically generate Dockerfile (backward compatible)

# Color output
readonly CSI="\033["
readonly CEND="${CSI}0m"
readonly CGREEN="${CSI}1;32m"
readonly CYELLOW="${CSI}1;33m"
readonly CRED="${CSI}1;31m"
readonly Info="${CGREEN}[Info]: ${CEND}"
readonly Warn="${CYELLOW}[Warning]: ${CEND}"
readonly Error="${CRED}[Error]: ${CEND}"

# Get script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# Initialize multi-architecture build related variables (provide default values to support single-architecture builds)
# These variables are usually set by CI environment or _multiarch.sh module
# In single-architecture build scenarios, use default value "false" to avoid "unbound variable" error
MULTIARCH_BUILD_ENABLE="${MULTIARCH_BUILD_ENABLE:-false}"
GOLANG_MULTIARCH_MODE="${GOLANG_MULTIARCH_MODE:-dockerfile}"

# Normalize JDK version tag to ensure -alpine suffix is included
# Example: jdk21 -> jdk21-alpine, 8 -> 8-alpine, jdk17-alpine -> jdk17-alpine (unchanged)
normalize_jdk_version() {
local version="${1}"
if [[ -n "${version}" && ! "${version}" =~ -alpine$ ]]; then
echo "${version}-alpine"
else
echo "${version}"
fi
}

# Generate .dockerignore file
generate_dockerignore() {
echo -e "${Info}Generating .dockerignore file"
cat > .dockerignore << 'EOF'
*.md
!README.md
Dockerfile
.dockerignore
test?
tests/
.git/
.gitignore
.gitlab-ci.yml
*.log
.DS_Store
node_modules/
.pnpm-store/
EOF
}

# Use static template
use_static_template() {
local project_type="${1}"

# Select template based on multi-architecture build switch and mode
if [[ "${MULTIARCH_BUILD_ENABLE}" == "true" && "${project_type}" == "golang" ]]; then
# Select corresponding multi-architecture template based on GOLANG_MULTIARCH_MODE
local multiarch_mode="${GOLANG_MULTIARCH_MODE:-dockerfile}"

if [[ "${multiarch_mode}" == "precompile" ]]; then
# Precompile mode: use precompiled binary template
local template_file="${TEMPLATES_DIR}/${project_type}-multiarch-precompile.Dockerfile"
if [[ -f "${template_file}" ]]; then
echo -e "${Info}Using precompiled multi-architecture Dockerfile template: ${project_type}-multiarch-precompile.Dockerfile"
cp "${template_file}" Dockerfile
return 0
else
echo -e "${Warn}Precompiled multi-architecture template not found: ${template_file}"
echo -e "${Warn}Falling back to standard multi-architecture template"
multiarch_mode="dockerfile"
fi
fi

if [[ "${multiarch_mode}" == "dockerfile" ]]; then
# Dockerfile mode: use multi-stage build template
local template_file="${TEMPLATES_DIR}/${project_type}-multiarch.Dockerfile"
if [[ -f "${template_file}" ]]; then
echo -e "${Info}Using multi-stage build multi-architecture Dockerfile template: ${project_type}-multiarch.Dockerfile"
cp "${template_file}" Dockerfile
return 0
else
echo -e "${Warn}Multi-architecture template not found, falling back to standard single-architecture template"
fi
fi
fi

# Use standard single-architecture template
local template_file="${TEMPLATES_DIR}/${project_type}.Dockerfile"
if [[ -f "${template_file}" ]]; then
echo -e "${Info}Using static Dockerfile template: ${project_type}.Dockerfile"
cp "${template_file}" Dockerfile

# Java project: replace base image version based on DOCKERFILE_BUILD_JDK_VERSION
if [[ "${project_type}" == "java" && -n "${DOCKERFILE_BUILD_JDK_VERSION:-}" ]]; then
local _jdk_ver
_jdk_ver=$(normalize_jdk_version "${DOCKERFILE_BUILD_JDK_VERSION}")
echo -e "${Info}Switching Java base image based on DOCKERFILE_BUILD_JDK_VERSION=${DOCKERFILE_BUILD_JDK_VERSION} (tag: ${_jdk_ver})"
sed -i "s|^ARG OPENJDK_VERSION=.*|ARG OPENJDK_VERSION=${_jdk_ver}|" Dockerfile
fi

return 0
else
return 1
fi
}

# Generate Web project Dockerfile
generate_web_dockerfile() {
cat > Dockerfile << 'EOF'
# Web Application Dockerfile (Nginx)
ARG NGINX_VERSION=1.24-alpine
FROM nginx:${NGINX_VERSION} as web

# Build arguments for metadata
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_PROJECT_NAME="app"
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
    CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
    CI_BUILD_DATE=${CI_BUILD_DATE} \
    CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}

# Set environment variables
ENV APP=${CI_PROJECT_NAME}

# Copy static files
ADD dist /opt/deployments/dist

# Configure nginx and set permissions
RUN chown -R nginx:nginx /opt/deployments/dist && \
    if [ ! -e /usr/share/nginx/html ]; then \
    mkdir -p /usr/share/nginx && \
    ln -sv /opt/deployments/dist /usr/share/nginx/html; \
    else \
    rm -rf /usr/share/nginx/html && \
    ln -sv /opt/deployments/dist /usr/share/nginx/html; \
    fi

EXPOSE 80
EOF
}

# Generate Java project Dockerfile
generate_java_dockerfile() {
local jdk_version
jdk_version=$(normalize_jdk_version "${DOCKERFILE_BUILD_JDK_VERSION:-jdk17-alpine}")
echo -e "${Info}Generating Java Dockerfile, JDK version: ${jdk_version}"
cat > Dockerfile << EOF
# Java Application Dockerfile
ARG DOCKER_MIRROR_PREFIX=""
ARG OPENJDK_VERSION=${jdk_version}
FROM \${DOCKER_MIRROR_PREFIX}eclipse-temurin:\${OPENJDK_VERSION} as java

# Build arguments for metadata
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_PROJECT_NAME="app"
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=\${CI_COMMIT_AUTHOR} \\
    CI_COMMIT_SHORT_SHA=\${CI_COMMIT_SHORT_SHA} \\
    CI_BUILD_DATE=\${CI_BUILD_DATE} \\
    CI_COMMIT_REF_NAME=\${CI_COMMIT_REF_NAME}

# Set environment variables
ENV APP=\${CI_PROJECT_NAME}

# Copy JAR file
COPY --chown=daemon:daemon *.jar /opt/deployments/\${APP}.jar

# Set working directory
WORKDIR /opt/deployments

# Ensure proper permissions
RUN chown -R daemon:daemon /opt/deployments

# Switch to non-root user
USER daemon

# JVM configuration optimized for container environments
# Use shell form to ensure proper variable expansion and entrypoint compatibility
CMD java -jar -XX:+UseContainerSupport -XX:InitialRAMPercentage=40.0 -XX:MinRAMPercentage=50.0 -XX:MaxRAMPercentage=90.0 -XshowSettings:vm /opt/deployments/\${APP}.jar
EOF
}

# Generate Python project Dockerfile
generate_python_dockerfile() {
cat > Dockerfile << 'EOF'
# Python Application Dockerfile
ARG PYTHON_VERSION=3-alpine
FROM python:${PYTHON_VERSION}

# Build arguments for metadata
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_PROJECT_NAME="app"
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
    CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
    CI_BUILD_DATE=${CI_BUILD_DATE} \
    CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}

# Set environment variables
ENV APP=${CI_PROJECT_NAME} \
    PIP_DEFAULT_TIMEOUT=100 \
    PYPI_HOST='https://pypi.org/simple'

# Set working directory
WORKDIR /usr/src/${CI_PROJECT_NAME}

# Copy application files
COPY . .

# Install dependencies and cleanup
RUN pip install -r ./requirements.txt && \
    rm -rf ~/.cache

# Run application
CMD ["python", "main.py"]
EOF
}

# Generate Golang project Dockerfile (multi-architecture precompile mode)
generate_golang_multiarch_precompile_dockerfile() {
cat > Dockerfile << 'EOF'
# Golang Multi-Architecture Dockerfile Template (Precompile Mode)
# Uses precompiled multi-architecture binary files
# Applicable to GOLANG_MULTIARCH_MODE=precompile mode

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

# Build arguments (runtime metadata)
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
    app.name=${APP_NAME} \
    build.platform=${TARGETPLATFORM}

# Print build information (for debugging)
RUN echo "Target platform: ${TARGETPLATFORM}" && \
    echo "  OS: ${TARGETOS}" && \
    echo "  ARCH: ${TARGETARCH}" && \
    echo "  VARIANT: ${TARGETVARIANT}"

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

# Copy precompiled binary files (selected by target architecture)
# File naming format: ${CI_PROJECT_NAME}-${TARGETOS}-${TARGETARCH}${TARGETVARIANT}
# Examples: hysteria-linux-amd64, hysteria-linux-arm64, hysteria-linux-arm-v7
COPY binaries/${CI_PROJECT_NAME}-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} /app/${APP_NAME}

# Ensure executable permission
RUN chmod +x /app/${APP_NAME} && \
    echo "Binary info:" && \
    ls -lh /app/${APP_NAME}


# Expose port
EXPOSE ${PORT}

# Startup command
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
EOF
}

# Generate Golang project Dockerfile (multi-architecture multi-stage build mode)
generate_golang_multiarch_dockerfile() {
cat > Dockerfile << 'EOF'
# Golang Multi-Architecture Dockerfile Template
# Supports linux/amd64, linux/arm64, linux/arm/v7 and other multi-architecture builds
# Use Docker Buildx for cross-platform compilation and image building

# ============================================
# Build Stage: Compile stage (multi-architecture)
# ============================================
ARG GO_VERSION=1.23
FROM golang:${GO_VERSION}-alpine AS builder

# Auto-injected Buildx platform variables
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

# Copy go.mod and go.sum (leverage Docker cache layers)
COPY go.mod go.sum* ./

# Download dependencies (separate layer, accelerates subsequent builds)
RUN go mod download

# Copy source code
COPY . .

# Cross-compile (automatically compile based on TARGETOS and TARGETARCH)
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

LABEL maintainer="DevOps Team <devops@example.com>"

# Build arguments (runtime metadata)
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

# Copy binary from build stage
COPY --from=builder /build/${APP_NAME} /app/${APP_NAME}

# Ensure executable permission
RUN chmod +x /app/${APP_NAME}

# Expose port
EXPOSE ${PORT}

# Startup command
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
EOF
}

# Generate Golang project Dockerfile (single-architecture mode)
generate_golang_dockerfile() {
cat > Dockerfile << 'EOF'
# Golang Application Dockerfile
FROM alpine:3.22 as golang

LABEL maintainer="DevOps Team <devops@example.com>"

# Set working directory
WORKDIR /app

# Build arguments
ARG CI_PROJECT_NAME="app"
ARG PORT=2025
ARG CI_COMMIT_AUTHOR=""
ARG CI_COMMIT_SHORT_SHA=""
ARG CI_BUILD_DATE=""
ARG CI_COMMIT_REF_NAME=""

# Environment variables
ENV CI_PROJECT_NAME=${CI_PROJECT_NAME} \
    TZ="Asia/Shanghai" \
    PORT=${PORT}

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
    CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
    CI_BUILD_DATE=${CI_BUILD_DATE} \
    CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME} \
    app.name=${CI_PROJECT_NAME}

# Copy prebuilt binary from CI workspace
COPY ./app /app/${CI_PROJECT_NAME}

# Ensure binary is executable
RUN chmod +x /app/${CI_PROJECT_NAME}

# Health check
HEALTHCHECK --start-period=10s --interval=20s --timeout=3s --retries=3 \
    CMD curl -fs http://localhost:${PORT}/health || exit 1

# Expose port
EXPOSE ${PORT}

# Run application
CMD ["/bin/sh", "-c", "exec /app/${CI_PROJECT_NAME}"]
EOF
}

# Generate Python Model project Dockerfile
generate_py_model_dockerfile() {
cat > Dockerfile << 'EOF'
# Python Model Dockerfile (InitContainer)
FROM alpine:latest as py_model

# Build arguments for metadata
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG CI_PROJECT_NAME="app"
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
    CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
    CI_BUILD_DATE=${CI_BUILD_DATE} \
    CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}

# Set environment variables
ENV APP=${CI_PROJECT_NAME}

# Set working directory
WORKDIR /usr/src/${CI_PROJECT_NAME}

# Copy all files
COPY . .
EOF
}

# Dynamically generate Dockerfile
generate_dynamic_dockerfile() {
local project_type="${1}"

echo -e "${Warn}Static template not found, dynamically generating Dockerfile: ${project_type}"

case "${project_type}" in
web)
generate_web_dockerfile
;;
java)
generate_java_dockerfile
;;
python)
generate_python_dockerfile
;;
golang)
# Select corresponding generation function based on multi-architecture mode
if [[ "${MULTIARCH_BUILD_ENABLE}" == "true" ]]; then
local multiarch_mode="${GOLANG_MULTIARCH_MODE:-dockerfile}"

if [[ "${multiarch_mode}" == "precompile" ]]; then
echo -e "${Info}Dynamically generating multi-architecture precompile mode Dockerfile"
generate_golang_multiarch_precompile_dockerfile
elif [[ "${multiarch_mode}" == "dockerfile" ]]; then
echo -e "${Info}Dynamically generating multi-architecture multi-stage build mode Dockerfile"
generate_golang_multiarch_dockerfile
else
echo -e "${Warn}Unknown GOLANG_MULTIARCH_MODE: ${multiarch_mode}, using single-architecture mode"
generate_golang_dockerfile
fi
else
# Single-architecture mode
generate_golang_dockerfile
fi
;;
py_model)
generate_py_model_dockerfile
;;
*)
echo -e "${Error}Unsupported project type: ${project_type}"
exit 1
;;
esac
}

# Main function
main() {
# Parameter validation
if [[ $# -eq 0 ]]; then
echo -e "${Error}Missing project type argument"
echo "Usage: $0 <project_type>"
echo "Supported types: web, java, python, golang, py_model"
exit 1
fi

local project_type="${1}"

# Validate project type
case "${project_type}" in
web|java|python|golang|py_model)
# Valid project type
;;
*)
echo -e "${Error}Invalid project type: ${project_type}"
echo "Supported types: web, java, python, golang, py_model"
exit 1
;;
esac

# Prefer static templates, fall back to dynamic generation
if ! use_static_template "${project_type}"; then
generate_dynamic_dockerfile "${project_type}"
fi

# Generate .dockerignore file
generate_dockerignore

echo -e "${Info}Dockerfile generation completed"
}

# Execute main function
main "$@"
