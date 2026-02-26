# gitlab-ci-templates

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Actions](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/build-images.yml/badge.svg)](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/build-images.yml)
[![GitHub Container Registry](https://img.shields.io/badge/ghcr.io-cdryzun-blue)](https://github.com/cdryzun?tab=packages)

A collection of reusable GitLab CI/CD templates for streamlined, consistent, and maintainable delivery pipelines. Supports **Java**, **Node.js**, **Python**, and **Golang** projects with minimal configuration.

## Features

- **Multi-language Support**: Java (Maven/Gradle), Node.js, Python, Golang
- **Auto Detection**: Automatically detects project type and applies appropriate pipeline
- **Built-in Quality Gates**: Unit testing, SonarQube code scanning
- **Docker Integration**: Automated image building with multi-arch support
- **GitOps Ready**: ArgoCD/Helm deployment integration

## Quick Start

### 1. Include the Template

Create or update your `.gitlab-ci.yml`:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  UNIT_TEST_ENABLE: "true"
```

### 2. Configure CI/CD Variables (Optional)

If you want to customize the registry or other settings:

```yaml
variables:
  # Docker registry (default: docker.io for application images)
  DOCKER_REGISTRY: "docker.io"

  # SonarQube (optional)
  SONAR_URL: "https://sonarqube.example.com"
  SONAR_TOKEN: "${SONARQUBE_TOKEN}"  # Set in GitLab CI/CD variables
```

### 3. Push and Watch

Push your code and watch the pipeline run automatically.

## Project Types

### Java Project

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  DOCKERFILE_BUILD_JDK_VERSION: "17-alpine"
```

### Node.js Project

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
```

### Python Project

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pip install -r requirements.txt"
```

### Golang Project

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "go build -o app ./..."
```

### Golang + Node.js Project (Frontend Embedded in Go Binary)

For projects that embed frontend static files into Go binaries (e.g., using `go:embed`):

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  # Use the multi-language builder image
  BASE_BUILD_IMAGE: "ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.23-node20"

  # Build frontend first, then compile Go binary with embedded assets
  BUILD_SHELL: |
    cd web && pnpm install && pnpm build && cd .. \
    && go mod tidy && go build -o app ./...

  # Optional: customize frontend output directory
  # STATIC_FILE_NAME: "web/dist"
```

**Available Golang+Node.js Images:**

| Image Tag | Go Version | Node.js Version | Type |
|-----------|------------|-----------------|------|
| `go1.22-node20` | 1.22 | 20 | LTS |
| `go1.22-node22` | 1.22 | 22 | LTS |
| `go1.23-node20` | 1.23 | 20 | LTS |
| `go1.23-node22` | 1.23 | 22 | LTS |
| `go1.24-node20` | 1.24 | 20 | LTS |
| `go1.24-node22` | 1.24 | 22 | LTS |
| `go1.24-node24` | 1.24 | 24 | Current |
| `go1.25-node22` | 1.25 | 22 | LTS |
| `go1.25-node24` | 1.25 | 24 | Current |
| `go1.25-node25` | 1.25 | 25 | Latest |
| `go1.26-node22` | 1.26 | 22 | LTS |
| `go1.26-node24` | 1.26 | 24 | Current |
| `go1.26-node25` | 1.26 | 25 | Latest |

## Available Images

All CI builder images are available on GitHub Container Registry:

| Image | Tags | Description |
|-------|------|-------------|
| `ghcr.io/cdryzun/glci-builder-java` | `jdk8`, `jdk11`, `jdk17` | Java build with Maven, Gradle, SonarScanner |
| `ghcr.io/cdryzun/glci-builder-nodejs` | `18`, `20`, `24` | Node.js build with pnpm, yarn, npm |
| `ghcr.io/cdryzun/glci-builder-python` | `3.10`, `3.11`, `3.12` | Python build with pip, poetry |
| `ghcr.io/cdryzun/glci-builder-golang` | `1.21`, `1.22`, `1.23` | Go build environment |
| `ghcr.io/cdryzun/glci-builder-golang-nodejs` | `go1.22-node20`, `go1.22-node22`, `go1.23-node20`, `go1.23-node22`, `go1.24-node20`, `go1.24-node22`, `go1.24-node24`, `go1.25-node22`, `go1.25-node24`, `go1.25-node25`, `go1.26-node22`, `go1.26-node24`, `go1.26-node25` | Multi-language builder for Go + Node.js projects |
| `ghcr.io/cdryzun/glci-toolbox` | `latest` | Utility image with common tools |

## Directory Structure

```
gitlab-ci-templates/
├── templates/              # Ready-to-use GitLab CI templates
│   └── Auto-DevOps.gitlab-ci.yml
├── jobs-templates/         # Reusable job definitions
├── utils/                  # Utility job snippets
├── vars/                   # Default variables
├── scripts/                # Shell scripts for CI jobs
├── dockerfile/templates/   # Application Dockerfile templates
├── images/                 # Source for CI builder images
└── .github/workflows/      # Image build pipelines
```

## Configuration Reference

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BUILD_SHELL` | Build command | (auto-detected) |
| `UNIT_TEST_ENABLE` | Enable unit tests | `true` |
| `DOCKER_IMAGE_BUILD` | Build Docker image | `true` |
| `SONAR_URL` | SonarQube server URL | - |
| `SONAR_GATE` | Fail on quality gate | `false` |
| `DOCKER_REGISTRY` | Docker registry URL | `docker.io` |

### Custom Dockerfile

To use a custom Dockerfile:

```yaml
variables:
  CUSTOM_DOCKERFILE_PATH: "docker/Dockerfile"
```

### Disable Docker Image Build

For library projects:

```yaml
variables:
  DOCKER_IMAGE_BUILD: "false"
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by GitLab's Auto DevOps
- Built with best practices from various CI/CD implementations
