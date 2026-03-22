# 构建镜像

所有镜像托管在 GitHub Container Registry，工具链预装完毕，CI 运行时无需额外下载。

## Builder 镜像

| 镜像 | 版本 | 内置工具 |
|------|------|---------|
| `ghcr.io/cdryzun/glci-builder-java` | `jdk8` `jdk11` `jdk17` `jdk21` | Maven, Gradle, SonarScanner |
| `ghcr.io/cdryzun/glci-builder-nodejs` | `20` `22` `24` | pnpm, yarn, npm |
| `ghcr.io/cdryzun/glci-builder-python` | `3.11` `3.12` `3.13` | pip, poetry |
| `ghcr.io/cdryzun/glci-builder-golang` | `1.22` `1.23` `1.24` | Go 工具链, golangci-lint |
| `ghcr.io/cdryzun/glci-builder-golang-nodejs` | `go1.23-node20` 等 | Go + Node.js |
| `ghcr.io/cdryzun/glci-toolbox` | `latest` | docker, helm, glab, yq, argocd, kubectl |

## Toolbox 工具版本

| 工具 | 版本 |
|------|------|
| Helm | 3.20.1 |
| kubectl | 1.35.3 |
| Docker CLI | 27.5.1 |
| glab (GitLab CLI) | 1.89.0 |
| ArgoCD CLI | 2.14.21 |
| yq | 4.52.4 |
| jq | 1.7.1 |

## 使用加速代理

在国内环境，通过 `IMAGE_MIRROR_PREFIX` 变量加速镜像拉取：

```yaml
variables:
  IMAGE_MIRROR_PREFIX: "your-proxy.example.com/"
```

配置后 `ghcr.io/cdryzun/glci-builder-java:jdk17` 变为 `your-proxy.example.com/ghcr.io/cdryzun/glci-builder-java:jdk17`。

## 自定义 Builder 镜像

覆盖默认镜像：

```yaml
variables:
  MAVEN_IMAGE: "your-registry.example.com/custom-java:jdk17"
  NODE_IMAGE: "your-registry.example.com/custom-node:20"
  BASE_BUILD_IMAGE: "your-registry.example.com/custom-builder:latest"
```

`BASE_BUILD_IMAGE` 覆盖所有项目类型的默认构建镜像。
