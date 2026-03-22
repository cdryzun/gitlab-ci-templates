# 30 秒接入

## 第一步：添加配置

在项目根目录创建 `.gitlab-ci.yml`：

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'
```

## 第二步：推送代码

```bash
git add .gitlab-ci.yml
git commit -m "ci: add CI/CD pipeline"
git push
```

流水线自动触发。模板会：

1. **自动检测**项目类型（通过 `pom.xml` / `package.json` / `requirements.txt` / `go.mod`）
2. **自动选择**构建镜像和构建命令
3. **构建 Docker 镜像**并推送到 Registry
4. **运行单元测试**

## 常见覆盖配置

### Java 项目

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -DskipTests"
  DOCKERFILE_BUILD_JDK_VERSION: "17"
```

### 前端项目（React / Vue）

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
```

### 纯库项目（不构建镜像）

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  DOCKER_IMAGE_BUILD: "false"
```

### 开启 GitOps 部署

在 GitLab CI/CD Settings > Variables 中配置 `DEPLOY_REPO`（Helm charts 仓库地址），然后在 `.gitlab-ci.yml` 中添加：

```yaml
variables:
  DEPLOY_REPO_PROJ: "my-service"
  DEPLOY_VALUE_FILE: "values-dev.yaml"
  DEPLOY_REPO_YAML_TAG: ".image.tag"
```

更多配置项见 [变量参考](../reference/variables.md)。
