# 第二章：ArgoCD 安装

## 说明

本章通过 Helm 安装 ArgoCD，并配置 NodePort 对外暴露，允许通过 HTTP 访问（适合内网/开发环境）。

**验证环境**：
- Helm 版本：v3.20.0
- ArgoCD Chart 版本：9.4.5
- ArgoCD 版本：v3.3.2

## 1. 安装 Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

验证：

```bash
helm version --short
# 输出: v3.20.0+...
```

## 2. 添加 ArgoCD Helm 仓库

```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
```

查看可用版本：

```bash
helm search repo argo-cd/argo-cd --versions | head -5
```

## 3. 创建 ArgoCD 配置文件

创建 `/tmp/argocd-values.yaml`：

```yaml
global:
  domain: argocd.local

server:
  service:
    type: NodePort
    nodePortHttp: 30080
    nodePortHttps: 30443

  # 禁用内部 TLS，通过 NodePort HTTP 访问（内网开发环境）
  extraArgs:
    - --insecure

configs:
  params:
    server.insecure: true
```

> **关于 --insecure 模式**
> 生产环境应启用 TLS。本配置适用于内网或开发测试环境。

## 4. 安装 ArgoCD

```bash
kubectl create namespace argocd

helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --values /tmp/argocd-values.yaml \
  --wait
```

等待所有 Pod 就绪（约 2-3 分钟）：

```bash
kubectl get pods -n argocd -w
```

预期所有 Pod 为 Running/Ready：

```
NAME                                               READY   STATUS
argocd-application-controller-0                    1/1     Running
argocd-applicationset-controller-xxx               1/1     Running
argocd-dex-server-xxx                              1/1     Running
argocd-notifications-controller-xxx                1/1     Running
argocd-redis-xxx                                   1/1     Running
argocd-repo-server-xxx                             1/1     Running
argocd-server-xxx                                  1/1     Running
```

## 5. 获取初始管理员密码

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

## 6. 验证访问

```bash
NODE_IP="10.16.110.17"
curl -s http://${NODE_IP}:30080/healthz
# 输出: ok
```

浏览器访问：`http://<NODE_IP>:30080`

用户名：`admin`，密码：上一步获取的初始密码

## 7. 安装 ArgoCD CLI

```bash
ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | grep tag_name | cut -d'"' -f4)

curl -sSL -o /tmp/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"

sudo install -m 755 /tmp/argocd /usr/local/bin/argocd
argocd version --client
```

## 8. CLI 登录

```bash
NODE_IP="10.16.110.17"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

argocd login ${NODE_IP}:30080 \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --plaintext   # HTTP 模式需要此标志，不需要 --insecure
```

## 9. 在 Proxmox VE 宿主机上的特殊配置

**问题背景**：若 K3s 部署在 PVE 宿主机，而 GitLab 运行在 PVE 虚拟机，ArgoCD 的 `repo-server` Pod 默认无法访问 PVE VM（PVE bridge 网络隔离）。

**解决方案**：将 `repo-server` 配置为 hostNetwork 模式：

```bash
kubectl patch deployment argocd-repo-server -n argocd --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true},
  {"op": "add", "path": "/spec/template/spec/dnsPolicy", "value": "ClusterFirstWithHostNet"}
]'
```

验证：

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o wide
# repo-server Pod 的 IP 应为宿主机 IP (如 10.16.110.17)
```

> **注意**：hostNetwork 模式下 repo-server 使用宿主机网络栈，具有与宿主机相同的网络访问权限，可直接访问 PVE VM。

## 下一步

[第三章：GitOps 仓库设置](./03-gitops-repo-setup.md)
