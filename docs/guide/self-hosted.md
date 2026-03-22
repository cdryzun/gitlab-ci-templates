# 私有化部署

## 为什么需要私有化

默认模板通过 `include: remote:` 从 GitHub 拉取，在以下场景可能不适用：

- 国内网络访问 GitHub 不稳定
- 内网隔离环境无法访问外网
- 需要对模板做定制修改

## 方案：GitLab 仓库镜像

### 第一步：创建镜像仓库

在你的 GitLab 实例上创建一个项目，从 GitHub 导入：

```bash
# 通过 GitLab API 创建镜像
curl -X POST "https://your-gitlab.example.com/api/v4/projects" \
  -H "PRIVATE-TOKEN: YOUR_TOKEN" \
  -d "name=gitlab-ci-templates" \
  -d "namespace_id=YOUR_GROUP_ID" \
  -d "import_url=https://github.com/cdryzun/gitlab-ci-templates.git" \
  -d "mirror=true" \
  -d "visibility=public"
```

!!! warning "可见性设置"
    仓库必须设为 `public` 或 `internal`，否则脚本下载时需要额外的认证配置。

### 第二步：配置下游项目

```yaml
include:
  - project: 'your-group/gitlab-ci-templates'
    ref: open
    file:
      - 'vars/default-vars.stable.gitlab-ci.yml'
      - 'vars/multiarch-vars.stable.gitlab-ci.yml'
      - 'vars/vault.stable.gitlab-ci.yml'
      - 'utils/rules.stable.gitlab-ci.yml'
      - 'utils/before.stable.gitlab-ci.yml'
      - 'utils/after.stable.gitlab-ci.yml'
      - 'utils/build.stable.gitlab-ci.yml'
      - 'utils/deploy.stable.gitlab-ci.yml'
      - 'utils/scan.stable.gitlab-ci.yml'
      - 'utils/test.stable.gitlab-ci.yml'
      - 'utils/manage.stable.gitlab-ci.yml'
      - 'jobs-templates/PreJob.stable.gitlab-ci.yml'
      - 'jobs-templates/SonarQube.stable.gitlab-ci.yml'
      - 'jobs-templates/Test.stable.gitlab-ci.yml'
      - 'jobs-templates/Build.stable.gitlab-ci.yml'
      - 'jobs-templates/Trivy-Container-Scanning.stable.gitlab-ci.yml'
      - 'jobs-templates/Gitlab-Container-Scanning.stable.gitlab-ci.yml'
      - 'jobs-templates/Deploy.stable.gitlab-ci.yml'
      - 'jobs-templates/Rollback.stable.gitlab-ci.yml'

variables:
  extends: .default_vars
  TEMPLATE_CONTEXT: 'stable'
  # 你的项目变量...

cache:
  paths:
    - ${CACHE_DIR}

stages:
  !reference [ .general_stage, stages ]

workflow:
  rules:
    !reference [ .trigger_rule, rules ]
```

### 第三步：配置脚本下载地址

在 GitLab Group CI/CD Variables 中设置：

```
TEMPLATE_REPO_RAW_URL = https://your-gitlab.example.com/your-group/gitlab-ci-templates/-/raw/open
```

### 第四步：配置加速（可选）

```
IMAGE_MIRROR_PREFIX = your-proxy.example.com/
DOCKER_MIRROR_PREFIX = your-proxy.example.com/
MAVEN_REGISTRY = https://maven.aliyun.com/repository/public
NODE_REGISTRY = https://registry.npmmirror.com
PYPI = https://pypi.tuna.tsinghua.edu.cn/simple
```
