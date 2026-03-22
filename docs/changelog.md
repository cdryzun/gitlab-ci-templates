# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `DOCKER_MIRROR_PREFIX` variable for accelerating Dockerfile base image pulls via mirror proxy
- `IMAGE_MIRROR_PREFIX` variable for accelerating CI builder image pulls (ghcr.io)
- `APP_NAME` build-arg dynamically injected from `MAVEN_APP_NAME` or `CI_PROJECT_NAME` for identifiable JAR filenames
- `CI_JOB_TOKEN` authentication support in script/dockerfile downloads for private GitLab instances
- `Auto-DevOps.self-hosted.gitlab-ci.yml` entry point for self-hosted GitLab deployments
- `docs/VARIABLE_REFERENCE.md` with full variable list (60+ variables)
- `SECURITY.md` with vulnerability reporting process
- `CHANGELOG.md` for tracking project changes
- GitHub Issue and Pull Request templates
- 8 ready-to-use example configs: Java, Gradle, Node.js frontend/backend, Python, Go, Go+GitOps, library
- Acceleration/mirrors section in README for China mainland deployments

### Security

- Hardened `shell_exec` function: replaced `echo|bash` pipe with `bash -c` to prevent command injection
- Replaced `eval` with `bash -c` for Docker workspace preparation commands
- Removed leaked internal credentials from `.gitleaks.toml` allowlist
- Removed internal domain references (`iquantex.com`) from all templates and examples
- Added `set -eo pipefail` across all shell scripts for robust error handling

### Fixed

- Fixed default value quoting in unit-test/build/sonarqube scripts (`'mvn test'` -> `mvn test`)
- Fixed Java Dockerfile COPY pattern: `app*.jar` -> `*.jar` to support custom `MAVEN_APP_NAME`
- Fixed `dotenv()` function to properly quote variable assignments
- Fixed `#!/bin/bash` shebangs to portable `#!/usr/bin/env bash`
- Fixed Python build workspace recursive copy error
- Added backward-compatible variable alias `CD_DEPLOY_IMAGE` for typo `CD_DEPLOY_IMGAGE`
- Added backward-compatible `requirements-build.txt` detection alongside legacy `requestments-build.txt`

### Changed

- README rewritten with Mermaid architecture diagrams, before/after comparison, and acceleration guide
- Removed AI tool artifacts (`.agents/`, `.spec-workflow/`, `.serena/`, `PROJECT_ANALYSIS.md`)
- Upgraded CI workflow with real yamllint, shellcheck, and template validation (no more `|| true`)
- Simplified verbose comments across shell scripts for readability

## [1.0.0] - 2024-01-01

### Added

- Initial open-source release
- Auto-detection for Java (Maven/Gradle), Node.js, Python, and Golang projects
- Docker image build and push with single and multi-architecture support
- ArgoCD GitOps deployment integration with Helm values update
- SonarQube code quality scanning integration
- Gitleaks secret scanning on every push
- Two-track system (`*.stable.*` / `*.latest.*`) for template versioning
- CI builder images published to GitHub Container Registry (`ghcr.io/cdryzun/glci-*`)
- Rollback support for quick recovery via image tag revert
- Environment-based deployment branching (dev/sit/prd)
- Custom Dockerfile support with strict validation option
- Multi-project (mono-repo) sub-project auto-detection
- Golang+Node.js combo builder images for embedded frontend projects
