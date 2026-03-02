# PVE + K3s NodePort Compatibility Issue

**Difficulty**: Intermediate
**Affected Versions**: K3s v1.34+, Proxmox VE 8.x
**Last Updated**: 2026-03-01

## Problem Description

### Symptoms

在 Proxmox VE 上运行 K3s 集群时，PVE 虚拟机无法访问 K3s NodePort 服务，即使 PVE 防火墙已关闭。

- 从 PVE 虚拟机（如 GitLab VM）访问 K3s NodePort 端口（如 30080）时，TCP 连接超时
- 其他端口（如 SSH 22、PVE Web UI 8006）访问正常
- 从 K3s 主机本地访问 NodePort 正常
- 使用 `socat` 监听相同 NodePort 端口仍然失败

### Environment

- **Host**: Proxmox VE 8.x
  - K3s 运行在 PVE 主机上（非虚拟机）
  - 主机 IP: 10.16.110.17/24 (vmbr0.1111)
  - Bridge: vmbr0 with VLAN 1111

- **VM**: GitLab VM (VMID=106)
  - IP: 10.16.110.119/24
  - Network: vmbr0, VLAN tag=1111
  - Tap interface: tap106i0

- **K3s**: v1.34.4+k3s1
  - Network: kube-router CNI
  - Pod CIDR: 10.42.0.0/16
  - Service CIDR: 10.43.0.0/16
  - ArgoCD Service: NodePort 30080 -> Pod 10.42.0.11:8080

### When It Happens

- 尝试从 PVE 虚拟机访问运行在 PVE 主机上的 K3s NodePort 服务时
- NodePort 范围内的端口（30000-32767）会出现此问题
- 非 NodePort 端口不受影响

## Root Cause Analysis

### Technical Background

K3s 使用 iptables-legacy 的 PREROUTING DNAT 规则来处理 NodePort 流量：

```
PREROUTING (nat) -> KUBE-SERVICES -> KUBE-EXT-* -> DNAT to Pod IP
```

### The Problem

当数据包从虚拟机（tap106i0）到达 vmbr0 时：

1. **正常路径**（期望）：
   ```
   GitLab VM -> vmbr0 -> PREROUTING -> INPUT -> socat:30080
   ```

2. **实际路径**（问题）：
   ```
   GitLab VM -> vmbr0 -> PREROUTING -> DNAT to Pod IP -> FORWARD -> DROP
   ```

### Investigation Steps

#### 1. Verify PVE Firewall is Disabled

```bash
# Check firewall services
systemctl is-active pve-firewall proxmox-firewall
# Output: active / active (but no rules loaded)

# Check nftables rules
nft list ruleset | wc -l
# Output: 0 (firewall effectively disabled)
```

#### 2. Test Connectivity

```bash
# From GitLab VM
curl http://10.16.110.17:30080/healthz
# Result: Connection timeout

# Test other ports
curl http://10.16.110.17:8006  # PVE Web UI
# Result: OK

curl http://10.16.110.17:22    # SSH
# Result: OK
```

#### 3. Add iptables LOG Rules

```bash
# Add LOG to raw PREROUTING
iptables-legacy -t raw -I PREROUTING 1 -s 10.16.110.119 -p tcp --dport 30080 -j LOG --log-prefix "RAW-GIT30: "

# Add LOG to nat PREROUTING
iptables-legacy -t nat -I PREROUTING 1 -s 10.16.110.119 -p tcp --dport 30080 -j LOG --log-prefix "PRERT-GIT30: "

# Add LOG to FORWARD
iptables-legacy -I FORWARD 1 -s 10.16.110.119 -p tcp -j LOG --log-prefix "FWD-GIT-SRC: "
```

#### 4. Analyze Packet Flow

```bash
# Trigger test connection
qm guest exec 106 -- bash -c "timeout 3 bash -c 'echo > /dev/tcp/10.16.110.17/30080'"

# Check kernel log
dmesg | grep "RAW-GIT30"
# Output: IN=vmbr0 PHYSIN=tap106i0 SRC=10.16.110.119 DST=10.16.110.17 DPT=30080
# Packet reaches raw PREROUTING ✓

dmesg | grep "PRERT-GIT30"
# Output: (same packet)
# Packet reaches nat PREROUTING ✓

dmesg | grep "FWD-GIT"
# Output: (no packets!)
# Packet NOT reaching FORWARD chain ✗
```

### Key Findings

1. **Packets reach iptables PREROUTING**: 确认数据包进入 iptables-legacy
2. **DNAT intercepts NodePort**: K3s PREROUTING 规则将 dst:30080 改写为 pod IP (10.42.0.11:8080)
3. **Packets never reach FORWARD chain**: DNAT 后的包在 FORWARD 链前消失
4. **Root cause**: kube-router NetworkPolicy 的 FORWARD 规则在处理外部流量时，默认丢弃来自非 K3s 网络的包

### Why socat on NodePort Failed

当 socat 监听 NodePort 30080 时：

1. K3s PREROUTING DNAT **优先**拦截目标端口 30080 的所有流量
2. DNAT 将目的地改写为 pod IP，触发路由决策为 FORWARD（转发到 pod）
3. socat 监听的是 **INPUT** 链（本地进程），永远收不到被 DNAT 劫持的包
4. 被 DNAT 的包进入 FORWARD 链，被 kube-router 的 NetworkPolicy 丢弃

## Solution

### Prerequisites

- K3s 运行在 PVE 主机上
- 需要 PVE 虚拟机访问 K3s 服务
- K3s 服务配置为 NodePort 类型

### Step-by-Step Solution

#### Step 1: Create socat Proxy Service

创建 systemd 服务，监听**非 NodePort 端口**（如 9080），转发到 K3s Service ClusterIP：

```bash
sudo bash -c 'cat > /etc/systemd/system/socat-argocd-proxy.service << EOF
[Unit]
Description=TCP proxy for ArgoCD (9080 -> ClusterIP 10.43.114.154:80)
After=network.target k3s.service
Wants=k3s.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:9080,fork,reuseaddr TCP:10.43.114.154:80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF'
```

**关键点**：
- 使用**非 NodePort 范围端口**（9080），避免被 K3s PREROUTING DNAT 拦截
- 转发到 **ClusterIP**（10.43.114.154:80），让 K3s 的 OUTPUT DNAT 处理转发到 pod
- 从 host 发起的连接通过 OUTPUT 链（非 FORWARD），不会被 kube-router 丢弃

#### Step 2: Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable socat-argocd-proxy
sudo systemctl start socat-argocd-proxy
sudo systemctl status socat-argocd-proxy
```

#### Step 3: Verify Local Access

```bash
# From K3s host
curl -I http://localhost:9080/healthz
# Expected: HTTP/1.1 200 OK
```

#### Step 4: Verify VM Access

```bash
# From PVE VM
curl -I http://10.16.110.17:9080/healthz
# Expected: HTTP/1.1 200 OK
```

#### Step 5: Update GitLab Webhook

```bash
# Update webhook URL to use port 9080
glab api --hostname gitlab.example.com --method PUT \
  "projects/gitops%2Fgo-hello/hooks/188" \
  --field url="http://10.16.110.17:9080/api/webhook"
```

#### Step 6: Test Webhook Trigger

```bash
# Make a change in gitops repo
cd /tmp && git clone https://gitlab.example.com/gitops/go-hello.git
cd go-hello
echo "# Webhook test $(date +%s)" >> README.md
git commit -am "test: webhook trigger"
git push origin dev

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server | grep webhook
# Expected: refreshing app 'go-hello-dev' from webhook
```

### Alternative Solutions

#### Option 1: Use HostPort Instead of NodePort

修改 K8s Service，使用 `hostPort` 而非 `nodePort`：

```yaml
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
    # Use hostPort to bind directly to host network
```

**Pros**: 绕过 K3s PREROUTING DNAT
**Cons**: 需要修改 K8s 配置，可能影响其他部署

#### Option 2: Add iptables ACCEPT Rule

在 FORWARD 链开头添加 ACCEPT 规则：

```bash
iptables-legacy -I FORWARD 1 -s 10.16.110.0/24 -d 10.42.0.0/16 -j ACCEPT
```

**Pros**: 保持 NodePort 不变
**Cons**: 绕过 NetworkPolicy 安全控制，每次重启需重新添加

#### Option 3: Change K3s CNI

使用其他 CNI（如 Flannel without NetworkPolicy）：

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=vxlan" sh -
```

**Pros**: 完全避免 kube-router NetworkPolicy 问题
**Cons**: 需要重新部署 K3s，失去 NetworkPolicy 功能

### Recommended Solution

**使用 socat 代理（Step 1-6）**，理由：

1. 不修改 K8s 配置
2. 不绕过安全控制
3. 端口映射清晰可控
4. 易于维护和调试

## Verification

### 1. TCP Connectivity Test

```bash
# From GitLab VM
timeout 3 bash -c 'echo > /dev/tcp/10.16.110.17/9080' && echo "SUCCESS" || echo "FAIL"
# Expected: SUCCESS
```

### 2. HTTP Request Test

```bash
curl -s -o /dev/null -w '%{http_code}' http://10.16.110.17:9080/healthz
# Expected: 200
```

### 3. Webhook Trigger Test

```bash
# Trigger webhook
git push origin dev

# Check ArgoCD application status
kubectl get app -n argocd go-hello-dev -o jsonpath='{.status.sync.status}'
# Expected: Synced
```

### 4. Check Packet Flow (Optional)

```bash
# Add LOG to INPUT chain
iptables-legacy -I INPUT 1 -p tcp --dport 9080 -j LOG --log-prefix "INPUT-9080: "

# Test connection
curl http://10.16.110.17:9080/healthz

# Check log
dmesg | grep "INPUT-9080"
# Expected: IN=vmbr0.1111 ... DPT=9080
```

## Prevention

### 1. Document Network Architecture

在项目文档中明确记录：

- PVE 主机运行 K3s
- K3s 使用 kube-router CNI with NetworkPolicy
- NodePort 范围：30000-32767
- PVE 虚拟机访问 K3s 服务需使用代理端口

### 2. Use Non-NodePort Ports for External Access

对外服务（webhook、API 等）避免使用 NodePort 范围：

- 推荐端口范围：8000-8999, 9000-9999
- 或使用 Ingress Controller (80/443)

### 3. Standardize Proxy Configuration

创建标准化的代理配置模板：

```bash
# /etc/systemd/system/socat-template.service
[Unit]
Description=TCP proxy for [SERVICE_NAME] ([HOST_PORT] -> [CLUSTER_IP]:[PORT])
After=network.target k3s.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:[HOST_PORT],fork,reuseaddr TCP:[CLUSTER_IP]:[PORT]
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 4. Monitor Network Policies

定期检查 kube-router NetworkPolicy 规则：

```bash
kubectl get networkpolicy --all-namespaces
iptables-legacy -L KUBE-ROUTER-FORWARD -n -v
```

## Related Issues

- [ArgoCD Webhook Setup](../kubernetes/argocd-webhook-setup.md)
- [PVE Firewall Configuration](https://pve.proxmox.com/wiki/Firewall)

## Technical Deep Dive

### iptables Packet Flow

```
Incoming Packet (DST:30080)
    ↓
raw PREROUTING → LOG (packet seen)
    ↓
nat PREROUTING → KUBE-SERVICES → DNAT (DST changed to 10.42.0.11:8080)
    ↓
Routing Decision → FORWARD (dest is remote pod)
    ↓
FORWARD chain → KUBE-ROUTER-FORWARD → NetworkPolicy DROP
    ↓
Packet lost ✗
```

```
Incoming Packet (DST:9080) [SOLUTION]
    ↓
raw PREROUTING → (no DNAT for 9080)
    ↓
nat PREROUTING → (no DNAT for 9080)
    ↓
Routing Decision → INPUT (dest is local process)
    ↓
INPUT chain → socat receives packet
    ↓
socat → connects to ClusterIP (10.43.114.154:80)
    ↓
nat OUTPUT → KUBE-SERVICES → DNAT (DST changed to 10.42.0.11:8080)
    ↓
Routing Decision → OUTPUT (source is local)
    ↓
POSTROUTING → masquerade
    ↓
Packet delivered to pod ✓
```

### Why ClusterIP Works

从 host 连接 ClusterIP 时：

1. 流量从 **OUTPUT** 链发出（本地进程）
2. K3s 在 nat OUTPUT 中有 DNAT 规则
3. 不经过 FORWARD 链
4. kube-router NetworkPolicy 不影响 OUTPUT 链

## References

1. [K3s Networking](https://docs.k3s.io/networking)
2. [kube-router NetworkPolicy](https://github.com/cloudnativelabs/kube-router/blob/master/docs/network-policies.md)
3. [iptables Packet Flow Diagram](https://commons.wikimedia.org/wiki/File:Netfilter-packet-flow.svg)
4. [Proxmox VE Firewall](https://pve.proxmox.com/wiki/Firewall)
