# gitlab-ci-templates

> Drop-in CI/CD for GitLab. One `include`, full pipeline — build, test, scan, deploy.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/ci.yml/badge.svg)](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/ci.yml)
[![Build Images](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/build-images.yml/badge.svg)](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/build-images.yml)
[![GHCR](https://img.shields.io/badge/images-ghcr.io-blue?logo=docker)](https://github.com/cdryzun?tab=packages)
[![Stars](https://img.shields.io/github/stars/cdryzun/gitlab-ci-templates?style=social)](https://github.com/cdryzun/gitlab-ci-templates/stargazers)

---

**Get a production-grade CI/CD pipeline in 3 lines of YAML.**
Auto-detects Java, Node.js, Python, and Golang. Batteries included: Docker builds, SonarQube, ArgoCD GitOps, secret scanning, and rollback support.

---

## Why This Project?

| Pain Point | This Template |
|---|---|
| Every project reinvents the pipeline | One shared template, consistent across all repos |
| CI config grows to 500+ lines | 3-line include, sensible defaults |
| Language-specific quirks need custom setup | Auto-detection handles Maven, pnpm, pip, go modules |
| Deployment is stitched together manually | Built-in ArgoCD GitOps + Helm + rollback |
| Secrets leak in pipelines | Gitleaks scanning on every push |

---

## Quickstart (30 seconds)

Add one line to your `.gitlab-ci.yml`:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'
```

That's it. Push and watch your pipeline run.

**Optional overrides:**

```yaml
variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  UNIT_TEST_ENABLE: "true"
  DOCKER_REGISTRY: "docker.io"
```

---

## What You Get

```
.pre     ->  Environment prep, variable injection
build    ->  Auto-detected build (Maven / pnpm / pip / go)
             Docker image build & push (multi-arch)
test     ->  Unit tests with language-specific runners
             SonarQube code quality scan (optional)
deploy   ->  ArgoCD GitOps sync via Helm values update
rollback ->  One-job rollback to previous image tag
```

---

## Language Examples

### Java

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "mvn clean package -Dmaven.test.skip=true"
  DOCKERFILE_BUILD_JDK_VERSION: "17-alpine"
```

### Node.js

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pnpm run build"
  PACKAGE_MANAGER: "pnpm"
```

### Python

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "pip install -r requirements.txt"
```

### Golang

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "go build -o app ./..."
```

### Golang + Node.js (Embedded Frontend)

For projects that embed frontend assets into Go binaries via `go:embed`:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BASE_BUILD_IMAGE: "ghcr.io/cdryzun/glci-builder-golang-nodejs:go1.23-node20"
  BUILD_SHELL: |
    cd web && pnpm install && pnpm build && cd .. \
    && go mod tidy && go build -o app ./...
```

**Available Golang+Node.js images:**

| Tag | Go | Node.js |
|---|---|---|
| `go1.23-node20` | 1.23 | 20 LTS |
| `go1.23-node22` | 1.23 | 22 LTS |
| `go1.24-node20` | 1.24 | 20 LTS |
| `go1.24-node22` | 1.24 | 22 LTS |
| `go1.24-node24` | 1.24 | 24 |
| `go1.25-node22` | 1.25 | 22 LTS |
| `go1.25-node24` | 1.25 | 24 |
| `go1.26-node22` | 1.26 | 22 LTS |
| `go1.26-node24` | 1.26 | 24 |

---

## CI Builder Images

Pre-built images on GitHub Container Registry — no external dependencies at runtime.

| Image | Tags | Includes |
|---|---|---|
| `ghcr.io/cdryzun/glci-builder-java` | `jdk8`, `jdk11`, `jdk17` | Maven, Gradle, SonarScanner |
| `ghcr.io/cdryzun/glci-builder-nodejs` | `18`, `20`, `24` | pnpm, yarn, npm |
| `ghcr.io/cdryzun/glci-builder-python` | `3.10`, `3.11`, `3.12` | pip, poetry |
| `ghcr.io/cdryzun/glci-builder-golang` | `1.21`, `1.22`, `1.23` | Go toolchain |
| `ghcr.io/cdryzun/glci-builder-golang-nodejs` | `go1.23-node20`, ... | Go + Node.js combo |
| `ghcr.io/cdryzun/glci-toolbox` | `latest` | docker, helm, glab, yq, argocd |

---

## GitOps Deployment (ArgoCD)

The templates support a GitOps workflow: push image tag to a Helm values repo, ArgoCD syncs automatically.

```
CI Pipeline
    |
    +-- build --> push image to registry
    |
    +-- deploy --> clone charts repo
                   update image.tag in values.yaml
                   push / create MR (PRD)
                   ArgoCD detects change --> syncs cluster
```

Environment branching:

| Source Branch | Target | Environment |
|---|---|---|
| `feat/*` / `feature/*` | `dev` | Development |
| `sit` | `sit` | Staging |
| `v*.*.*` / `prd` | `prd` | Production (MR required) |

---

## Configuration Reference

### Core Variables

| Variable | Description | Default |
|---|---|---|
| `BUILD_SHELL` | Build command | auto-detected |
| `UNIT_TEST_ENABLE` | Run unit tests | `true` |
| `DOCKER_IMAGE_BUILD` | Build and push Docker image | `true` |
| `DOCKER_REGISTRY` | Docker registry URL | `docker.io` |
| `SONAR_URL` | SonarQube server URL | — |
| `SONAR_GATE` | Fail pipeline on quality gate | `false` |

### Custom Dockerfile

```yaml
variables:
  CUSTOM_DOCKERFILE: "true"
  CUSTOM_DOCKERFILE_PATH: "${CI_PROJECT_DIR}/Dockerfile"
```

### Library Projects (No Docker Build)

```yaml
variables:
  DOCKER_IMAGE_BUILD: "false"
```

---

## Repository Layout

```
templates/              # Entry point — include these in your projects
jobs-templates/         # Reusable job definitions per language/stage
utils/                  # Rule snippets, before/after scripts
vars/                   # Default variable definitions
scripts/                # Shell scripts executed by CI jobs
dockerfile/templates/   # Application Dockerfile templates
images/                 # CI builder image sources (Java, Node, Python, Go)
.github/workflows/      # Builder image CI + secret scanning
```

The project uses a two-track system:
- `*.stable.*` — production-ready
- `*.latest.*` — experimental / in-development

---

## Security

Secret scanning runs automatically on every push via [Gitleaks](https://github.com/gitleaks/gitleaks).

[![Secret Scan](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/ci.yml/badge.svg)](https://github.com/cdryzun/gitlab-ci-templates/actions/workflows/ci.yml)

---

## Contributing

Issues and PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

If this project saves you time, consider giving it a star — it helps others find it.

---

## License

MIT — see [LICENSE](LICENSE) for details.
