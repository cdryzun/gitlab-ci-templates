# 第一章：K3s 安装

## 说明

本章在单台 Debian 12 服务器上安装轻量级 Kubernetes 发行版 K3s。

**验证环境**：
- 系统：Debian GNU/Linux 12 (bookworm)
- K3s 版本：v1.34.4+k3s1
- 服务器 IP：`<YOUR_NODE_IP>`（示例中为 `10.16.110.17`）

## 1. 安装 K3s

### 1.1 禁用内置组件安装

本环境禁用 Traefik（使用外部 Ingress）和 ServiceLB（避免端口冲突），并配置节点 IP：

```bash
# 替换 YOUR_NODE_IP 为服务器实际 IP
NODE_IP="10.16.110.17"

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --node-ip "${NODE_IP}"
```

> **为什么禁用 traefik 和 servicelb？**
> - K3s 默认安装 Traefik Ingress 和 ServiceLB (klipper)，会占用 80/443 端口
> - 如果服务器已有 Nginx/Apache 等服务占用这些端口，需要禁用
> - ArgoCD 通过 NodePort 对外暴露，不依赖 Ingress

### 1.2 等待节点就绪

```bash
sudo kubectl get nodes -w
# 等待 STATUS 变为 Ready
```

预期输出：

```
NAME     STATUS   ROLES           AGE   VERSION
5600x    Ready    control-plane   1m    v1.34.4+k3s1
```

## 2. 配置 kubectl

K3s 自动生成 kubeconfig，默认路径为 `/etc/rancher/k3s/k3s.yaml`：

```bash
# 配置 kubectl 默认 kubeconfig（可选，K3s 已自动配置）
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 将 kubeconfig server 地址替换为真实 IP（默认为 127.0.0.1）
NODE_IP="10.16.110.17"
sed -i "s/127.0.0.1/${NODE_IP}/g" ~/.kube/config
```

验证：

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## 3. 验证核心组件

```bash
kubectl get pods -n kube-system
```

预期所有 Pod 为 Running 状态：

```
NAME                                      READY   STATUS    RESTARTS
coredns-xxx                               1/1     Running   0
local-path-provisioner-xxx                1/1     Running   0
metrics-server-xxx                        1/1     Running   0
```

## 4. K3s 服务管理

```bash
# 查看状态
sudo systemctl status k3s

# 重启
sudo systemctl restart k3s

# 开机自启（安装时已自动配置）
sudo systemctl enable k3s

# 卸载（保留数据）
/usr/local/bin/k3s-uninstall.sh
```

## 下一步

[第二章：ArgoCD 安装](./02-argocd-installation.md)
