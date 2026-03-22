# Variable Reference

All variables with their defaults and descriptions. Override any of these in your `.gitlab-ci.yml`.

## Build

| Variable | Default | Description |
|----------|---------|-------------|
| `BUILD_SHELL` | _(auto-detected)_ | Build command. When empty, auto-selects based on `PROJECT_TYPE`. |
| `PROJECT_TYPE` | _(auto-detected)_ | `java` / `web` / `python` / `golang`. Usually no need to set manually. |
| `PACKAGE_MANAGER` | `pnpm` | Node.js package manager: `pnpm` or `yarn`. |
| `MAVEN_APP_NAME` | `app` | Final JAR name after Maven packaging. |
| `BUILD_MAVEN_POM_FILE` | `pom.xml` | Path to pom.xml (for non-root Maven projects). |
| `GO_CGO_ENABLED` | `0` | CGO switch for Go builds. |
| `GO_ARCH` | `amd64` | Target architecture for Go builds. |
| `GO_GOPROXY` | _(empty)_ | Custom GOPROXY for Go module downloads. |
| `GO_GOPRIVATE` | _(empty)_ | GOPRIVATE pattern for bypassing proxy on private modules. |
| `NODE_OPTIONS` | `--max_old_space_size=4096` | Node.js memory limit during build. |
| `STATIC_FILE_NAME` | _(empty)_ | Frontend output directory (default: `dist`). Set if your build outputs to a different folder. |
| `PNPM_LOCKFILE_DISABLE` | `false` | Skip pnpm lockfile check during install. |

## Docker Image

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_IMAGE_BUILD` | `true` | Set to `false` for library projects (no Docker image). |
| `DOCKER_REGISTRY` | `docker.io` | Docker registry URL. |
| `DOCKER_HUB_ORGANIZATION` | `cdryzun` | Docker Hub organization/username (only for docker.io). |
| `IMG_NAME` | _(auto-generated)_ | Full image name without tag. Built from registry + namespace + project. |
| `DOCKER_IMAGE_TAG` | _(auto-generated)_ | Image tag, derived from branch name + timestamp + commit SHA. |
| `DOCKER_BUILD_FLAGS` | `--no-cache` | Extra `docker build` flags. |
| `DOCKER_MIRROR_PREFIX` | _(empty)_ | Docker Hub mirror prefix with trailing slash (e.g., `proxyhub.example.com/`). Prepended to base images in Dockerfile templates. |
| `DOCKER_DAEMON_WORKSPACE` | `./docker-build` | Working directory for Docker build context. |
| `DOCKER_WORKSPACE_PREPARE_CMD` | _(empty)_ | Shell command to run inside build workspace before `docker build`. |
| `CUSTOM_DOCKERFILE` | _(auto-detected)_ | Set to `true` to use project's own Dockerfile instead of built-in templates. |
| `CUSTOM_DOCKERFILE_PATH` | _(empty)_ | Path to custom Dockerfile (relative or absolute). |
| `CUSTOM_DOCKERFILE_STRICT_CHECK` | `false` | Reject Dockerfiles containing `ENTRYPOINT`, `USER`, `CMD`, etc. |
| `DOCKER_APP_TYPE` | _(empty)_ | Target stage for multi-stage builds (e.g., `production`). |
| `FEAT_DOCKER_IMAGE_BUILD` | `false` | Build Docker images on `feat/*` branches. |
| `DOCKERFILE_BUILD_JDK_VERSION` | `17-alpine` | JDK version for Java Dockerfile template. |
| `RELEASE_BUILD` | `false` | Treat current build as a release (uses tag as version). |
| `RELEASE_RETAG_DISABLE` | `false` | Force rebuild instead of retagging existing image. |

## Testing

| Variable | Default | Description |
|----------|---------|-------------|
| `UNIT_TEST_ENABLE` | `true` | Enable unit test stage. |
| `JAVA_UNIT_TEST_SHELL` | _(empty)_ | Custom test command for Java (default: `mvn test`). |
| `NODE_UNIT_TEST_SHELL` | _(empty)_ | Custom test command for Node.js (default: `pnpm test`). |
| `PYTHON_UNIT_TEST_SHELL` | _(empty)_ | Custom test command for Python (default: `python -m unittest`). |
| `GO_UNIT_TEST_SHELL` | _(empty)_ | Custom test command for Go (default: `go test ./... -count=1`). |

## SonarQube

| Variable | Default | Description |
|----------|---------|-------------|
| `SONAR_URL` | _(required)_ | SonarQube server URL. Configure in GitLab CI/CD Variables. |
| `SONAR_TOKEN` | _(required)_ | SonarQube authentication token. Configure in GitLab CI/CD Variables. |
| `SONAR_DIR` | `./src` | Source directory for analysis. Auto-detected if missing. |
| `SONAR_GATE` | `false` | Fail pipeline when quality gate fails. |
| `SONAR_SCAN_ARGS` | _(empty)_ | Extra sonar-scanner arguments. |
| `MIN_COVERAGE` | `80` | Minimum coverage threshold (%). |

## CD / GitOps Deployment

| Variable | Default | Description |
|----------|---------|-------------|
| `DEPLOY_REPO` | _(required)_ | Git URL of the Helm values repository. |
| `DEPLOY_VALUE_FILE` | `values.yaml` | Values file to update in the charts repo. |
| `DEPLOY_REPO_YAML_TAG` | `.image.tag` | YAML path to the image tag field (yq syntax). |
| `DEPLOY_REPO_PROJ` | `${CI_PROJECT_NAME}` | Directory name in the charts repo for this project. |
| `DEPLOY_COMMIT_MESSAGE` | `chore: helm values updated by gitlab-ci pipeline` | Commit message for auto-updates. |
| `REMOTE_BRANCH` | `dev` | Target branch in the charts repo (auto-set by branch rules). |
| `GIT_AUTO_COMMIT_NAME` | `ci-bot` | Git username for automated commits. |
| `GIT_AUTO_COMMIT_EMAIL` | `ci-bot@example.com` | Git email for automated commits. |
| `DEV_CD_AUTO_DEPLOY` | `true` | Auto-deploy on dev branch push. |
| `SIT_CD_AUTO_DEPLOY` | `true` | Auto-deploy on sit branch push. |
| `PRD_CD_AUTO_DEPLOY` | `true` | Auto-deploy on prd branch push. |
| `FEAT_CD_AUTO_DEPLOY` | `false` | Auto-deploy on feat/* branch push. |

## Container Scanning

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_IMAGE_SCAN_IMAGE` | `false` | Enable container vulnerability scanning. |
| `ENFORCE_EXIT` | `false` | Fail pipeline on medium+ severity vulnerabilities. |

## Builder Images

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_BUILD_IMAGE` | _(empty)_ | Override auto-selected builder image for all stages. |
| `MAVEN_IMAGE` | `ghcr.io/cdryzun/glci-builder-java:jdk17` | Java builder image. |
| `GRADLE_IMAGE` | `ghcr.io/cdryzun/glci-builder-java:jdk17` | Gradle builder image. |
| `NODE_IMAGE` | `ghcr.io/cdryzun/glci-builder-nodejs:20` | Node.js builder image. |
| `PYTHON_IMAGE` | `ghcr.io/cdryzun/glci-builder-python:3.11` | Python builder image. |
| `GO_IMAGE` | `ghcr.io/cdryzun/glci-builder-golang:1.23` | Go builder image. |
| `TOOLBOX_IMAGE` | `ghcr.io/cdryzun/glci-toolbox:latest` | Toolbox image (helm, yq, glab, argocd). |

## Registries

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_REGISTRY` | `docker.io` | Docker image registry. |
| `NODE_REGISTRY` | `https://registry.npmmirror.com` | npm registry mirror. |
| `PYPI` | `https://pypi.org/simple` | Python package index. |

## Infrastructure

| Variable | Default | Description |
|----------|---------|-------------|
| `RUNNER` | `default` | GitLab runner tag. |
| `TEMPLATE_BRANCH_NAME` | `open` | Branch of this template repo to pull from. |
| `CI_DEBUG_TRACE` | `false` | Enable verbose debug output (prints all commands). |
| `LOG_LEVEL` | `info` | Log verbosity level. |

## Branch-to-Environment Mapping

The pipeline auto-maps branches to deployment environments:

| Branch Pattern | Environment | Docker Tag Pattern |
|---------------|-------------|-------------------|
| `dev` / `main` | dev | `dev-{time}-{sha}-{pipeline}` |
| `feat/*` / `feature/*` | dev | `feat-xxx-{time}-{sha}-{pipeline}` |
| `sit` | sit | `sit-{time}-{sha}-{pipeline}` |
| `prd` | prd | via MR to charts repo |
| `v*.*.*` (tag) | prd (release) | `*.*.*` (semver) |
