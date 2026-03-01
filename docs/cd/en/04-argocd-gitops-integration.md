# Chapter 4: ArgoCD GitOps Integration

## Overview

This chapter registers the GitLab GitOps repository with ArgoCD and creates an ArgoCD Application that automatically deploys the application.

## 1. Register the GitLab repository

### 1.1 Prepare a GitLab Access Token

Create a Personal Access Token in GitLab with at least `read_repository` scope:

GitLab → User Settings → Access Tokens → Create token (enable `read_repository`)

### 1.2 Register the repository

```bash
NODE_IP="10.16.110.17"
GITLAB_URL="https://gitlab.example.com"
GITLAB_TOKEN="<YOUR_GITLAB_TOKEN>"

argocd repo add "${GITLAB_URL}/gitops/go-hello.git" \
  --username oauth2 \
  --password "${GITLAB_TOKEN}" \
  --plaintext \
  --server "${NODE_IP}:30080"
```

Verify:

```bash
argocd repo list --server "${NODE_IP}:30080"
```

Expected output:

```
TYPE  NAME  REPO                                              INSECURE  STATUS      MESSAGE
git         https://gitlab.example.com/gitops/go-hello.git  false     Successful
```

## 2. Create an ArgoCD Application

### 2.1 DEV environment

```bash
NODE_IP="10.16.110.17"

kubectl create namespace go-hello-dev

argocd app create go-hello-dev \
  --repo https://gitlab.example.com/gitops/go-hello.git \
  --path go-hello \
  --revision dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace go-hello-dev \
  --values values-dev.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --server "${NODE_IP}:30080"
```

Parameter reference:

| Flag | Description |
|------|-------------|
| `--revision dev` | Track the `dev` branch |
| `--path go-hello` | Chart path inside the repository |
| `--values values-dev.yaml` | Overlay DEV-specific values |
| `--sync-policy automated` | Auto-sync when Git changes are detected |
| `--auto-prune` | Automatically delete resources removed from Git |
| `--self-heal` | Revert manual cluster changes back to the Git state |

### 2.2 Check Application status

```bash
argocd app get go-hello-dev --server "${NODE_IP}:30080"
```

Expected output (synced and healthy):

```
Name:               argocd/go-hello-dev
Sync Status:        Synced to dev (abc1234)
Health Status:      Healthy

GROUP  KIND        NAMESPACE     NAME          STATUS  HEALTH
       Service     go-hello-dev  go-hello-dev  Synced  Healthy
apps   Deployment  go-hello-dev  go-hello-dev  Synced  Healthy
```

### 2.3 Verify Kubernetes resources

```bash
kubectl get pods,svc -n go-hello-dev
```

## 3. Trigger a manual sync

```bash
# Sync immediately without waiting for the polling interval
argocd app sync go-hello-dev --server "${NODE_IP}:30080"
```

## 4. Special handling for Proxmox VE hosts

**Problem**: K3s pod networks (10.42.0.0/16) cannot reach PVE VM IPs (e.g. GitLab VM at 10.16.110.119). The PVE Linux bridge (vmbr0) does not forward masqueraded packets from the hypervisor host back to VMs (hairpin routing issue).

**Symptom**:

```
argocd repo add ...
# Error: rpc error: ... context deadline exceeded
```

**Root cause**:
- Pods in 10.42.0.x send packets that are MASQUERADE'd to the host IP (e.g. 10.16.110.17)
- The PVE bridge does not forward those packets to co-located VMs
- As a result, both GitLab VMs and public internet destinations are unreachable from pods, while the host's own services (e.g. NodePort) remain accessible

**Solution: enable hostNetwork on repo-server**

```bash
kubectl patch deployment argocd-repo-server -n argocd --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true},
  {"op": "add", "path": "/spec/template/spec/dnsPolicy", "value": "ClusterFirstWithHostNet"}
]'
```

Wait for the rollout to complete:

```bash
kubectl rollout status deployment/argocd-repo-server -n argocd
```

Verify the pod is using the host IP:

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o wide
# The IP column should show the host IP (e.g. 10.16.110.17)
```

With hostNetwork enabled, repo-server has direct access to PVE VMs without going through the pod network. Only `application-controller` makes cluster API calls and does not need this change.

## 5. Configure GitLab Webhooks (optional — for instant sync)

By default ArgoCD polls Git every 3 minutes. A Webhook triggers an immediate sync on every push.

Add a Webhook in the GitLab project settings:

- URL: `http://<NODE_IP>:30080/api/webhook`
- Trigger: Push events
- Secret Token: (optional, configure in ArgoCD if used)

## Next

[Chapter 5: GitLab CI/CD Integration](./05-cicd-integration.md)
