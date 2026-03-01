# 第五章：GitLab CI/CD 集成

## 说明

本章说明如何通过 gitlab-ci-templates 的 Auto-DevOps 模板，在 CI 流水线完成镜像构建后，自动更新 GitOps 仓库并触发 ArgoCD 部署。

## 完整 CD 流程

```
应用代码仓库 (go-hello)
    |
    | git push → CI 流水线触发
    v
.pre 阶段 → build 阶段 → deploy 阶段
    |              |              |
    | 环境检测   | 镜像构建&推送 | 更新 GitOps 仓库
    |              |              | (更新 values.yaml image.tag)
    v              v              |
                           git push → dev 分支
                                  |
                                  v
                           ArgoCD 检测变更
                                  |
                                  | argocd app sync
                                  v
                           K8s 部署新版本
```

## 1. CI 变量配置

在 GitLab 项目 Settings → CI/CD → Variables 中配置以下变量：

| 变量 | 示例值 | 说明 |
|------|--------|------|
| `DEPLOY_REPO` | `https://gitlab.example.com/gitops/go-hello.git` | GitOps 仓库地址 |
| `GITLAB_REPO_COMMIT_TOKEN` | `glpat-xxxx` | 有 write 权限的 Token |
| `DEPLOY_REPO_YAML_TAG` | `.image.tag` | yq 路径，指向 values.yaml 中的 tag 字段 |
| `DEPLOY_VALUE_FILE` | `values-dev.yaml` | 要更新的 values 文件 |
| `DEPLOY_REPO_PROJ` | `go-hello` | GitOps 仓库中的 Chart 目录名 |
| `ARGOCD_SERVER` | `10.16.110.17:30080` | ArgoCD 地址（可选，用于同步） |
| `ARGOCD_AUTH_TOKEN` | `xxxx` | ArgoCD API Token（可选） |

## 2. 在应用仓库配置 .gitlab-ci.yml

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/cdryzun/gitlab-ci-templates/open/templates/Auto-DevOps.gitlab-ci.yml'

variables:
  # 构建配置
  BUILD_SHELL: "go mod tidy && go build -o ${CI_PROJECT_NAME} ./..."

  # 启用 Docker 镜像构建
  FEAT_DOCKER_IMAGE_BUILD: "true"

  # 启用单元测试
  UNIT_TEST_ENABLE: "true"

  # CD 配置
  DEPLOY_REPO: "https://gitlab.example.com/gitops/go-hello.git"
  DEPLOY_REPO_YAML_TAG: ".image.tag"
  DEPLOY_VALUE_FILE: "values-dev.yaml"
  DEPLOY_REPO_PROJ: "go-hello"

  # 环境自动部署开关
  DEV_CD_AUTO_DEPLOY: "true"
  SIT_CD_AUTO_DEPLOY: "true"
  PRD_CD_AUTO_DEPLOY: "true"  # PRD 环境自动提 MR，不直接推送
```

## 3. 分支与环境映射

Auto-DevOps 模板自动根据当前分支决定部署到哪个环境：

| 推送分支 | 目标 GitOps 分支 | 部署环境 |
|---------|----------------|---------|
| `feat-*` / `feature-*` | `dev` | DEV |
| `sit` | `sit` | SIT |
| `v*.*.*` (release tag) | `prd` | PRD（创建 MR，需审批） |
| `prd` | `prd` | PRD（创建 MR，需审批） |

## 4. PRD 环境保护机制

对于 PRD 环境，CD 脚本会：
1. 在 GitOps 仓库创建一个新分支（如 `ci/update-tag-v1.2.3`）
2. 提交 image.tag 变更
3. 自动创建 Merge Request 到 `prd` 分支
4. 等待人工审批后 ArgoCD 才会同步

```bash
# PRD 环境 MR 通知 (在 CI 日志中输出)
MR URL: https://gitlab.example.com/gitops/go-hello/-/merge_requests/123
```

## 5. ArgoCD 同步配置（可选）

如果配置了 `ARGOCD_SERVER` 和 `ARGOCD_AUTH_TOKEN`，CI 在更新 GitOps 仓库后会主动触发 ArgoCD 同步：

```yaml
# utils/deploy.stable.gitlab-ci.yml 中的同步逻辑
argocd app sync "${APP_NAME}" --server "${ARGOCD_SERVER}" --auth-token "${ARGOCD_AUTH_TOKEN}"
argocd app wait "${APP_NAME}" --health --timeout 300
```

应用名称格式：`{DEPLOY_REPO_PROJ}-{DEPLOY_REPO_NAME}-{REMOTE_BRANCH}`

例如：`go-hello-go-hello-dev`

## 6. 验证 CD 流程

### 6.1 确认镜像被推送到 Registry

```bash
# 查看 GitLab 项目镜像列表
curl -sk -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/registry/repositories"
```

### 6.2 确认 GitOps 仓库被更新

```bash
cd /tmp/gitops-go-hello
git fetch origin dev
git log origin/dev --oneline -5
# 应看到 "ci: update image tag to xxxx" 的提交
```

### 6.3 确认 ArgoCD 同步

```bash
argocd app get go-hello-dev --server "${NODE_IP}:30080"
# Sync Status: Synced to dev (xxxx)
# Health Status: Healthy
```

### 6.4 确认 K8s 中的 Pod 使用新镜像

```bash
kubectl get pods -n go-hello-dev
kubectl describe pod -n go-hello-dev <pod-name> | grep Image:
```

## 7. 回滚操作

CI 流水线提供了手动回滚 Job：

```bash
# 在 GitLab Pipeline 页面点击 "rollback" Job 手动触发
# 或通过 CLI 触发
```

回滚原理：
1. 从 CI artifacts 读取上次部署的旧 image.tag
2. 使用 sed 将 values.yaml 中的 tag 替换回旧值
3. 提交 GitOps 仓库
4. ArgoCD 自动同步回滚

## 关键变量参考

完整变量说明参见 `vars/default-vars.stable.gitlab-ci.yml` 中的 `.cd_vars` 部分。
