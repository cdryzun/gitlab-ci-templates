# Troubleshooting Guide

本目录收集了在实际项目中遇到的各种问题及其解决方案，帮助后续遇到类似问题时快速定位和解决。

## 目录结构

```
troubleshooting/
├── networking/      # 网络相关问题
├── proxmox/         # Proxmox VE 相关问题
├── kubernetes/      # Kubernetes/K3s 相关问题
└── cicd/            # CI/CD 流水线相关问题
```

## 文档索引

### Networking

| 问题 | 描述 | 难度 |
|------|------|------|
| [PVE + K3s NodePort 兼容性](networking/pve-k3s-nodeport-compatibility.md) | PVE 虚拟机无法访问 K3s NodePort 服务 | 中级 |

### Proxmox

| 问题 | 描述 | 难度 |
|------|------|------|
| - | - | - |

### Kubernetes

| 问题 | 描述 | 难度 |
|------|------|------|
| [ArgoCD Webhook 配置](kubernetes/argocd-webhook-setup.md) | 配置 GitLab webhook 触发 ArgoCD 自动同步 | 初级 |
| [ArgoCD 自动同步失败](kubernetes/argocd-sync-issues.md) | ArgoCD 应用无法自动同步的常见原因 | 中级 |

### CI/CD

| 问题 | 描述 | 难度 |
|------|------|------|
| - | - | - |

## 贡献指南

如果您在项目中遇到了新的问题并已解决，欢迎补充到本目录：

1. 选择合适的分类目录（或创建新分类）
2. 使用文档模板：`template.md`
3. 在本 README.md 中添加索引
4. 提交 PR

### 文档要求

- **标题**：简明扼要，包含关键技术和问题特征
- **问题描述**：清晰说明现象和环境
- **根本原因**：深入分析问题根因
- **解决方案**：详细的解决步骤
- **验证方法**：如何确认问题已解决
- **预防措施**：避免再次遇到的建议

## 相关文档

- [SOP: Template Development](../SOP-Template-Development.md)
- [CD Documentation](../cd/)
