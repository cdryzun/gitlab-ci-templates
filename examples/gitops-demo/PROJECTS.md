# 项目关联总表

## GitHub 开源项目

| 项目名称 | 描述 | 链接 |
|---------|------|------|
| **gitlab-ci-templates** | CI/CD 模板 + 完整文档 | [GitHub](https://github.com/cdryzun/gitlab-ci-templates) |
| **gitops-go-hello** | GitOps Helm charts | [GitHub](https://github.com/cdryzun/gitops-go-hello) |
| **go-hello** | Go 应用源码 | [GitHub](https://github.com/cdryzun/go-hello) |

## GitLab 私有项目

| 项目名称 | 描述 | 链接 |
|---------|------|------|
| **go-hello** | Go 应用源码（原始仓库） | [GitLab](https://gitlab.treesir.pub/sre/devops/go-hello) |
| **gitops/go-hello** | GitOps Helm charts（原始仓库） | [GitLab](https://gitlab.treesir.pub/gitops/go-hello) |

## 项目关系图

```
┌──────────────────────────────────────────────────────────────────┐
│                        GitHub 开源项目                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                                             │
│  │ go-hello        │  Go HTTP service + GitLab CI               │
│  │ (应用源码)       │  https://github.com/cdryzun/go-hello       │
│  └────────┬────────┘                                             │
│           │                                                      │
│           │ 使用模板                                             │
│           ▼                                                      │
│  ┌─────────────────┐                                             │
│  │ gitlab-ci-      │  CI/CD 模板 + 文档                          │
│  │ templates       │  https://github.com/cdryzun/               │
│  │                 │    gitlab-ci-templates                      │
│  └─────────────────┘                                             │
│           ▲                                                      │
│           │ 更新                                                 │
│           │                                                      │
│  ┌────────┴────────┐                                             │
│  │ gitops-go-hello │  GitOps Helm charts                        │
│  │ (Helm charts)   │  https://github.com/cdryzun/               │
│  │                 │    gitops-go-hello                          │
│  └─────────────────┘                                             │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## CI/CD 完整流程

```
1. 代码开发
   └─> git push origin feat-test (GitLab go-hello)

2. GitLab CI Pipeline 自动触发
   └─> include: gitlab-ci-templates (Auto-DevOps)

3. Pipeline 执行阶段
   ├─> pre: 环境准备
   ├─> build: 构建 Docker 镜像
   ├─> unit_test: 运行单元测试
   └─> cd-deploy: 更新 GitOps 仓库

4. GitOps 仓库更新
   └─> 更新 gitops-go-hello values.yaml

5. Webhook 触发
   └─> ArgoCD 检测到变更

6. ArgoCD 同步
   └─> 部署到 K3s 集群
```

## 文档资源

### Troubleshooting

- [PVE + K3s NodePort 兼容性](../../docs/troubleshooting/networking/pve-k3s-nodeport-compatibility.md)
  - 解决 PVE 虚拟机无法访问 K3s NodePort 的问题
  - socat 代理方案详解

- [ArgoCD Webhook 配置](../../docs/troubleshooting/kubernetes/argocd-webhook-setup.md)
  - GitLab webhook 集成指南
  - 自动触发 ArgoCD 同步

### CD Documentation

- [CD Overview](../../docs/cd/00-overview.md)
- [K3s Installation](../../docs/cd/01-k3s-installation.md)
- [ArgoCD Installation](../../docs/cd/02-argocd-installation.md)
- [GitOps Setup](../../docs/cd/03-gitops-repo-setup.md)
- [ArgoCD Integration](../../docs/cd/04-argocd-gitops-integration.md)
- [CI/CD Integration](../../docs/cd/05-cicd-integration.md)

## 快速开始

### 1. 使用 CI/CD 模板

在你的项目中添加 `.gitlab-ci.yml`:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  BUILD_SHELL: "go build -o app ./..."
```

### 2. 部署到 Kubernetes

```bash
# 使用 Helm 部署
helm install go-hello-dev \
  https://github.com/cdryzun/gitops-go-hello.git \
  -f https://raw.githubusercontent.com/cdryzun/gitops-go-hello/main/dev/values.yaml
```

### 3. 配置 ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: go-hello-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/cdryzun/gitops-go-hello.git
    targetRevision: main
    path: go-hello
    helm:
      valueFiles:
        - values-dev.yaml
        - ../../dev/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: go-hello-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## 许可证

所有开源项目均使用 MIT 许可证。
