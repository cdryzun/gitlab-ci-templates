# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| stable  | Yes       |
| latest  | Development only |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Use [GitHub Security Advisories](https://github.com/cdryzun/gitlab-ci-templates/security/advisories/new) to report privately
3. Include a description of the vulnerability, steps to reproduce, and potential impact
4. Allow reasonable time for a fix before public disclosure

## Vulnerability Disclosure Timeline

- **Day 0**: Vulnerability reported
- **Day 1-3**: Acknowledgment sent to reporter
- **Day 7-14**: Fix developed and tested
- **Day 14-30**: Fix released, advisory published

## Security Best Practices for Users

When using these CI/CD templates in your projects:

### Credentials

- Store all secrets (tokens, passwords, registry credentials) in GitLab CI/CD Variables with **Masked** and **Protected** flags enabled
- Never hardcode credentials in `.gitlab-ci.yml` or any configuration file
- Use GitLab's built-in `CI_JOB_TOKEN` where possible instead of personal access tokens
- Rotate tokens regularly, especially `GITLAB_REPO_COMMIT_TOKEN` and `REGISTRY_PASSWORD`

### Runner Security

- Use project-specific runners for production deployments
- Enable runner isolation (Docker executor with `--privileged=false` where possible)
- Regularly update runner images and dependencies
- Restrict runner access using GitLab's protected runner feature

### Pipeline Security

- Enable branch protection rules for `main`, `sit`, and `prd` branches
- Require merge request approvals before deployment to production
- Review all values passed to `BUILD_SHELL` and `DOCKER_WORKSPACE_PREPARE_CMD` as they execute shell commands
- Enable the Gitleaks scanning stage to detect accidental secret commits

### Image Security

- Enable container scanning (Trivy or GitLab Container Scanning) in your pipeline
- Pin base image versions in custom Dockerfiles
- Use the provided builder images from `ghcr.io/cdryzun/glci-*` which are regularly updated
- Review the `CUSTOM_DOCKERFILE_STRICT_CHECK` variable to enforce Dockerfile restrictions
