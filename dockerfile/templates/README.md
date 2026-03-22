# Dockerfile 模板使用说明

本目录包含各类工程的标准 Dockerfile 模板，用于构建容器镜像。

## 模板列表

| 模板文件 | 工程类型 | 基础镜像 | 说明 |
|---------|---------|---------|------|
| java.Dockerfile | Java/Maven | OpenJDK 8 Alpine | Spring Boot 等 Java 应用 |
| web.Dockerfile | Node.js/Web | Nginx 1.18 Alpine | Vue/React/Angular 等前端应用 |
| python.Dockerfile | Python | Conda base-mini | Python 服务应用 |
| golang.Dockerfile | Golang | Alpine 3.22 | Go 编译后的二进制应用（单架构）|
| golang-multiarch.Dockerfile | Golang | Alpine 3.22 | Go 多架构应用（Dockerfile 模式，多阶段构建）|
| golang-multiarch-precompile.Dockerfile | Golang | Alpine 3.22 | Go 多架构应用（预编译模式）|
| py_model.Dockerfile | Python 模型库 | Alpine latest | 用于 initContainer 的模型库 |

## 使用方式

### 方式 1: 使用默认模板（推荐）

CI/CD 流程会自动根据项目类型选择对应的模板，无需额外配置。

**.gitlab-ci.yml 示例：**
```yaml
include:
  - project: 'devops/ci-templates'
    ref: devops
    file: 'jobs-templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
```

### 方式 2: 使用自定义 Dockerfile

如果需要完全自定义 Dockerfile，可以在项目根目录或指定目录下创建 Dockerfile，并通过 `CUSTOM_DOCKERFILE_PATH` 变量指定路径。

**项目结构：**
```
your-project/
├── src/
├── docker/
│   └── Dockerfile          # 自定义的 Dockerfile
└── .gitlab-ci.yml
```

**.gitlab-ci.yml 配置：**
```yaml
include:
  - project: 'devops/ci-templates'
    ref: devops
    file: 'jobs-templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  CUSTOM_DOCKERFILE_PATH: "docker/Dockerfile"  # 指定自定义 Dockerfile 路径
```

### 方式 3: 基于标准模板自定义

您可以复制标准模板到项目中进行修改：

```bash
# 复制 Java 模板到项目
cp dockerfile/templates/java.Dockerfile your-project/docker/Dockerfile

# 在项目中根据需要修改 Dockerfile

# 在 .gitlab-ci.yml 中配置使用自定义 Dockerfile
variables:
  CUSTOM_DOCKERFILE_PATH: "docker/Dockerfile"
```

## 模板特性说明

### 1. Java 模板 (java.Dockerfile)

**特点：**
- 使用非 root 用户 (daemon) 运行
- 容器感知的 JVM 参数优化
- 支持 Spring Boot 健康检查（需自行启用）

**JVM 参数说明：**
- `-XX:+UseContainerSupport`: 自动检测容器内存限制
- `-XX:MaxRAMPercentage=90.0`: 最大堆内存占总内存 90%
- `-XX:InitialRAMPercentage=40.0`: 初始堆内存占总内存 40%

**自定义示例：**
```dockerfile
# 修改 JVM 参数
CMD ["sh", "-c", "java -jar \
    -XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=80.0 \
    -Dspring.profiles.active=prod \
    /opt/deployments/${APP}.jar"]
```

### 2. Web 模板 (web.Dockerfile)

**特点：**
- 基于 Nginx，轻量高效
- 支持自定义 nginx.conf 配置
- 内置健康检查

**使用自定义 Nginx 配置：**
```yaml
# .gitlab-ci.yml
variables:
  CUSTOM_NGINX_CONF: "docker/nginx.conf"  # 自定义 nginx 配置文件路径
```

构建脚本会自动将 nginx.conf 添加到镜像中。

**使用工作区前置命令准备多个配置文件：**

当需要准备多个配置文件时，可以使用 `DOCKER_WORKSPACE_PREPARE_CMD` 变量：

```yaml
# .gitlab-ci.yml
variables:
  BUILD_SHELL: "pnpm run build"
  DOCKER_WORKSPACE_PREPARE_CMD: |
    cp ${CI_PROJECT_DIR}/config/nginx.conf .
    cp ${CI_PROJECT_DIR}/config/app.conf .
    mkdir -p ssl && cp ${CI_PROJECT_DIR}/config/ssl/*.pem ssl/
```

此命令会在 Docker 构建工作区（DOCKER_DAEMON_WORKSPACE）执行，用于准备 Dockerfile 所需的依赖文件。

### 3. Python 模板 (python.Dockerfile)

**特点：**
- 基于 Conda，支持科学计算库
- 自动配置私有 PyPI 源
- 镜像层优化，减小体积

**依赖管理：**
- 主要依赖：`requirements.txt`
- 构建时依赖：`requirements-build.txt`（可选）

### 4. Golang 模板

Golang 项目提供三种模板，适用于不同的构建场景：

#### 4.1 golang.Dockerfile（单架构模板）

**特点：**
- 极小的镜像体积（基于 Alpine）
- 支持健康检查
- 适用于单一架构部署

**使用场景：**
- 仅需构建 linux/amd64 或 linux/arm64 单一架构
- 不需要跨平台支持

#### 4.2 golang-multiarch.Dockerfile（多架构多阶段构建模板）

**特点：**
- 使用 Docker 多阶段构建
- 在容器内部进行跨架构编译
- 支持 linux/amd64、linux/arm64、linux/arm/v7 等多架构
- 自动利用 Docker Buildx 的架构感知能力

**使用方式：**
```yaml
# .gitlab-ci.yml
variables:
  MULTIARCH_BUILD_ENABLE: "true"
  GOLANG_MULTIARCH_MODE: "dockerfile"  # 使用 Dockerfile 模式（默认值）
  DOCKER_BUILD_PLATFORMS: "linux/amd64,linux/arm64"
```

**优点：**
- 构建简单，无需预编译
- 充分利用 Docker 缓存层
- 适合源码较小的项目

**工作流程：**
1. 第一阶段（builder）：在 golang:alpine 镜像中编译代码
2. 第二阶段（runtime）：将编译好的二进制复制到最小运行镜像

#### 4.3 golang-multiarch-precompile.Dockerfile（多架构预编译模板）

**特点：**
- 在 CI 环境中预先编译多个架构的二进制文件
- Docker 构建阶段仅负责复制和打包
- 更快的构建速度（跳过容器内编译）

**使用方式：**
```yaml
# .gitlab-ci.yml
variables:
  MULTIARCH_BUILD_ENABLE: "true"
  GOLANG_MULTIARCH_MODE: "precompile"  # 使用预编译模式
  DOCKER_BUILD_PLATFORMS: "linux/amd64,linux/arm64"
  BUILD_SHELL: "make build"  # 可选：自定义编译脚本
```

**优点：**
- 编译速度快（并行编译多个架构）
- 可使用自定义编译脚本
- 构建过程更可控

**工作流程：**
1. CI 环境中使用 Go 交叉编译生成多个架构的二进制文件
2. 文件命名格式：`${CI_PROJECT_NAME}-linux-amd64`、`${CI_PROJECT_NAME}-linux-arm64` 等
3. 存放在 `binaries/` 目录
4. Docker Buildx 根据目标架构自动选择对应的二进制文件

**二进制文件命名规范：**
```
binaries/
├── your-app-linux-amd64
├── your-app-linux-arm64
└── your-app-linux-arm-v7
```

#### 选择建议

| 场景 | 推荐模板 | 理由 |
|-----|---------|------|
| 单架构部署 | golang.Dockerfile | 简单直接 |
| 源码较小（<10MB）| golang-multiarch.Dockerfile | 充分利用 Docker 缓存 |
| 源码较大或有复杂依赖 | golang-multiarch-precompile.Dockerfile | 编译速度更快 |
| 需要自定义编译流程 | golang-multiarch-precompile.Dockerfile | 更灵活的编译控制 |

### 5. Python 模型库模板 (py_model.Dockerfile)

**特点：**
- 用于 initContainer 部署模式
- 包含完整的模型文件和代码
- 配合 PVC 共享卷使用

**使用场景：**
模型库镜像通常不直接运行，而是作为 initContainer 将模型文件复制到共享存储中，供主容器使用。

## 构建参数 (Build Args)

所有模板都支持以下构建参数，CI/CD 流程会自动注入：

| 参数 | 说明 | 示例值 |
|-----|------|--------|
| CI_COMMIT_SHORT_SHA | Git 提交短哈希 | a1b2c3d |
| CI_BUILD_DATE | 构建日期时间 | 2024-01-15/14:30 |
| APP_NAME | 应用名称 | my-app |
| CI_COMMIT_REF_NAME | Git 分支/标签名 | dev |
| CI_COMMIT_AUTHOR | Git 提交作者 | john.doe |
| CI_PROJECT_NAME | GitLab 项目名 | my-project |

这些参数会作为镜像的 LABEL 元数据保存，便于追溯和审计。

## 自定义基础镜像版本

可以通过 ARG 指令自定义基础镜像版本：

```dockerfile
# Java 示例
ARG OPENJDK_VERSION=11-jre-slim
FROM openjdk:${OPENJDK_VERSION}

# Web 示例
ARG NGINX_VERSION=1.22-alpine
FROM nginx:${NGINX_VERSION}

# Golang 示例
FROM alpine:3.18
```

## 常见问题

### 1. 如何修改应用端口？

**Java:**
```dockerfile
# 在应用配置文件中修改（如 application.yml）
# 或通过环境变量
ENV SERVER_PORT=8080
EXPOSE 8080
```

**Golang:**
```dockerfile
ARG PORT=8080
ENV PORT=${PORT}
EXPOSE ${PORT}
```

### 2. 如何添加健康检查？

所有模板都包含健康检查示例（部分已启用，部分需要手动启用）。根据应用实际的健康检查端点进行修改：

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1
```

### 3. 如何优化镜像体积？

- **多阶段构建**：分离构建环境和运行环境
- **清理缓存**：删除不必要的包管理器缓存
- **精简依赖**：仅安装运行时必需的依赖
- **使用 Alpine**：优先选择 Alpine 基础镜像

### 4. 如何处理时区问题？

大部分模板已配置为 Asia/Shanghai 时区。如需修改：

```dockerfile
RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/America/New_York /etc/localtime && \
    echo "America/New_York" > /etc/timezone
```

## 工作区前置命令高级用法

### 什么是工作区前置命令？

`DOCKER_WORKSPACE_PREPARE_CMD` 是一个在 Docker 构建前执行的自定义命令，在 `DOCKER_DAEMON_WORKSPACE` 目录下运行。它的主要用途是准备 Dockerfile 构建所需的依赖配置文件。

### 使用场景

#### 场景 1：准备多个配置文件

```yaml
variables:
  DOCKER_WORKSPACE_PREPARE_CMD: |
    cp ${CI_PROJECT_DIR}/config/nginx.conf .
    cp ${CI_PROJECT_DIR}/config/app.json .
    cp ${CI_PROJECT_DIR}/config/.env.production .env
```

#### 场景 2：根据环境动态生成配置

```yaml
variables:
  DOCKER_WORKSPACE_PREPARE_CMD: |
    # 根据分支选择配置文件
    if [ "${CI_COMMIT_REF_NAME}" = "prd" ]; then
      cp ${CI_PROJECT_DIR}/config/nginx.prod.conf nginx.conf
    else
      cp ${CI_PROJECT_DIR}/config/nginx.dev.conf nginx.conf
    fi
```

#### 场景 3：从远程下载配置

```yaml
variables:
  DOCKER_WORKSPACE_PREPARE_CMD: |
    # 从配置中心下载配置文件
    curl -fsSL "https://config.example.com/api/v1/configs/app.json" -o app.json
    curl -fsSL "https://config.example.com/api/v1/configs/nginx.conf" -o nginx.conf
```

#### 场景 4：准备 SSL 证书

```yaml
variables:
  DOCKER_WORKSPACE_PREPARE_CMD: |
    mkdir -p ssl
    # 从项目复制证书
    cp ${CI_PROJECT_DIR}/certs/server.crt ssl/
    cp ${CI_PROJECT_DIR}/certs/server.key ssl/
    # 设置正确的权限
    chmod 600 ssl/server.key
```

#### 场景 5：处理模板文件

```yaml
variables:
  DOCKER_WORKSPACE_PREPARE_CMD: |
    # 使用环境变量替换配置模板
    envsubst < ${CI_PROJECT_DIR}/config/app.conf.template > app.conf
    # 验证生成的配置文件
    cat app.conf
```

#### 场景 6：复杂的准备逻辑

```yaml
variables:
  DOCKER_WORKSPACE_PREPARE_CMD: |
    echo "开始准备构建依赖..."

    # 创建必要的目录结构
    mkdir -p config ssl static

    # 复制配置文件
    cp ${CI_PROJECT_DIR}/deploy/nginx.conf config/
    cp ${CI_PROJECT_DIR}/deploy/app.json config/

    # 处理 SSL 证书
    if [ -f "${CI_PROJECT_DIR}/certs/cert.pem" ]; then
      cp ${CI_PROJECT_DIR}/certs/*.pem ssl/
      echo "SSL 证书已复制"
    else
      echo "警告: 未找到 SSL 证书"
    fi

    # 复制静态资源
    if [ -d "${CI_PROJECT_DIR}/public" ]; then
      cp -r ${CI_PROJECT_DIR}/public/* static/
    fi

    # 生成构建信息文件
    cat > build-info.json << EOF
    {
      "build_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "commit": "${CI_COMMIT_SHORT_SHA}",
      "branch": "${CI_COMMIT_REF_NAME}",
      "pipeline": "${CI_PIPELINE_ID}"
    }
    EOF

    echo "依赖准备完成，目录内容："
    ls -lha
```

### 注意事项

1. **路径引用**
   - 使用 `${CI_PROJECT_DIR}` 引用项目根目录
   - 当前目录是 `${DOCKER_DAEMON_WORKSPACE}`
   - 使用相对路径引用工作区内的文件

2. **错误处理**
   - 命令执行失败会自动终止构建
   - 建议添加错误检查和日志输出
   - 使用 `set -e` 确保任何命令失败时立即退出

3. **安全性**
   - 不要在命令中硬编码敏感信息
   - 使用 GitLab CI/CD 变量管理密钥
   - 注意文件权限设置

4. **调试技巧**
   - 使用 `echo` 输出关键步骤
   - 使用 `ls -lha` 查看文件列表
   - 使用 `cat` 验证文件内容

## 最佳实践

1. **安全性**
   - 使用非 root 用户运行应用
   - 定期更新基础镜像
   - 扫描镜像漏洞（CI 已集成）

2. **可维护性**
   - 为镜像添加完整的元数据标签
   - 使用语义化版本标签
   - 保持 Dockerfile 简洁易读

3. **性能优化**
   - 合理利用构建缓存
   - 优化层顺序（变化少的在前）
   - 使用 .dockerignore 排除不必要文件

4. **可观测性**
   - 配置健康检查
   - 暴露应用指标端点
   - 统一日志输出格式

## 支持与反馈

如有问题或建议，请联系 DevOps 团队或在 GitLab 项目中提交 Issue。

- 项目地址: https://gitlab.cpinnov.run/devops/ci-templates
- 文档地址: [README.md](../../README.md)
