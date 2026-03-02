---
name: gitlab-ci-templates-usage
description: Quickly integrate GitLab CI/CD pipelines with one include statement. Auto-detects Java, Node.js, Python, Golang projects. Includes Docker builds, SonarQube, GitOps deployment, and rollback support. Use when setting up CI/CD for new or existing projects.
---

# GitLab CI Templates Usage Guide

Quickly integrate GitLab CI/CD pipelines into your projects. One `include` statement delivers a complete build, test, scan, and deploy workflow.

## When to Use This Skill

Use this skill when you need to:

- Add CI/CD pipelines to new or existing projects
- Integrate GitLab CI templates into applications
- Configure automated builds for Java, Node.js, Python, or Golang projects
- Set up GitOps deployment workflows
- Troubleshoot CI/CD pipeline issues

## Quick Start

### 1. Basic Integration (30 seconds)

Create `.gitlab-ci.yml` in your project root:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'
```

Push your code and watch the pipeline run.

### 2. Automatic Project Type Detection

The template automatically detects the following project types:

- **Java**: Detects `pom.xml` or `build.gradle`
- **Node.js**: Detects `package.json`
- **Python**: Detects `requirements.txt` or `setup.py`
- **Golang**: Detects `go.mod`

## Common Scenarios

### Java Projects

#### Standard Maven Project
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  UNIT_TEST_ENABLE: "true"
  DOCKERFILE_BUILD_JDK_VERSION: "17-alpine"
```

#### Multi-Module Project (JAR not in root directory)
```yaml
variables:
  BUILD_SHELL: "mvn clean install -Dmaven.test.skip=true && mkdir -p ./target && mv spring-cloud-gateway/target/*.jar ./target/app.jar"
  BUILD_MAVEN_POM_FILE: "spring-cloud-gateway/pom.xml"
  UNIT_TEST_ENABLE: "true"
```

#### Library Project (No Docker Build)
```yaml
variables:
  BUILD_SHELL: "mvn clean install -Dmaven.test.skip=true"
  DOCKER_IMAGE_BUILD: "false"
```

### Node.js Projects

#### Standard Frontend Project
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
  UNIT_TEST_ENABLE: "false"
```

#### Environment-Based Build
```yaml
variables:
  BUILD_SHELL: "pnpm run ${BUILD_ENV}"
  UNIT_TEST_ENABLE: "false"
```

### Python Projects

#### Standard Python Application
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pip install -r requirements.txt"
  UNIT_TEST_ENABLE: "false"
```

#### Build Wheel Package (No Docker Image)
```yaml
variables:
  BUILD_SHELL: "python3 setup.py bdist_wheel"
  PROJECT_TYPE: "python"
  DOCKER_IMAGE_BUILD: "false"
  PYTHON_UNIT_TEST_SHELL: "python -m unittest"
```

### Golang Projects

#### Standard Application
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "go build -o app ./..."
```

#### Golang + Node.js (Embedded Frontend)
```yaml
variables:
  BASE_BUILD_IMAGE: "ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.23-node20"
  BUILD_SHELL: |
    cd web && pnpm install && pnpm build && cd .. \
    && go mod tidy && go build -o app ./...
```

Available image tags:
- `go1.23-node20`, `go1.23-node22`
- `go1.24-node20`, `go1.24-node22`, `go1.24-node24`
- `go1.25-node22`, `go1.25-node24`
- `go1.26-node22`, `go1.26-node24`

## Key Variables

### Core Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `BUILD_SHELL` | Build command | Auto-detected |
| `UNIT_TEST_ENABLE` | Enable unit tests | `true` |
| `DOCKER_IMAGE_BUILD` | Build and push Docker image | `true` |
| `DOCKER_REGISTRY` | Docker registry URL | `docker.io` |
| `DOCKER_HUB_ORGANIZATION` | Docker Hub organization name | `cdryzun` |

### Code Quality

| Variable | Description | Default |
|----------|-------------|---------|
| `SONAR_URL` | SonarQube server URL | - |
| `SONAR_TOKEN` | SonarQube access token | - |
| `SONAR_GATE` | Fail pipeline on quality gate | `false` |
| `MIN_COVERAGE` | Minimum code coverage | `80` |

### GitOps Deployment

| Variable | Description | Default |
|----------|-------------|---------|
| `DEPLOY_REPO_PROJ` | GitOps repository project path | - |
| `DEPLOY_VALUE_FILE` | Helm values file path | `values.yaml` |
| `DEPLOY_REPO_YAML_TAG` | Image tag YAML path | `.image.tag` |
| `DEV_CD_AUTO_DEPLOY` | Auto-deploy to DEV environment | `true` |
| `SIT_CD_AUTO_DEPLOY` | Auto-deploy to SIT environment | `true` |
| `PRD_CD_AUTO_DEPLOY` | Auto-deploy to PRD environment | `true` |

### Custom Dockerfile

```yaml
variables:
  CUSTOM_DOCKERFILE: "true"
  CUSTOM_DOCKERFILE_PATH: "${CI_PROJECT_DIR}/Dockerfile"
  CUSTOM_DOCKERFILE_STRICT_CHECK: "false"
```

## Pipeline Stages

```
.pre     → Environment preparation, variable computation
build    → Code build, Docker image build & push
test     → Unit tests, SonarQube scan
deploy   → GitOps deployment (update Helm values)
rollback → Rollback to previous version
```

## GitOps Integration

### Environment Branch Mapping

| Source Branch | Target Branch | Environment |
|---------------|---------------|-------------|
| `feat/*`, `feature/*` | `dev` | Development |
| `sit` | `sit` | Staging |
| `v*.*.*`, `prd` | `prd` | Production (MR required) |

### GitOps Workflow

```
CI Pipeline
  |
  +-- build → Push image to registry
  |
  +-- deploy → Clone charts repository
               Update image.tag in values.yaml
               Push changes / Create MR (PRD)
               ArgoCD detects change → Syncs cluster
```

## Docker Images

All builder images are hosted on GitHub Container Registry:

| Image | Tags | Included Tools |
|-------|------|----------------|
| `ghcr.io/cdryzun/glci-builder-java` | `jdk8`, `jdk11`, `jdk17` | Maven, Gradle, SonarScanner |
| `ghcr.io/cdryzun/glci-builder-nodejs` | `18`, `20`, `24` | pnpm, yarn, npm |
| `ghcr.io/cdryzun/glci-builder-python` | `3.10`, `3.11`, `3.12` | pip, poetry |
| `ghcr.io/cdryzun/glci-builder-golang` | `1.21`, `1.22`, `1.23` | Go toolchain |
| `ghcr.io/cdryzun/glci-builder-golang-nodejs` | `go1.23-node20`, ... | Go + Node.js |
| `ghcr.io/cdryzun/glci-toolbox` | `latest` | docker, helm, glab, yq, argocd |

## Troubleshooting

### Common Issues

#### 1. `unbound variable` Error

**Cause**: Script incompatibility with GitLab CI variable environment

**Solution**: Check if `set -u` was added, remove it or use `${VAR:-default}` syntax

#### 2. Docker Image Build Failure

**Checklist**:
- Dockerfile syntax errors
- Base image accessibility
- Build context correctness

#### 3. GitOps Deployment Failure

**Checklist**:
- `DEPLOY_REPO_PROJ` configuration correctness
- GitLab access token write permissions
- Helm values file path correctness

#### 4. CDN Cache Issues

Templates download scripts from GitHub raw URLs with a 5-minute CDN cache. Wait for cache expiration after fixes.

### Debugging Pipelines

```bash
# Get latest pipeline
glab api projects/${PROJECT_PATH}/pipelines | jq '.[0]'

# View all jobs
glab api projects/${PROJECT_PATH}/pipelines/${PIPELINE_ID}/jobs | jq '.[]'

# Get failure logs
glab api projects/${PROJECT_PATH}/jobs/${JOB_ID}/trace | tail -100
```

## Advanced Configuration

### Custom Runner Tags

```yaml
variables:
  RUNNER: "your-runner-tag"
```

### Cache Configuration

```yaml
variables:
  CACHE_DIR: "${CI_PROJECT_DIR}/.cache"
  NODE_CACHE_DISABLE: "false"
  PNPM_LOCKFILE_DISABLE: "false"
```

### Go Build Optimization

```yaml
variables:
  GO_CGO_ENABLED: "0"
  GO_ARCH: "amd64"
  GO_GOPROXY: "https://proxy.golang.org"
  GO_GOPRIVATE: "github.com/your-org/*"
```

### Docker Build Parameters

```yaml
variables:
  DOCKER_BUILD_FLAGS: '--no-cache'
  DOCKER_BUILDKIT: 1
  DOCKER_APP_TYPE: "production"  # Multi-stage build target
```

## Security

### Secret Scanning

Automatically runs Gitleaks scan on every push to prevent credential leakage.

### Container Image Scanning

Optional container image security scanning:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/jobs-templates/Trivy-Container-Scanning.stable.gitlab-ci.yml'
```

## Best Practices

1. **Use Stable Versions**: Use `*.stable.*` templates for production
2. **Minimize Configuration**: Leverage auto-detection, override only necessary variables
3. **Environment Isolation**: Use separate GitOps repositories or branches
4. **Access Control**: Configure sensitive information in GitLab CI/CD variables
5. **Monitor Cache**: Periodically clean `.cache` directory to prevent disk saturation

## Related Documentation

- [CD Environment Setup Guide](../../docs/cd/00-overview.md)
- [Template Development SOP](../../docs/SOP-Template-Development.md)
- [Troubleshooting Guide](../../docs/troubleshooting/README.md)
- [Project README](../../README.md)

## Support

- GitHub Issues: https://github.com/cdryzun/gitlab-ci-templates/issues
- Documentation: https://github.com/cdryzun/gitlab-ci-templates/tree/open/docs
