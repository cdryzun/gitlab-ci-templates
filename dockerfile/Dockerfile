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
