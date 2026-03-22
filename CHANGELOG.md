# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Security

- Hardened `shell_exec` function: replaced `echo|bash` pipe with `bash -c` to prevent command injection
- Replaced `eval` with `bash -c` for safer command execution in Docker workspace preparation
- Standardized all shell scripts to use `set -euo pipefail` for robust error handling
- Fixed unquoted variables in `_utils.sh` that could cause word splitting issues

### Added

- `SECURITY.md` with vulnerability reporting process and security best practices
- `CHANGELOG.md` for tracking project changes
- GitHub Issue templates (bug report, feature request)
- GitHub Pull Request template with testing checklist
- Backward-compatible variable aliases for corrected spelling (`CD_DEPLOY_IMAGE`, `CUSTOM_REMOTE_*`)

### Fixed

- Fixed `dotenv()` function to properly quote variable assignments
- Fixed `#!/bin/bash` shebangs to portable `#!/usr/bin/env bash`
- Fixed inconsistent `set` flags across shell scripts (now all use `set -euo pipefail`)

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
