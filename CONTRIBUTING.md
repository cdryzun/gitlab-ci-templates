# Contributing to gitlab-ci-templates

Thanks for your interest in contributing!

## Reporting Issues

1. Check [existing issues](https://github.com/cdryzun/gitlab-ci-templates/issues) first
2. Create a new issue with:
   - Your GitLab version and runner executor type
   - The `.gitlab-ci.yml` config you used
   - Relevant CI job logs (redact secrets)

## Submitting Changes

1. Fork the repository
2. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature
   ```
3. Make your changes following the style guide below
4. Test locally:
   ```bash
   # Lint YAML
   yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" templates/*.yml jobs-templates/*.yml

   # Lint shell scripts
   shellcheck -e SC1090,SC1091,SC2034,SC2154 scripts/*.sh

   # Run pre-script matrix test
   hack/test-pre-matrix.sh
   ```
5. Commit with [conventional commits](https://www.conventionalcommits.org/):
   ```bash
   git commit -m "feat: add support for Rust projects"
   ```
6. Open a Pull Request

## Style Guide

### YAML
- 2-space indentation, lines under 120 chars
- Quote strings with special characters

### Shell
- `#!/usr/bin/env bash` shebang
- `set -eo pipefail` (use `set -euo pipefail` only in scripts designed for it)
- Quote all variable references: `"${VAR}"`
- Use `$()` instead of backticks

### Dockerfile
- Pin base image versions
- Multi-stage builds when appropriate
- Order layers by change frequency
- Support `DOCKER_MIRROR_PREFIX` for base images

### Two-Track System

All template files exist in two versions:
- `*.stable.*` -- production-ready, breaking changes require version bump
- `*.latest.*` -- experimental, may change without notice

Always update both when modifying core logic.

## Project Structure

```
templates/              # Entry points for downstream projects
jobs-templates/         # Reusable job definitions per stage
utils/                  # Rule snippets, before/after scripts
vars/                   # Default variable configurations
scripts/                # Shell scripts executed by CI jobs
dockerfile/templates/   # Application Dockerfile templates
images/                 # CI builder image Dockerfiles
examples/               # Ready-to-use .gitlab-ci.yml examples
docs/                   # Documentation
hack/                   # Development and testing scripts
```

## License

By contributing, you agree your contributions will be licensed under the MIT License.
