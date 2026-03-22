# Troubleshooting Guide

This directory collects various problems encountered in actual projects and their solutions, helping to quickly locate and resolve similar issues in the future.

## Directory Structure

```
troubleshooting/
├── networking/      # Network-related issues
├── proxmox/         # Proxmox VE related issues
├── kubernetes/      # Kubernetes/K3s related issues
└── cicd/            # CI/CD pipeline related issues
```

## Document Index

### Networking

| Issue | Description | Difficulty |
|-------|-------------|------------|
| [PVE + K3s NodePort Compatibility](networking/pve-k3s-nodeport-compatibility.md) | PVE VMs cannot access K3s NodePort services | Intermediate |


| Issue | Description | Difficulty |
|-------|-------------|------------|
| - | - | - |

### Kubernetes

| Issue | Description | Difficulty |
|-------|-------------|------------|
| [ArgoCD Webhook Setup](kubernetes/argocd-webhook-setup.md) | Configure GitLab webhook to trigger ArgoCD auto-sync | Beginner |

### CI/CD

| Issue | Description | Difficulty |
|-------|-------------|------------|
| - | - | - |

## Contributing

If you encounter and resolve a new problem in your project, welcome to add it to this directory:

1. Choose the appropriate category directory (or create a new one)
2. Use the document template: `../template.md`
3. Add index in this README.md
4. Submit PR

### Document Requirements

- **Title**: Concise, including key technology and problem characteristics
- **Problem Description**: Clearly describe symptoms and environment
- **Root Cause**: Deep analysis of the root cause
- **Solution**: Detailed solution steps
- **Verification**: How to confirm the problem is resolved
- **Prevention**: Suggestions to avoid encountering it again

## Related Documentation

- [SOP: Template Development](../../SOP-Template-Development.md)
- [CD Documentation](../../cd/)
