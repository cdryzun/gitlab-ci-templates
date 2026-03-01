# Chapter 1: K3s Installation

## Overview

This chapter installs the K3s lightweight Kubernetes distribution on a single Debian 12 server.

**Validated environment**:
- OS: Debian GNU/Linux 12 (bookworm)
- K3s version: v1.34.4+k3s1
- Server IP: `<YOUR_NODE_IP>` (example: `10.16.110.17`)

## 1. Install K3s

### 1.1 Disable built-in components

This setup disables Traefik (using an external Ingress instead) and ServiceLB (to avoid port conflicts), and sets the node IP explicitly:

```bash
# Replace YOUR_NODE_IP with the actual server IP
NODE_IP="10.16.110.17"

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --node-ip "${NODE_IP}"
```

> **Why disable traefik and servicelb?**
> - K3s ships with Traefik Ingress and ServiceLB (klipper), which bind to ports 80/443
> - If the server already runs Nginx/Apache on those ports, disabling them prevents conflicts
> - ArgoCD is exposed via NodePort and does not need Ingress

### 1.2 Wait for the node to be Ready

```bash
sudo kubectl get nodes -w
# Wait until STATUS shows Ready
```

Expected output:

```
NAME     STATUS   ROLES           AGE   VERSION
5600x    Ready    control-plane   1m    v1.34.4+k3s1
```

## 2. Configure kubectl

K3s generates a kubeconfig at `/etc/rancher/k3s/k3s.yaml`. Set it up for the current user:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Replace the loopback address with the actual node IP
NODE_IP="10.16.110.17"
sed -i "s/127.0.0.1/${NODE_IP}/g" ~/.kube/config
```

Verify:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## 3. Verify core components

```bash
kubectl get pods -n kube-system
```

All pods should be Running:

```
NAME                                      READY   STATUS    RESTARTS
coredns-xxx                               1/1     Running   0
local-path-provisioner-xxx                1/1     Running   0
metrics-server-xxx                        1/1     Running   0
```

## 4. K3s service management

```bash
# Check status
sudo systemctl status k3s

# Restart
sudo systemctl restart k3s

# Enable on boot (configured automatically during install)
sudo systemctl enable k3s

# Uninstall (preserves data)
/usr/local/bin/k3s-uninstall.sh
```

## Next

[Chapter 2: ArgoCD Installation](./02-argocd-installation.md)
