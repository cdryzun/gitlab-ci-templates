# gitops-go-hello

GitOps Helm chart repository for go-hello application.

## Repository

**GitHub:** https://github.com/cdryzun/gitops-go-hello

## Structure

```
.
├── go-hello/           # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── dev/                # Dev environment values
├── sit/                # SIT environment values
└── prd/                # Production environment values
```

## Usage

```bash
# Install to dev environment
helm install go-hello-dev ./go-hello -f dev/values.yaml

# Upgrade
helm upgrade go-hello-dev ./go-hello -f dev/values.yaml
```

## CI/CD Integration

This repository is automatically updated by GitLab CI pipelines from the [go-hello](https://gitlab.treesir.pub/sre/devops/go-hello) application.

## Related Projects

- [gitlab-ci-templates](https://github.com/cdryzun/gitlab-ci-templates) - CI/CD templates
- [go-hello](https://gitlab.treesir.pub/sre/devops/go-hello) - Source application
