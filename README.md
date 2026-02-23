# gitlab-ci-templates

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Actions](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/build-images.yml/badge.svg)](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/build-images.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/cdryzun/glci-toolbox.svg)](https://hub.docker.com/u/cdryzun)

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
  # Docker registry (default: docker.io)
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

## Available Images

All CI builder images are available on Docker Hub:

| Image | Tags | Description |
|-------|------|-------------|
| `cdryzun/glci-builder-java` | `jdk8`, `jdk11`, `jdk17` | Java build with Maven, Gradle, SonarScanner |
| `cdryzun/glci-builder-nodejs` | `18`, `20`, `24` | Node.js build with pnpm, yarn, npm |
| `cdryzun/glci-builder-python` | `3.10`, `3.11`, `3.12` | Python build with pip, poetry |
| `cdryzun/glci-builder-golang` | `1.21`, `1.22`, `1.23` | Go build environment |
| `cdryzun/glci-toolbox` | `latest` | Utility image with common tools |

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
