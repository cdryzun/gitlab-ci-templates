# Toolbox Image
# Utility image with common DevOps tools

FROM debian:bookworm-slim

LABEL maintainer="cdryzun"
LABEL description="Utility image with common DevOps tools"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Versions
ARG YQ_VERSION=4.40.5
ARG JQ_VERSION=1.7
ARG HELM_VERSION=3.14.0
ARG KUBECTL_VERSION=1.29.2
ARG DOCKER_VERSION=24.0.7
ARG GLAB_VERSION=1.37.0
ARG ARGOCD_VERSION=2.10.0

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
RUN curl -fsSL https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64 \
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
    | tar -xzC /tmp && \
    mv /tmp/bin/glab /usr/local/bin/glab && \
    rm -rf /tmp/bin

# Install ArgoCD CLI
RUN curl -fsSL https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64 \
    -o /usr/local/bin/argocd && \
    chmod +x /usr/local/bin/argocd

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
