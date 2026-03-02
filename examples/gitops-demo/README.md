# GitOps Demo - go-hello

This is a complete GitOps demonstration project showing CI/CD workflow with GitLab CI and ArgoCD.

## Related Repositories

| Repository | Description | Link |
|------------|-------------|------|
| gitlab-ci-templates | CI/CD templates | [GitHub](https://github.com/cdryzun/gitlab-ci-templates) |
| go-hello | Source application | [GitLab](https://gitlab.treesir.pub/sre/devops/go-hello) |
| gitops-go-hello | GitOps Helm charts | [GitHub](https://github.com/cdryzun/gitops-go-hello) |

## Workflow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Git Push      │────▶│   GitLab CI     │────▶│  Build Image    │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                       │
                                                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   ArgoCD Sync   │◀────│   Webhook       │◀────│  Update GitOps  │
│   (Kubernetes)  │     │   Trigger       │     │  Repository     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Documentation

- [PVE + K3s NodePort Compatibility](../../docs/troubleshooting/networking/pve-k3s-nodeport-compatibility.md)
- [ArgoCD Webhook Setup](../../docs/troubleshooting/kubernetes/argocd-webhook-setup.md)

## License

MIT
