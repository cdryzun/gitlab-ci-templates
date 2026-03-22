# 国内加速配置

## 镜像拉取加速

| 变量 | 作用 | 推荐值 |
|------|------|--------|
| `IMAGE_MIRROR_PREFIX` | 加速 Builder 镜像拉取（ghcr.io） | `your-proxy/` |
| `DOCKER_MIRROR_PREFIX` | 加速 Dockerfile 基础镜像拉取 | `your-proxy/` |

## 依赖源加速

| 变量 | 作用 | 推荐值 |
|------|------|--------|
| `MAVEN_REGISTRY` | Maven 仓库 | `https://maven.aliyun.com/repository/public` |
| `NODE_REGISTRY` | npm 包 | `https://registry.npmmirror.com` |
| `PYPI` | pip 包 | `https://pypi.tuna.tsinghua.edu.cn/simple` |
| `GO_GOPROXY` | Go 模块 | `https://goproxy.cn,direct` |

## 配置方式

建议在 GitLab **Group** 级别统一配置，所有子项目自动继承：

**Settings > CI/CD > Variables**

```
IMAGE_MIRROR_PREFIX = your-proxy.example.com/
DOCKER_MIRROR_PREFIX = your-proxy.example.com/
MAVEN_REGISTRY = https://maven.aliyun.com/repository/public
NODE_REGISTRY = https://registry.npmmirror.com
PYPI = https://pypi.tuna.tsinghua.edu.cn/simple
GO_GOPROXY = https://goproxy.cn,direct
```

## 模板引用加速

将模板仓库镜像到内网 GitLab 后，配置：

```
TEMPLATE_REPO_RAW_URL = https://your-gitlab/group/gitlab-ci-templates/-/raw/open
```

详见 [私有化部署指南](../guide/self-hosted.md)。
