# Chapter 3: GitOps Repository Setup

## Overview

This chapter creates a GitOps repository on GitLab to store Helm Charts. ArgoCD reads this repository to deploy and manage the application.

**Core GitOps principle**: The desired state of the application (Helm values, image tag) is stored in Git. ArgoCD continuously reconciles the cluster's actual state with Git.

> **Repository mode note**: This chapter demonstrates the **single-application dedicated repository** model (each application has its own GitOps repository). If you need to **manage multiple projects in a single repository**, see [Chapter 6: Multi-Project GitOps Repository Design](./06-multi-project-gitops.md).

## 1. Repository structure

Recommended GitOps repository layout:

```
gitops/go-hello.git          # GitOps repo (separate from the application code repo)
└── go-hello/                # Application Helm Chart
    ├── Chart.yaml           # Chart metadata
    ├── values.yaml          # Default configuration (base values)
    ├── values-dev.yaml      # DEV environment overrides
    ├── values-sit.yaml      # SIT environment overrides
    ├── values-prd.yaml      # PRD environment overrides
    └── templates/           # Kubernetes resource templates
        ├── deployment.yaml
        └── service.yaml
```

**Branch strategy**:

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

| Branch | Environment | Notes |
|--------|-------------|-------|
| `dev` | DEV | Development; updated automatically by CI |
| `sit` | SIT | Staging; updated automatically by CI |
| `prd` | PRD | Production; merged via MR after approval |

## 2. Create the repository in GitLab

Create via the GitLab UI or the API:

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

## 3. Initialize repository contents

### 3.1 Clone and initialize

```bash
GITOPS_REPO="https://gitlab.example.com/gitops/go-hello.git"
GITLAB_TOKEN="<YOUR_GITLAB_TOKEN>"

git clone "https://oauth2:${GITLAB_TOKEN}@gitlab.example.com/gitops/go-hello.git" /tmp/gitops-go-hello
cd /tmp/gitops-go-hello
git checkout -b dev
```

### 3.2 Create Chart.yaml

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

### 3.3 Create values.yaml (default configuration)

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

### 3.4 Create per-environment override files

```bash
# DEV
cat > go-hello/values-dev.yaml << 'EOF'
replicaCount: 1
image:
  tag: "latest"
env: dev
EOF

# SIT
cat > go-hello/values-sit.yaml << 'EOF'
replicaCount: 1
image:
  tag: "latest"
env: sit
EOF

# PRD
cat > go-hello/values-prd.yaml << 'EOF'
replicaCount: 2
image:
  tag: "latest"
env: prd
EOF
```

### 3.5 Create the Deployment template

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

### 3.6 Create the Service template

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

### 3.7 Commit and push

```bash
git add .
git commit -m "feat: initialize go-hello helm chart"

# Push the dev branch (used by ArgoCD for the DEV environment)
git push origin dev

# Create the prd branch (used by ArgoCD for the PRD environment; CI pushes to this branch)
git checkout -b prd
git push origin prd
```

## 4. How CI updates the image tag

After a CI pipeline builds and pushes an image, it updates the GitOps repository with the new tag:

```bash
# Run inside the CI job (requires yq)
NEW_TAG="${CI_COMMIT_SHA::8}"   # Short commit SHA as tag
VALUES_FILE="go-hello/values-dev.yaml"

yq -i ".image.tag = \"${NEW_TAG}\"" "${VALUES_FILE}"

git add "${VALUES_FILE}"
git commit -m "ci: update image tag to ${NEW_TAG}"
git push origin dev
```

ArgoCD detects the Git change and auto-syncs (default polling interval: 3 minutes; use a Webhook for immediate sync).

## Next

[Chapter 4: ArgoCD GitOps Integration](./04-argocd-gitops-integration.md)
