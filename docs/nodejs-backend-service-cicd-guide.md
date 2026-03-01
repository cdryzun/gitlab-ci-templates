# Node.js 后端服务 CI/CD 配置总结

## 问题背景

这是一个 Node.js Express 后端服务项目，使用 gitlab-ci-templates 进行 CI/CD。遇到的问题包括：

1. **模板类型限制**：模板将 `package.json` 项目统一识别为 `web` 类型（前端）
2. **web 类型构建流程不匹配**：期望执行 `npm run build` 并生成 `dist` 目录
3. **后端服务不需要构建步骤**：Express 后端直接运行源代码，没有 `dist` 目录
4. **镜像推送认证失败**：缺少 Docker Hub 认证配置

## 解决方案

### 1. 项目配置文件 (`.gitlab-ci.yml`)

```yaml
# GitLab CI configuration for nodejs-hello service
# Uses gitlab-ci-templates for standardized CI/CD

# Include the Auto-DevOps template from GitHub
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

# Project-specific variables
variables:
  # Use custom Dockerfile for Node.js backend service
  # This bypasses the template's web type build process which expects a dist directory
  CUSTOM_DOCKERFILE: "true"
  CUSTOM_DOCKERFILE_PATH: "Dockerfile"

  # Set empty build command to skip template's npm run build
  # Backend service doesn't need a build step
  BUILD_SHELL: "echo 'No build step required for backend service'"

  # Use external workspace directory to avoid conflicts with template's workspace
  DOCKER_DAEMON_WORKSPACE: "/tmp/docker-build"

  # Override test image to use Node.js for unit tests
  # Template auto-detects web type but we need to ensure Node.js image is used
  TEST_IMAGE: "ghcr.io/cdryzun/glci-builder-nodejs:24"

  # Enable Docker image build for feat branches
  FEAT_DOCKER_IMAGE_BUILD: "true"

  # Docker Hub credentials (configured in GitLab CI/CD Settings > Variables)
  # These variables should be set in GitLab:
  # - REGISTRY_USER: Docker Hub username
  # - REGISTRY_PASSWORD: Docker Hub password or access token

  # Enable unit tests
  UNIT_TEST_ENABLE: "true"
  NODE_UNIT_TEST_SHELL: "npm test"

  # Optional: Override default settings
  # DOCKER_IMAGE_BUILD: "true"
  # PORT: "8080"
```

### 2. Dockerfile

```dockerfile
# Node.js Express backend service
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies
RUN npm install --production

# Copy source code
COPY src ./src

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start application
CMD ["node", "src/index.js"]
```

### 3. GitLab CI/CD Variables 配置

在 GitLab 项目的 Settings > CI/CD > Variables 中配置以下变量：

| 变量名 | 值 | 保护 | 掩码 | 描述 |
|--------|-----|------|------|------|
| `REGISTRY_USER` | `cdryzun` | No | No | Docker Hub 用户名 |
| `REGISTRY_PASSWORD` | `your-password-or-token` | No | Yes | Docker Hub 密码或访问令牌 |

## 关键修复点总结

| 问题 | 原因 | 修复方法 |
|------|------|----------|
| 模板尝试复制 `./dist` 但不存在 | `web` 类型期望前端构建输出 | 使用 `CUSTOM_DOCKERFILE` 绕过 web 类型的 `image_build_init()` |
| `npm run build` 被调用但后端不需要 | 模板默认执行构建 | 设置 `BUILD_SHELL` 为 echo 命令跳过实际构建 |
| 工作目录冲突 | 模板使用 `./docker-build` | 使用 `/tmp/docker-build` 作为独立工作目录 |
| 测试镜像不正确 | `web` 类型自动选择 Node.js 镜像但构建镜像冲突 | 显式设置 `TEST_IMAGE` 为 Node.js 镜像 |
| 镜像推送认证失败 | 缺少 Docker Hub 认证 | 在 GitLab CI Variables 中配置 `REGISTRY_USER` 和 `REGISTRY_PASSWORD` |

## 流水线验证

- **流水线 URL**: https://gitlab.treesir.pub/sre/devops/nodejs-hello/-/pipelines/6196
- **状态**: ✅ 全部成功
- **Jobs**:
  - ✅ pre 阶段成功
  - ✅ build 阶段成功（构建并推送 Docker 镜像）
  - ✅ unit_test 阶段成功（使用正确的 Node.js 镜像运行测试）

## 注意事项

1. **Dockerfile 路径**: 确保 `Dockerfile` 位于项目根目录，并且 `CUSTOM_DOCKERFILE_PATH` 指向正确的路径。

2. **认证安全**: 建议使用 Docker Hub 访问令牌（Access Token）而不是密码，并在 GitLab 中设置 `masked: true`。

3. **缓存优化**: 可以考虑在 Dockerfile 中利用 Docker 层缓存优化构建速度，例如先复制 `package.json` 安装依赖，再复制源代码。

4. **健康检查**: Dockerfile 中定义了健康检查，确保服务启动后能通过 `/health` 端点响应。

## 参考资料

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [gitlab-ci-templates Repository](https://github.com/cdryzun/gitlab-ci-templates)
