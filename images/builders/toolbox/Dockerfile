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

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    openssl \
    openssh-client \
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

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
