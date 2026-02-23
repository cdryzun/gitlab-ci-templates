#!/usr/bin/env bash
set -euo pipefail

# Dockerfile 生成脚本 (stable 版本)
# 支持两种模式：
# 1. 使用 templates 目录下的静态模板（推荐）
# 2. 动态生成 Dockerfile（向后兼容）

# 颜色输出
readonly CSI="\033["
readonly CEND="${CSI}0m"
readonly CGREEN="${CSI}1;32m"
readonly CYELLOW="${CSI}1;33m"
readonly CRED="${CSI}1;31m"
readonly Info="${CGREEN}[信息]: ${CEND}"
readonly Warn="${CYELLOW}[警告]: ${CEND}"
readonly Error="${CRED}[错误]: ${CEND}"

# 获取脚本所在目录
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# 初始化多架构构建相关变量（提供默认值以支持单架构构建）
# 这些变量通常由 CI 环境或 _multiarch.sh 模块设置
# 在单架构构建场景下，使用默认值 "false" 以避免 "unbound variable" 错误
MULTIARCH_BUILD_ENABLE="${MULTIARCH_BUILD_ENABLE:-false}"
GOLANG_MULTIARCH_MODE="${GOLANG_MULTIARCH_MODE:-dockerfile}"

# 标准化 JDK 版本标签，确保包含 -alpine 后缀
# 例如: jdk21 -> jdk21-alpine, 8 -> 8-alpine, jdk17-alpine -> jdk17-alpine (不变)
normalize_jdk_version() {
local version="${1}"
if [[ -n "${version}" && ! "${version}" =~ -alpine$ ]]; then
echo "${version}-alpine"
else
echo "${version}"
fi
}

# 生成 .dockerignore 文件
generate_dockerignore() {
echo -e "${Info}生成 .dockerignore 文件"
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

# 使用静态模板
use_static_template() {
local project_type="${1}"

# 根据多架构构建开关和模式选择模板
if [[ "${MULTIARCH_BUILD_ENABLE}" == "true" && "${project_type}" == "golang" ]]; then
# 根据 GOLANG_MULTIARCH_MODE 选择对应的多架构模板
local multiarch_mode="${GOLANG_MULTIARCH_MODE:-dockerfile}"

if [[ "${multiarch_mode}" == "precompile" ]]; then
# 预编译模式：使用预编译二进制的模板
local template_file="${TEMPLATES_DIR}/${project_type}-multiarch-precompile.Dockerfile"
if [[ -f "${template_file}" ]]; then
echo -e "${Info}使用预编译多架构 Dockerfile 模板: ${project_type}-multiarch-precompile.Dockerfile"
cp "${template_file}" Dockerfile
return 0
else
echo -e "${Warn}预编译多架构模板不存在: ${template_file}"
echo -e "${Warn}回退到标准多架构模板"
multiarch_mode="dockerfile"
fi
fi

if [[ "${multiarch_mode}" == "dockerfile" ]]; then
# Dockerfile 模式：使用多阶段构建模板
local template_file="${TEMPLATES_DIR}/${project_type}-multiarch.Dockerfile"
if [[ -f "${template_file}" ]]; then
echo -e "${Info}使用多阶段构建多架构 Dockerfile 模板: ${project_type}-multiarch.Dockerfile"
cp "${template_file}" Dockerfile
return 0
else
echo -e "${Warn}多架构模板不存在，回退到标准单架构模板"
fi
fi
fi

# 使用标准单架构模板
local template_file="${TEMPLATES_DIR}/${project_type}.Dockerfile"
if [[ -f "${template_file}" ]]; then
echo -e "${Info}使用静态 Dockerfile 模板: ${project_type}.Dockerfile"
cp "${template_file}" Dockerfile

# Java 项目：根据 DOCKERFILE_BUILD_JDK_VERSION 替换基础镜像版本
if [[ "${project_type}" == "java" && -n "${DOCKERFILE_BUILD_JDK_VERSION:-}" ]]; then
local _jdk_ver
_jdk_ver=$(normalize_jdk_version "${DOCKERFILE_BUILD_JDK_VERSION}")
echo -e "${Info}根据 DOCKERFILE_BUILD_JDK_VERSION=${DOCKERFILE_BUILD_JDK_VERSION} 切换 Java 基础镜像 (标签: ${_jdk_ver})"
sed -i "s|^ARG OPENJDK_VERSION=.*|ARG OPENJDK_VERSION=${_jdk_ver}|" Dockerfile
fi

return 0
else
return 1
fi
}

# 生成 Web 项目 Dockerfile
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

# 生成 Java 项目 Dockerfile
generate_java_dockerfile() {
local jdk_version
jdk_version=$(normalize_jdk_version "${DOCKERFILE_BUILD_JDK_VERSION:-jdk17-alpine}")
echo -e "${Info}生成 Java Dockerfile，JDK 版本: ${jdk_version}"
cat > Dockerfile << EOF
# Java Application Dockerfile
ARG OPENJDK_VERSION=${jdk_version}
FROM eclipse-temurin:\${OPENJDK_VERSION} as java

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
COPY --chown=daemon:daemon app*.jar /opt/deployments/\${APP}.jar

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

# 生成 Python 项目 Dockerfile
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

# 生成 Golang 项目 Dockerfile（多架构预编译模式）
generate_golang_multiarch_precompile_dockerfile() {
cat > Dockerfile << 'EOF'
# Golang Multi-Architecture Dockerfile Template (Precompile Mode)
# 使用预编译的多架构二进制文件
# 适用于 GOLANG_MULTIARCH_MODE=precompile 模式

# ============================================
# Runtime Stage: 运行时阶段（多架构）
# ============================================
FROM alpine:3.22

LABEL maintainer="DevOps Team <devops@cpinnov.run>"

# 自动注入的 Buildx 平台变量
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

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
    app.name=${APP_NAME} \
    build.platform=${TARGETPLATFORM}

# 打印构建信息（调试用）
RUN echo "Target platform: ${TARGETPLATFORM}" && \
    echo "  OS: ${TARGETOS}" && \
    echo "  ARCH: ${TARGETARCH}" && \
    echo "  VARIANT: ${TARGETVARIANT}"

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

# 复制预编译的二进制文件（根据目标架构选择）
# 文件命名格式: ${CI_PROJECT_NAME}-${TARGETOS}-${TARGETARCH}${TARGETVARIANT}
# 例如: hysteria-linux-amd64, hysteria-linux-arm64, hysteria-linux-arm-v7
COPY binaries/${CI_PROJECT_NAME}-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} /app/${APP_NAME}

# 确保可执行权限
RUN chmod +x /app/${APP_NAME} && \
    echo "Binary info:" && \
    ls -lh /app/${APP_NAME}


# 暴露端口
EXPOSE ${PORT}

# 启动命令
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
EOF
}

# 生成 Golang 项目 Dockerfile（多架构多阶段构建模式）
generate_golang_multiarch_dockerfile() {
cat > Dockerfile << 'EOF'
# Golang Multi-Architecture Dockerfile Template
# 支持 linux/amd64, linux/arm64, linux/arm/v7 等多架构构建
# 使用 Docker Buildx 进行跨平台编译和镜像构建

# ============================================
# Build Stage: 编译阶段（多架构）
# ============================================
ARG GO_VERSION=1.23
FROM golang:${GO_VERSION}-alpine AS builder

# 自动注入的 Buildx 平台变量
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# 构建参数
ARG CGO_ENABLED=0
ARG APP_NAME="app"
ARG BUILD_LDFLAGS="-s -w"

# 打印构建信息（调试用）
RUN echo "Building for platform: ${TARGETPLATFORM}" && \
    echo "  OS: ${TARGETOS}" && \
    echo "  ARCH: ${TARGETARCH}" && \
    echo "  VARIANT: ${TARGETVARIANT}"

# 安装必要的构建工具
RUN apk add --no-cache git make

# 设置工作目录
WORKDIR /build

# 复制 go.mod 和 go.sum（利用 Docker 缓存层）
COPY go.mod go.sum* ./

# 下载依赖（单独层，加速后续构建）
RUN go mod download

# 复制源代码
COPY . .

# 交叉编译（根据 TARGETOS 和 TARGETARCH 自动编译）
RUN GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    CGO_ENABLED=${CGO_ENABLED} \
    go build \
    -ldflags "${BUILD_LDFLAGS}" \
    -o /build/${APP_NAME} \
    ./

# 验证二进制文件（可选，调试用）
RUN file /build/${APP_NAME} && \
    ls -lh /build/${APP_NAME}

# ============================================
# Runtime Stage: 运行时阶段（多架构）
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

# 从构建阶段复制二进制文件
COPY --from=builder /build/${APP_NAME} /app/${APP_NAME}

# 确保可执行权限
RUN chmod +x /app/${APP_NAME}

# 暴露端口
EXPOSE ${PORT}

# 启动命令
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
EOF
}

# 生成 Golang 项目 Dockerfile（单架构模式）
generate_golang_dockerfile() {
cat > Dockerfile << 'EOF'
# Golang Application Dockerfile
FROM alpine:3.22 as golang

LABEL maintainer="zun.yang@cpdevice.com"

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

# 生成 Python Model 项目 Dockerfile
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

# 动态生成 Dockerfile
generate_dynamic_dockerfile() {
local project_type="${1}"

echo -e "${Warn}静态模板未找到，动态生成 Dockerfile: ${project_type}"

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
# 根据多架构模式选择对应的生成函数
if [[ "${MULTIARCH_BUILD_ENABLE}" == "true" ]]; then
local multiarch_mode="${GOLANG_MULTIARCH_MODE:-dockerfile}"

if [[ "${multiarch_mode}" == "precompile" ]]; then
echo -e "${Info}动态生成多架构预编译模式 Dockerfile"
generate_golang_multiarch_precompile_dockerfile
elif [[ "${multiarch_mode}" == "dockerfile" ]]; then
echo -e "${Info}动态生成多架构多阶段构建模式 Dockerfile"
generate_golang_multiarch_dockerfile
else
echo -e "${Warn}未知的 GOLANG_MULTIARCH_MODE: ${multiarch_mode}，使用单架构模式"
generate_golang_dockerfile
fi
else
# 单架构模式
generate_golang_dockerfile
fi
;;
py_model)
generate_py_model_dockerfile
;;
*)
echo -e "${Error}不支持的项目类型: ${project_type}"
exit 1
;;
esac
}

# 主函数
main() {
# 参数验证
if [[ $# -eq 0 ]]; then
echo -e "${Error}缺少项目类型参数"
echo "用法: $0 <project_type>"
echo "支持的类型: web, java, python, golang, py_model"
exit 1
fi

local project_type="${1}"

# 验证项目类型
case "${project_type}" in
web|java|python|golang|py_model)
# 有效的项目类型
;;
*)
echo -e "${Error}无效的项目类型: ${project_type}"
echo "支持的类型: web, java, python, golang, py_model"
exit 1
;;
esac

# 优先使用静态模板，失败则动态生成
if ! use_static_template "${project_type}"; then
generate_dynamic_dockerfile "${project_type}"
fi

# 生成 .dockerignore 文件
generate_dockerignore

echo -e "${Info}Dockerfile 生成完成"
}

# 执行主函数
main "$@"
