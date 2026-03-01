# ArgoCD Webhook Setup Guide

**Difficulty**: Beginner
**Affected Versions**: ArgoCD 2.x, GitLab 15+
**Last Updated**: 2026-03-01

## Problem Description

### Symptoms

ArgoCD applications don't automatically sync after Git repository updates, requiring manual `argocd app sync` triggers.

- After git push, ArgoCD application status shows `OutOfSync`
- Must run sync command manually
- CI/CD workflow cannot achieve full automation

### Environment

- **ArgoCD**: v2.x running on K3s
- **GitLab**: CE/EE v15+
- **Network**: GitLab cannot directly access K3s API (or requires authentication)

### When It Happens

- ArgoCD webhook not configured
- GitLab and K3s network isolation
- GitOps automation workflow needed

## Solution

### Prerequisites

- ArgoCD installed and running
- GitLab project created
- Network connectivity: GitLab can access ArgoCD webhook endpoint

### Step 1: Get ArgoCD Webhook URL

#### Option A: NodePort (Direct Access)

```bash
# Get ArgoCD Service NodePort
kubectl get svc -n argocd argocd-server -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}'
# Output: 30080

# Webhook URL
WEBHOOK_URL="http://<K3S_HOST_IP>:30080/api/webhook"
```

#### Option B: socat Proxy (Recommended for PVE)

If encountering [PVE + K3s compatibility issue](../networking/pve-k3s-nodeport-compatibility.md), use socat proxy:

```bash
# Webhook URL (using socat proxy port)
WEBHOOK_URL="http://<K3S_HOST_IP>:9080/api/webhook"
```

#### Option C: Ingress (Production)

```bash
# Webhook URL via Ingress
WEBHOOK_URL="https://argocd.example.com/api/webhook"
```

### Step 2: Configure GitLab Webhook

#### Via GitLab UI

1. Navigate to GitLab project: **Settings** → **Webhooks**
2. Fill in webhook configuration:
   - **URL**: `http://10.16.110.17:9080/api/webhook`
   - **Secret Token**: (leave empty or generate one)
   - **Trigger**: Select `Push events`, `Tag push events`
   - **SSL verification**: Disable if using HTTP

3. Click **Add webhook**

#### Via GitLab CLI (glab)

```bash
# Create webhook
glab api --hostname gitlab.example.com --method POST \
  "projects/gitops%2Fgo-hello/hooks" \
  --field url="http://10.16.110.17:9080/api/webhook" \
  --field push_events=true \
  --field tag_push_events=true \
  --field enable_ssl_verification=false

# Output
{
  "id": 188,
  "url": "http://10.16.110.17:9080/api/webhook",
  "push_events": true
}
```

### Step 3: Test Webhook

#### Manual Test via GitLab UI

1. Navigate to **Settings** → **Webhooks**
2. Find the created webhook
3. Click **Test** → **Push events**
4. Verify response: `HTTP 200`

#### Test via Git Push

```bash
# Clone GitOps repository
git clone https://gitlab.example.com/gitops/go-hello.git
cd go-hello

# Make a change
echo "# Webhook test $(date +%s)" >> README.md
git add README.md
git commit -m "test: webhook trigger"
git push origin dev

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server --tail=20 | grep webhook

# Expected output
time="2026-03-01T15:04:45Z" level=info msg="refreshing app 'go-hello-dev' from webhook"
```

### Step 4: Verify ArgoCD Sync

```bash
# Check application status
kubectl get app -n argocd go-hello-dev -o wide

# Expected output
NAME          SYNC STATUS   HEALTH STATUS   REVISION                                   PROJECT
go-hello-dev  Synced        Healthy         ad0a2b81f3e9cdca4b50cef143f9f36530b47082   default

# Check sync history
argocd app history go-hello-dev

# Expected output
ID  DATE                           REVISION                             ORIGIN
1   2026-03-01 23:04:45 +0800 CST  ad0a2b81f3e9cdca4b50cef143f9f36530b47082  Webhook
```

## Configuration Details

### Webhook URL Format

ArgoCD webhook endpoint format:

```
http(s)://<argocd-host>/api/webhook
```

**Important**:
- No need to add `/applications/{app-name}` suffix
- ArgoCD automatically matches applications by Git repository URL
- Supports triggering multiple applications simultaneously

### GitLab Webhook Events

Recommended trigger events:

| Event | When to Trigger | Use Case |
|-------|----------------|----------|
| **Push events** | Branch push | Dev environment auto-deploy |
| **Tag push events** | Tag creation | Production release |
| **Merge request events** | MR create/merge | Staging environment |
| **Releases events** | Release creation | Production release |

### Secret Token (Optional)

Add secret token verification for webhook:

1. **Generate Token**:
   ```bash
   openssl rand -hex 32
   # Output: a1b2c3d4e5f6...
   ```

2. **Configure in GitLab**:
   ```bash
   glab api --method POST "projects/gitops%2Fgo-hello/hooks" \
     --field url="http://10.16.110.17:9080/api/webhook" \
     --field token="a1b2c3d4e5f6..."
   ```

3. **Configure in ArgoCD** (optional):
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: argocd-webhook-secret
     namespace: argocd
   stringData:
     webhook.github.secret: a1b2c3d4e5f6...
   ```

## Troubleshooting

### Webhook Returns 404

**Cause**: ArgoCD server not configured correctly or wrong URL

**Solution**:
```bash
# Verify ArgoCD service is running
kubectl get svc -n argocd argocd-server

# Test webhook endpoint manually
curl -X POST http://10.16.110.17:9080/api/webhook
# Expected: 200 OK (empty response is normal)
```

### Webhook Returns 401/403

**Cause**: Secret token mismatch or IP whitelist restriction

**Solution**:
```bash
# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server | grep -i "webhook\|401\|403"

# Verify token in GitLab webhook settings
glab api "projects/gitops%2Fgo-hello/hooks" | jq '.[] | {id, url}'
```

### ArgoCD Not Refreshing After Webhook

**Cause**: Git repository URL mismatch or application not configured

**Solution**:
```bash
# Check application repo URL
kubectl get app -n argocd go-hello-dev -o jsonpath='{.spec.source.repoURL}'

# Verify GitLab webhook payload
# Navigate to GitLab → Settings → Webhooks → Recent Deliveries
# Check "Request body" contains correct repository URL
```

### Connection Timeout from GitLab

**Cause**: Network unreachable or port blocked

**Solution**:
```bash
# Test TCP connectivity from GitLab VM
timeout 3 bash -c 'echo > /dev/tcp/10.16.110.17/9080' && echo "OK" || echo "FAIL"

# If FAIL, check:
# 1. Firewall rules (PVE, iptables, cloud provider)
# 2. Network routing
# 3. socat service status
```

## Advanced Configuration

### Multiple Applications

ArgoCD webhook automatically triggers all applications matching Git repository URL:

```yaml
# App 1: go-hello-dev
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: go-hello-dev
  namespace: argocd
spec:
  source:
    repoURL: https://gitlab.example.com/gitops/go-hello.git
    targetRevision: dev
# ...

---
# App 2: go-hello-prd
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: go-hello-prd
  namespace: argocd
spec:
  source:
    repoURL: https://gitlab.example.com/gitops/go-hello.git
    targetRevision: prd
# ...
```

Push to `dev` branch triggers `go-hello-dev` app, push to `prd` branch triggers `go-hello-prd` app.

### Filter by Branch

Use **Push events** filter in GitLab webhook:

1. **Navigate to** Webhook settings
2. **Filter branches**: `dev`, `sit`, `prd`
3. Only pushes to these branches trigger webhook

### Webhook with ArgoCD Notifications

Combine with ArgoCD Notifications Controller for bidirectional notifications:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: NotificationsConfiguration
metadata:
  name: default-notifications-cm
spec:
  triggers:
    - name: on-sync-succeeded
      condition: app.status.operationState.phase in ['Succeeded']
      template: app-sync-succeeded

  templates:
    - name: app-sync-succeeded
      slack:
        attachments: |
          [{
            "title": "{{.app.metadata.name}}",
            "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
            "color": "#18be52",
            "fields": [
              {
                "title": "Sync Status",
                "value": "{{.app.status.sync.status}}",
                "short": true
              }
            ]
          }]
```

## Best Practices

### 1. Use Dedicated Webhook Port

Configure dedicated proxy port for webhook:

```bash
# socat for webhook only
socat TCP-LISTEN:9080,fork,reuseaddr TCP:10.43.114.154:80
```

**Benefits**:
- Avoids NodePort conflicts
- Easy to monitor and debug
- Security isolation

### 2. Enable SSL/TLS

Use HTTPS in production:

```bash
# Using Ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-webhook
  namespace: argocd
spec:
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-tls
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /api/webhook
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

### 3. Monitor Webhook Health

Create health check script:

```bash
#!/bin/bash
# /usr/local/bin/check-argocd-webhook.sh

WEBHOOK_URL="http://10.16.110.17:9080/healthz"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 $WEBHOOK_URL)

if [ "$RESPONSE" != "200" ]; then
  echo "ArgoCD webhook unhealthy: HTTP $RESPONSE"
  exit 1
fi

echo "ArgoCD webhook healthy"
exit 0
```

### 4. Log Webhook Events

Enable verbose logging in ArgoCD:

```bash
# Update ArgoCD server deployment
kubectl patch deployment -n argocd argocd-server --type=json \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--loglevel=debug"}]'
```

## Verification Checklist

- [ ] ArgoCD service is running (`kubectl get svc -n argocd`)
- [ ] Webhook URL is accessible (`curl http://<host>:9080/healthz`)
- [ ] GitLab webhook created (`glab api projects/.../hooks`)
- [ ] Manual test successful (GitLab UI → Test → Push events)
- [ ] Git push triggers refresh (`git push && kubectl logs ...`)
- [ ] Application syncs automatically (`kubectl get app ...`)

## Related Issues

- [PVE + K3s NodePort Compatibility](../networking/pve-k3s-nodeport-compatibility.md)
- [ArgoCD GitOps Integration](../../../cd/en/04-argocd-gitops-integration.md)

## References

1. [ArgoCD Webhook Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/)
2. [GitLab Webhook Documentation](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html)
3. [ArgoCD Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
