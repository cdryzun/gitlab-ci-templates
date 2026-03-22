# Toolbox Image
# Utility image with common DevOps tools

FROM debian:bookworm-slim

LABEL maintainer="cdryzun"
LABEL description="Utility image with common DevOps tools"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Versions - pinned to latest stable releases
ARG YQ_VERSION=4.52.4
ARG JQ_VERSION=1.7.1
ARG HELM_VERSION=3.20.1
ARG KUBECTL_VERSION=1.35.3
ARG DOCKER_VERSION=27.5.1
ARG GLAB_VERSION=1.89.0
ARG ARGOCD_VERSION=2.14.21

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    openssl \
    openssh-client \
    tar \
    && rm -rf /var/lib/apt/lists/*

# Install yq
RUN curl -fsSL https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64 \
    -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Install jq
RUN curl -fsSL https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64 \
    -o /usr/local/bin/jq && \
    chmod +x /usr/local/bin/jq

# Install helm
RUN curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    | tar -xzC /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/linux-amd64

# Install kubectl
RUN curl -fsSL https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz \
    | tar -xzC /tmp && \
    mv /tmp/docker/docker /usr/local/bin/docker && \
    rm -rf /tmp/docker

# Install glab (GitLab CLI)
RUN curl -fsSL https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz \
    -o /tmp/glab.tar.gz && \
    tar -xzf /tmp/glab.tar.gz -C /tmp && \
    mv /tmp/bin/glab /usr/local/bin/glab && \
    rm -rf /tmp/bin /tmp/glab.tar.gz

# Install ArgoCD CLI
RUN curl -fsSL https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64 \
    -o /usr/local/bin/argocd && \
    chmod +x /usr/local/bin/argocd

WORKDIR /workspace
CMD ["bash"]
