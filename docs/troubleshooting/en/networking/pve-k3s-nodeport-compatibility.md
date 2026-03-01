# PVE + K3s NodePort Compatibility Issue

**Difficulty**: Intermediate
**Affected Versions**: K3s v1.34+, Proxmox VE 8.x
**Last Updated**: 2026-03-01

## Problem Description

### Symptoms

When running K3s cluster on Proxmox VE host, PVE virtual machines cannot access K3s NodePort services even with PVE firewall disabled.

- TCP connection timeout when accessing K3s NodePort (e.g., 30080) from PVE VM (e.g., GitLab VM)
- Other ports (SSH 22, PVE Web UI 8006) work normally
- Local access to NodePort from K3s host works fine
- Using `socat` to listen on the same NodePort still fails

### Environment

- **Host**: Proxmox VE 8.x
  - K3s running on PVE host (not in VM)
  - Host IP: 10.16.110.17/24 (vmbr0.1111)
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

- When trying to access K3s NodePort services running on PVE host from PVE VMs
- Ports in NodePort range (30000-32767) are affected
- Non-NodePort ports are not affected

## Root Cause Analysis

### Technical Background

K3s uses iptables-legacy PREROUTING DNAT rules to handle NodePort traffic:

```
PREROUTING (nat) -> KUBE-SERVICES -> KUBE-EXT-* -> DNAT to Pod IP
```

### The Problem

When packets arrive at vmbr0 from VM (tap106i0):

1. **Expected Path**:
   ```
   GitLab VM -> vmbr0 -> PREROUTING -> INPUT -> socat:30080
   ```

2. **Actual Path** (Problem):
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

1. **Packets reach iptables PREROUTING**: Confirmed packets enter iptables-legacy
2. **DNAT intercepts NodePort**: K3s PREROUTING rule rewrites dst:30080 to pod IP (10.42.0.11:8080)
3. **Packets never reach FORWARD chain**: DNAT'd packets disappear before FORWARD
4. **Root cause**: kube-router NetworkPolicy FORWARD rules drop packets from non-K3s networks by default

### Why socat on NodePort Failed

When socat listens on NodePort 30080:

1. K3s PREROUTING DNAT **intercepts** all traffic to port 30080 first
2. DNAT changes destination to pod IP, triggering routing decision to FORWARD (forward to pod)
3. socat listens on **INPUT** chain (local process), never receives DNAT'd packets
4. DNAT'd packets enter FORWARD chain and are dropped by kube-router NetworkPolicy

## Solution

### Prerequisites

- K3s running on PVE host
- PVE VM needs to access K3s service
- K3s service configured as NodePort type

### Step-by-Step Solution

#### Step 1: Create socat Proxy Service

Create systemd service listening on **non-NodePort port** (e.g., 9080), forwarding to K3s Service ClusterIP:

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

**Key Points**:
- Use **non-NodePort range port** (9080) to avoid K3s PREROUTING DNAT interception
- Forward to **ClusterIP** (10.43.114.154:80), let K3s OUTPUT DNAT handle forwarding to pod
- Connections from host go through OUTPUT chain (not FORWARD), won't be dropped by kube-router

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

Modify K8s Service to use `hostPort` instead of `nodePort`:

```yaml
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
    # Use hostPort to bind directly to host network
```

**Pros**: Bypasses K3s PREROUTING DNAT
**Cons**: Requires K8s config change, may affect other deployments

#### Option 2: Add iptables ACCEPT Rule

Add ACCEPT rule at beginning of FORWARD chain:

```bash
iptables-legacy -I FORWARD 1 -s 10.16.110.0/24 -d 10.42.0.0/16 -j ACCEPT
```

**Pros**: Keep NodePort unchanged
**Cons**: Bypasses NetworkPolicy security control, needs re-add after restart

#### Option 3: Change K3s CNI

Use different CNI (e.g., Flannel without NetworkPolicy):

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=vxlan" sh -
```

**Pros**: Completely avoids kube-router NetworkPolicy issues
**Cons**: Requires K3s redeployment, loses NetworkPolicy functionality

### Recommended Solution

**Use socat proxy (Step 1-6)**, reasons:

1. No K8s configuration changes
2. Doesn't bypass security controls
3. Clear port mapping, easy to maintain
4. Easy to debug

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

## Prevention

### 1. Document Network Architecture

Document clearly in project documentation:

- PVE host runs K3s
- K3s uses kube-router CNI with NetworkPolicy
- NodePort range: 30000-32767
- PVE VMs accessing K3s services need proxy ports

### 2. Use Non-NodePort Ports for External Access

Avoid NodePort range for external services (webhooks, APIs, etc.):

- Recommended port ranges: 8000-8999, 9000-9999
- Or use Ingress Controller (80/443)

### 3. Standardize Proxy Configuration

Create standardized proxy configuration template:

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

## References

1. [K3s Networking](https://docs.k3s.io/networking)
2. [kube-router NetworkPolicy](https://github.com/cloudnativelabs/kube-router/blob/master/docs/network-policies.md)
3. [iptables Packet Flow Diagram](https://commons.wikimedia.org/wiki/File:Netfilter-packet-flow.svg)
4. [Proxmox VE Firewall](https://pve.proxmox.com/wiki/Firewall)
