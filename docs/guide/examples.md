# 语言配置示例

## Java (Maven)

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -DskipTests"
  DOCKERFILE_BUILD_JDK_VERSION: "17"
  MAVEN_APP_NAME: "my-service"
```

!!! tip "JAR 文件命名"
    `MAVEN_APP_NAME` 决定了最终 JAR 文件名和容器内进程名。设置为项目名可以在 `ps` 或 `top` 中快速识别是哪个服务占用资源。

## Java (Gradle)

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "gradle clean build -x test"
  DOCKERFILE_BUILD_JDK_VERSION: "17"
```

## React / Vue（Vite）

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
  NODE_UNIT_TEST_SHELL: "pnpm test"
```

产物输出到 `dist/`，自动打包进 Nginx 镜像。

## Node.js 后端（Express / Koa）

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  CUSTOM_DOCKERFILE: "true"
  CUSTOM_DOCKERFILE_PATH: "${CI_PROJECT_DIR}/Dockerfile"
  DOCKER_DAEMON_WORKSPACE: "/tmp/docker-build"
  DOCKER_WORKSPACE_PREPARE_CMD: "cp -r ${CI_PROJECT_DIR}/package.json ${CI_PROJECT_DIR}/src ."
  BUILD_SHELL: "mkdir -p dist"
  NODE_UNIT_TEST_SHELL: "npm test"
```

!!! note "为什么需要自定义 Dockerfile"
    模板将 `package.json` 项目统一识别为 `web` 类型（前端），默认用 Nginx 作为运行时。后端服务需要自定义 Dockerfile 来使用 Node.js 运行时。

## Python

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  PYTHON_UNIT_TEST_SHELL: "python -m pytest -v"
  DOCKER_DAEMON_WORKSPACE: "/tmp/docker-build"
```

零配置。自动检测 `requirements.txt`。

## Golang

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  GO_UNIT_TEST_SHELL: "go test -v ./..."
```

自动检测 `go.mod`，编译产物以项目名命名。

## Golang + Node.js（前端内嵌）

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BASE_BUILD_IMAGE: "ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.24-node22"
  BUILD_SHELL: |
    cd web && pnpm install && pnpm build && cd ..
    && go mod tidy && go build -o app ./...
```

## 完整 GitOps 部署

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "go mod tidy && go build -o ${CI_PROJECT_NAME} ./..."
  FEAT_DOCKER_IMAGE_BUILD: "true"
  GO_UNIT_TEST_SHELL: "go test -v ./..."
  DEPLOY_REPO_PROJ: "my-service"
  DEPLOY_VALUE_FILE: "values-dev.yaml"
  DEPLOY_REPO_YAML_TAG: ".image.tag"
  FEAT_CD_AUTO_DEPLOY: "true"
  DEV_CD_AUTO_DEPLOY: "true"
  SIT_CD_AUTO_DEPLOY: "true"
```

!!! info "前提条件"
    需要在 GitLab CI/CD Variables 中配置 `DEPLOY_REPO`（Helm charts 仓库地址）和 `GITLAB_REPO_COMMIT_TOKEN`。
