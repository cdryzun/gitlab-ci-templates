# Chapter 2: ArgoCD Installation

## Overview

This chapter installs ArgoCD via Helm and exposes it through NodePort with HTTP access (suitable for internal networks and development environments).

**Validated environment**:
- Helm version: v3.20.0
- ArgoCD Chart version: 9.4.5
- ArgoCD version: v3.3.2

## 1. Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify:

```bash
helm version --short
# Output: v3.20.0+...
```

## 2. Add the ArgoCD Helm repository

```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
```

Check available versions:

```bash
helm search repo argo-cd/argo-cd --versions | head -5
```

## 3. Create the ArgoCD values file

Create `/tmp/argocd-values.yaml`:

```yaml
global:
  domain: argocd.local

server:
  service:
    type: NodePort
    nodePortHttp: 30080
    nodePortHttps: 30443

  # Disable internal TLS; access via NodePort HTTP (internal/dev environment)
  extraArgs:
    - --insecure

configs:
  params:
    server.insecure: true
```

> **About --insecure mode**
> Production deployments should enable TLS. This configuration is intended for internal networks and development/testing environments.

## 4. Install ArgoCD

```bash
kubectl create namespace argocd

helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --values /tmp/argocd-values.yaml \
  --wait
```

Wait for all pods to be ready (approximately 2–3 minutes):

```bash
kubectl get pods -n argocd -w
```

Expected output — all pods Running/Ready:

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

## 5. Retrieve the initial admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

## 6. Verify access

```bash
NODE_IP="10.16.110.17"
curl -s http://${NODE_IP}:30080/healthz
# Output: ok
```

Open `http://<NODE_IP>:30080` in a browser.

Username: `admin`, Password: retrieved in the previous step.

## 7. Install the ArgoCD CLI

```bash
ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | grep tag_name | cut -d'"' -f4)

curl -sSL -o /tmp/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"

sudo install -m 755 /tmp/argocd /usr/local/bin/argocd
argocd version --client
```

## 8. Log in with the CLI

```bash
NODE_IP="10.16.110.17"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

argocd login ${NODE_IP}:30080 \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --plaintext   # Required for HTTP mode; do NOT use --insecure here
```

## 9. Special configuration for Proxmox VE hosts

**Background**: When K3s runs on a PVE hypervisor and GitLab runs as a PVE VM, the ArgoCD `repo-server` pod cannot reach the GitLab VM by default. This is caused by PVE bridge network isolation (hairpin routing issue) — pods masquerade as the host IP but the bridge does not forward host-originated traffic back to VMs.

**Solution**: Enable `hostNetwork` on `repo-server` so it shares the host's network stack:

```bash
kubectl patch deployment argocd-repo-server -n argocd --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true},
  {"op": "add", "path": "/spec/template/spec/dnsPolicy", "value": "ClusterFirstWithHostNet"}
]'
```

Verify the pod uses the host IP:

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o wide
# The IP column should show the host IP (e.g. 10.16.110.17)
```

> **Note**: In hostNetwork mode the repo-server uses the host's network stack and has the same network access as the hypervisor — it can reach PVE VMs directly.

## Next

[Chapter 3: GitOps Repository Setup](./03-gitops-repo-setup.md)
