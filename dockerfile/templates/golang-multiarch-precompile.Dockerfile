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
# 例如: hysteria-linux-amd64, hysteria-linux-arm64, hysteria-linux-armv7
COPY binaries/${CI_PROJECT_NAME}-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} /app/${APP_NAME}

# 确保可执行权限
RUN chmod +x /app/${APP_NAME} && \
    echo "Binary info:" && \
    ls -lh /app/${APP_NAME}

# 健康检查
HEALTHCHECK --start-period=10s --interval=20s --timeout=3s --retries=3 \
    CMD curl -fs http://localhost:${PORT}/health || exit 1

# 暴露端口
EXPOSE ${PORT}

# 启动命令
CMD ["/bin/sh", "-c", "exec /app/${APP_NAME}"]
