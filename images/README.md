# Docker Images

This directory contains the source code for all Docker images used by gitlab-ci-templates.

## Image Registry

All images are published to GitHub Container Registry:

```
ghcr.io/cdryzun/glci-<type>:<tag>
```

## Available Images

### Builder Images (CI Build Stage)

| Image | Tag | Description |
|-------|-----|-------------|
| `glci-builder-java` | `jdk8`, `jdk11`, `jdk17` | Maven/Gradle build with SonarQube scanner |
| `glci-builder-nodejs` | `18`, `20`, `24` | Node.js build with pnpm/yarn/npm |
| `glci-builder-python` | `3.10`, `3.11`, `3.12` | Python build with pip/poetry |
| `glci-builder-golang` | `1.21`, `1.22`, `1.23` | Go build environment |
| `glci-builder-golang-nodejs` | `go1.22-node20`, `go1.23-node20`, etc. | Multi-language builder for Go + Node.js |
| `glci-toolbox` | `latest` | Utility image with common tools |

### Runtime Images (Application Runtime)

| Image | Tag | Description |
|-------|-----|-------------|
| `glci-runtime-nginx` | `1.24`, `1.25` | Nginx for static files |
| `glci-runtime-openjdk` | `jdk8`, `jdk11`, `jdk17` | JRE runtime for Java apps |
| `glci-runtime-alpine` | `3.19`, `3.20` | Minimal Alpine base |

## Usage

### In GitLab CI

```yaml
variables:
  MAVEN_IMAGE: "ghcr.io/cdryzun/glci-builder-java:jdk17"
  NODE_IMAGE: "ghcr.io/cdryzun/glci-builder-nodejs:24"
  PYTHON_IMAGE: "ghcr.io/cdryzun/glci-builder-python:3.11"
  GO_IMAGE: "ghcr.io/cdryzun/glci-builder-golang:1.23"
  TOOLBOX_IMAGE: "ghcr.io/cdryzun/glci-toolbox:latest"
```

### Pull Images

```bash
# Java builder
docker pull ghcr.io/cdryzun/glci-builder-java:jdk17

# Node.js builder
docker pull ghcr.io/cdryzun/glci-builder-nodejs:24

# Toolbox
docker pull ghcr.io/cdryzun/glci-toolbox:latest
```

## Building Images Locally

```bash
# Build Java JDK 17
cd images/builders/java
docker build -f Dockerfile.jdk17 -t glci-builder-java:jdk17 .

# Build Node.js 24
cd images/builders/nodejs
docker build --build-arg NODE_VERSION=24 -t glci-builder-nodejs:24 .
```

## Image Details

### glci-builder-java

Includes:
- OpenJDK (8/11/17)
- Maven 3.9
- Gradle 8.x
- SonarScanner

### glci-builder-nodejs

Includes:
- Node.js (18/20/24)
- pnpm (default)
- yarn
- npm

### glci-builder-python

Includes:
- Python (3.10/3.11/3.12)
- pip
- poetry
- virtualenv

### glci-builder-golang

Includes:
- Go (1.21/1.22/1.23)
- Common build tools

### glci-toolbox

Includes:
- git
- curl/wget
- yq (YAML processor)
- jq (JSON processor)
- helm
- kubectl

## Contributing

When adding new images or updating existing ones:

1. Create/modify the Dockerfile in the appropriate directory
2. Update the GitHub Actions workflow (`.github/workflows/build-images.yml`)
3. Update this README with the new image details
4. Test the image locally before submitting a PR
