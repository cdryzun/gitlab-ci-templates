# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **gitlab-ci-templates**, a collection of reusable GitLab CI/CD templates for streamlined, consistent, and maintainable delivery pipelines. Supports Java, Node.js, Python, and Golang projects with auto-detection, quality gates, and Docker integration.

## Development Commands

### Build Docker Images Locally

```bash
# Java builder (JDK 17)
cd images/builders/java && docker build -f Dockerfile.jdk17 -t glci-builder-java:jdk17 .

# Node.js builder (version 24)
cd images/builders/nodejs && docker build --build-arg NODE_VERSION=24 -t glci-builder-nodejs:24 .

# Python builder (3.11)
cd images/builders/python && docker build --build-arg PYTHON_VERSION=3.11 -t glci-builder-python:3.11 .

# Golang builder (1.23)
cd images/builders/golang && docker build --build-arg GO_VERSION=1.23 -t glci-builder-golang:1.23 .
```

### Linting

```bash
# YAML files
yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}}}" templates/*.yml jobs-templates/*.yml

# Shell scripts
shellcheck scripts/*.sh
```

### GitHub Actions (Image Publishing)

```bash
# Trigger specific image build manually
gh workflow run build-images.yml -f image=java -f push=true
```

## Architecture

```
templates/              # Entry points - include these in downstream projects
jobs-templates/         # Reusable job definitions (Build, Test, Deploy, SonarQube)
utils/                  # Utility snippets (rules, before/after scripts)
vars/                   # Default variable configurations
scripts/                # Shell scripts executed by CI jobs
dockerfile/templates/   # Application Dockerfile templates (java, web, python, golang)
images/                 # CI builder images (Java, Node, Python, Go, toolbox)
```

### Two-Track System

- `*.stable.*` files: Production-ready templates
- `*.latest.*` files: Development/experimental templates

### Key Flow

1. `templates/Auto-DevOps.gitlab-ci.yml` is the main entry point
2. It includes jobs from `jobs-templates/` based on `PROJECT_TYPE` (auto-detected)
3. Jobs execute shell scripts from `scripts/`
4. Docker images are built using templates from `dockerfile/templates/`

## Code Style

- YAML: 2-space indentation, lines under 120 characters
- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, meaningful variable names
- Dockerfile: Multi-stage builds, pinned base image versions, ordered by layer change frequency

## Key Variables

| Variable | Purpose |
|----------|---------|
| `PROJECT_TYPE` | Auto-detected: java, nodejs, python, golang |
| `BUILD_SHELL` | Build command override |
| `DOCKER_IMAGE_BUILD` | Set to "false" for library projects |
| `TEMPLATE_BRANCH_NAME` | Template branch (default: main) |

