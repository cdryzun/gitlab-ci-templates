# GitLab CI Templates Quick Reference

Quick reference card for common configurations and commands.

## One-Minute Integration

```yaml
# .gitlab-ci.yml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'
```

## Language Quick Configuration

### Java
```yaml
variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  DOCKERFILE_BUILD_JDK_VERSION: "17-alpine"
```

### Node.js
```yaml
variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
```

### Python
```yaml
variables:
  BUILD_SHELL: "pip install -r requirements.txt"
```

### Golang
```yaml
variables:
  BUILD_SHELL: "go build -o app ./..."
```

## Common Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `DOCKER_IMAGE_BUILD` | `"false"` | Library project, skip image build |
| `UNIT_TEST_ENABLE` | `"false"` | Disable unit tests |
| `CUSTOM_DOCKERFILE` | `"true"` | Use custom Dockerfile |
| `DOCKER_REGISTRY` | `"your-registry.com"` | Custom image registry |

## GitOps Configuration

```yaml
variables:
  DEPLOY_REPO_PROJ: "group/project"
  DEPLOY_VALUE_FILE: "values.yaml"
  DEPLOY_REPO_YAML_TAG: ".image.tag"
  DEV_CD_AUTO_DEPLOY: "true"
  SIT_CD_AUTO_DEPLOY: "true"
  PRD_CD_AUTO_DEPLOY: "true"
```

## Builder Image Tags

### Java
- `ghcr.io/cdryzun/glci-builder-java:jdk8`
- `ghcr.io/cdryzun/glci-builder-java:jdk11`
- `ghcr.io/cdryzun/glci-builder-java:jdk17`

### Node.js
- `ghcr.io/cdryzun/glci-builder-nodejs:18`
- `ghcr.io/cdryzun/glci-builder-nodejs:20`
- `ghcr.io/cdryzun/glci-builder-nodejs:24`

### Python
- `ghcr.io/cdryzun/glci-builder-python:3.10`
- `ghcr.io/cdryzun/glci-builder-python:3.11`
- `ghcr.io/cdryzun/glci-builder-python:3.12`

### Golang
- `ghcr.io/cdryzun/glci-builder-golang:1.21`
- `ghcr.io/cdryzun/glci-builder-golang:1.22`
- `ghcr.io/cdryzun/glci-builder-golang:1.23`

### Golang + Node.js
- `ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.23-node20`
- `ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.24-node22`

## Pipeline Stages

```
.pre     → Environment preparation
build    → Build and image push
test     → Test and scan
deploy   → GitOps deployment
rollback → Version rollback
```

## Debugging Commands

```bash
# View latest pipeline
glab api projects/${PROJECT_PATH}/pipelines | jq '.[0]'

# View all jobs
glab api projects/${PROJECT_PATH}/pipelines/${PIPELINE_ID}/jobs

# Get job logs
glab api projects/${PROJECT_PATH}/jobs/${JOB_ID}/trace

# Trigger pipeline
git commit --allow-empty -m "chore: trigger pipeline"
git push
```

## Troubleshooting

### `unbound variable` Error
- Check if `set -u` was added
- Use `${VAR:-default}` syntax

### Image Build Failure
- Verify Dockerfile syntax
- Check base image accessibility
- Confirm build context path

### GitOps Deployment Failure
- Verify `DEPLOY_REPO_PROJ` configuration
- Check access token permissions
- Confirm values file path

### CDN Cache Issues
- Wait 5 minutes for cache expiration
- Or add timestamp parameter to URL

## Environment Branch Rules

| Source Branch | Target Branch | Environment | Auto Deploy |
|---------------|---------------|-------------|-------------|
| `feat/*` | `dev` | DEV | Yes |
| `sit` | `sit` | SIT | Yes |
| `v*.*.*` | `prd` | PRD | Yes (MR required) |

## Complete Examples

### Java Microservice
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  UNIT_TEST_ENABLE: "true"
  DOCKERFILE_BUILD_JDK_VERSION: "17-alpine"
  SONAR_URL: "https://sonar.example.com"
  SONAR_GATE: "true"
  DEPLOY_REPO_PROJ: "devops/helm-charts"
```

### Node.js Frontend
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
  UNIT_TEST_ENABLE: "false"
  CUSTOM_NGINX_CONF: "docker/nginx.conf"
```

### Golang + React
```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BASE_BUILD_IMAGE: "ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.23-node20"
  BUILD_SHELL: |
    cd web && pnpm install && pnpm build && cd .. \
    && go mod tidy && go build -o app ./...
```

## Related Links

- GitHub: https://github.com/cdryzun/gitlab-ci-templates
- Documentation: https://github.com/cdryzun/gitlab-ci-templates/tree/open/docs
- Issues: https://github.com/cdryzun/gitlab-ci-templates/issues
