# ArgoCD Webhook Setup Guide

**Difficulty**: Beginner
**Affected Versions**: ArgoCD 2.x, GitLab 15+
**Last Updated**: 2026-03-01

## Problem Description

### Symptoms

ArgoCD 应用无法在 Git 仓库更新后自动同步，需要手动触发 `argocd app sync`。

- Git 推送后，ArgoCD 应用状态显示 `OutOfSync`
- 必须手动运行同步命令
- CI/CD 流程无法实现全自动闭环

### Environment

- **ArgoCD**: v2.x running on K3s
- **GitLab**: CE/EE v15+
- **Network**: GitLab 无法直接访问 K3s API（或需要认证）

### When It Happens

- ArgoCD 未配置 webhook
- GitLab 与 K3s 网络隔离
- 需要实现 GitOps 自动化流程

## Solution

### Prerequisites

- ArgoCD 已安装并运行
- GitLab 项目已创建
- 网络连通性：GitLab 可访问 ArgoCD webhook endpoint

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

如果遇到 [PVE + K3s 兼容性问题](../networking/pve-k3s-nodeport-compatibility.md)，使用 socat 代理：

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

ArgoCD webhook endpoint 格式：

```
http(s)://<argocd-host>/api/webhook
```

**重要**：
- 无需添加 `/applications/{app-name}` 后缀
- ArgoCD 自动根据 Git 仓库 URL 匹配应用
- 支持同时触发多个应用

### GitLab Webhook Events

推荐启用的触发事件：

| Event | When to Trigger | Use Case |
|-------|----------------|----------|
| **Push events** | 分支推送 | 开发环境自动部署 |
| **Tag push events** | 标签创建 | 生产环境发布 |
| **Merge request events** | MR 创建/合并 | 预发布环境 |
| **Releases events** | Release 创建 | 生产环境发布 |

### Secret Token (Optional)

为 webhook 添加密钥验证：

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

**Cause**: ArgoCD server 未正确配置或 URL 错误

**Solution**:
```bash
# Verify ArgoCD service is running
kubectl get svc -n argocd argocd-server

# Test webhook endpoint manually
curl -X POST http://10.16.110.17:9080/api/webhook
# Expected: 200 OK (empty response is normal)
```

### Webhook Returns 401/403

**Cause**: Secret token 不匹配或 IP 白名单限制

**Solution**:
```bash
# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server | grep -i "webhook\|401\|403"

# Verify token in GitLab webhook settings
glab api "projects/gitops%2Fgo-hello/hooks" | jq '.[] | {id, url}'
```

### ArgoCD Not Refreshing After Webhook

**Cause**: Git 仓库 URL 不匹配或应用未配置

**Solution**:
```bash
# Check application repo URL
kubectl get app -n argocd go-hello-dev -o jsonpath='{.spec.source.repoURL}'

# Verify GitLab webhook payload
# Navigate to GitLab → Settings → Webhooks → Recent Deliveries
# Check "Request body" contains correct repository URL
```

### Connection Timeout from GitLab

**Cause**: 网络不通或端口被阻止

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

ArgoCD webhook 自动触发所有匹配 Git 仓库 URL 的应用：

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

推送到 `dev` 分支会触发 `go-hello-dev` 应用，推送到 `prd` 分支会触发 `go-hello-prd` 应用。

### Filter by Branch

在 GitLab webhook 中使用 **Push events** 过滤：

1. **Navigate to** Webhook settings
2. **Filter branches**: `dev`, `sit`, `prd`
3. Only pushes to these branches trigger webhook

### Webhook with ArgoCD Notifications

结合 ArgoCD Notifications Controller 实现双向通知：

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

为 webhook 配置独立的代理端口：

```bash
# socat for webhook only
socat TCP-LISTEN:9080,fork,reuseaddr TCP:10.43.114.154:80
```

**Benefits**:
- 避免与 NodePort 冲突
- 便于监控和调试
- 安全隔离

### 2. Enable SSL/TLS

生产环境使用 HTTPS：

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

创建健康检查脚本：

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

在 ArgoCD 中启用详细日志：

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
- [ArgoCD GitOps Integration](../../cd/04-argocd-gitops-integration.md)

## References

1. [ArgoCD Webhook Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/)
2. [GitLab Webhook Documentation](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html)
3. [ArgoCD Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
