# 第三章：GitOps 仓库设置

## 说明

本章在 GitLab 创建 GitOps 仓库（存储 Helm Charts），用于 ArgoCD 读取并部署应用。

**GitOps 核心原则**：应用的期望状态（Helm values、镜像 tag）存储在 Git 仓库，ArgoCD 持续确保集群实际状态与 Git 一致。

> **仓库模式说明**：本章展示**单应用独立仓库**模式（每个应用拥有独立的 GitOps 仓库）。如果需要在**单个仓库中管理多个项目**，参见[第六章：多项目 GitOps 仓库设计](./06-multi-project-gitops.md)。

## 1. 仓库结构设计

推荐的 GitOps 仓库结构：

```
gitops/go-hello.git          # GitOps 仓库（独立于应用代码仓库）
└── go-hello/                # 应用 Helm Chart
    ├── Chart.yaml           # Chart 基础信息
    ├── values.yaml          # 默认配置（base values）
    ├── values-dev.yaml      # DEV 环境差异配置
    ├── values-sit.yaml      # SIT 环境差异配置
    ├── values-prd.yaml      # PRD 环境差异配置
    └── templates/           # K8s 资源模板
        ├── deployment.yaml
        └── service.yaml
```

**分支策略**：

```mermaid
gitGraph
   commit id: "init chart"
   branch dev
   checkout dev
   commit id: "ci: tag a1b2c3d"
   commit id: "ci: tag e4f5a6b"
   branch sit
   checkout sit
   commit id: "ci: tag e4f5a6b (sit)"
   checkout prd
   merge sit id: "release v1.0.0 (MR approved)" tag: "v1.0.0"
```

| 分支 | 环境 | 说明 |
|------|------|------|
| `dev` | DEV | 开发环境，CI 自动更新 |
| `sit` | SIT | 测试环境，CI 自动更新 |
| `prd` | PRD | 生产环境，MR 审批后合并 |

## 2. 在 GitLab 创建仓库

通过 GitLab UI 创建仓库，或使用 API：

```bash
GITLAB_TOKEN="<YOUR_GITLAB_TOKEN>"
GITLAB_URL="https://gitlab.example.com"

curl -sk -X POST "${GITLAB_URL}/api/v4/projects" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "go-hello",
    "namespace_id": <YOUR_NAMESPACE_ID>,
    "visibility": "private",
    "initialize_with_readme": false
  }'
```

## 3. 初始化仓库内容

### 3.1 克隆并初始化

```bash
GITOPS_REPO="https://gitlab.example.com/gitops/go-hello.git"
GITLAB_TOKEN="<YOUR_GITLAB_TOKEN>"

git clone "https://oauth2:${GITLAB_TOKEN}@gitlab.example.com/gitops/go-hello.git" /tmp/gitops-go-hello
cd /tmp/gitops-go-hello
git checkout -b dev  # 创建 dev 分支
```

### 3.2 创建 Chart.yaml

```bash
mkdir -p go-hello/templates

cat > go-hello/Chart.yaml << 'EOF'
apiVersion: v2
name: go-hello
description: Helm chart for go-hello service
type: application
version: 0.1.0
appVersion: "latest"
EOF
```

### 3.3 创建 values.yaml（默认配置）

```bash
cat > go-hello/values.yaml << 'EOF'
replicaCount: 1

image:
  repository: registry.gitlab.example.com/your-group/go-hello
  pullPolicy: IfNotPresent
  tag: "latest"

service:
  type: ClusterIP
  port: 2025

resources:
  requests:
    cpu: 100m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 256Mi

env: dev
EOF
```

### 3.4 创建环境差异配置

```bash
# DEV 环境
cat > go-hello/values-dev.yaml << 'EOF'
replicaCount: 1
image:
  tag: "latest"
env: dev
EOF

# SIT 环境
cat > go-hello/values-sit.yaml << 'EOF'
replicaCount: 1
image:
  tag: "latest"
env: sit
EOF

# PRD 环境
cat > go-hello/values-prd.yaml << 'EOF'
replicaCount: 2
image:
  tag: "latest"
env: prd
EOF
```

### 3.5 创建 Deployment 模板

```bash
cat > go-hello/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Release.Name }}
    version: {{ .Values.image.tag | quote }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
        version: {{ .Values.image.tag | quote }}
    spec:
      containers:
        - name: {{ .Release.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.port }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
EOF
```

### 3.6 创建 Service 模板

```bash
cat > go-hello/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
  selector:
    app: {{ .Release.Name }}
EOF
```

### 3.7 提交并推送

```bash
git add .
git commit -m "feat: initialize go-hello helm chart"

# 推送 dev 分支（ArgoCD DEV 环境使用此分支）
git push origin dev

# 创建 prd 分支（ArgoCD PRD 环境使用此分支，CI 会推送到此分支）
git checkout -b prd
git push origin prd
```

## 4. CI 更新镜像 Tag 的方式

当 CI 流水线完成镜像构建后，通过以下方式更新 GitOps 仓库中的镜像 tag：

```bash
# CI 中执行（需要 yq 工具）
NEW_TAG="${CI_COMMIT_SHA::8}"  # 使用短 commit SHA 作为 tag
VALUES_FILE="go-hello/values-dev.yaml"

# 更新 image.tag
yq -i ".image.tag = \"${NEW_TAG}\"" "${VALUES_FILE}"

git add "${VALUES_FILE}"
git commit -m "ci: update image tag to ${NEW_TAG}"
git push origin dev
```

ArgoCD 检测到 Git 变更后，自动触发同步（默认 3 分钟检测周期，或通过 Webhook 即时触发）。

## 下一步

[第四章：ArgoCD 接入 GitOps 仓库](./04-argocd-gitops-integration.md)
