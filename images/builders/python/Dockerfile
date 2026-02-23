# Python Builder Image
# For Python builds with pip, poetry, virtualenv

ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}-bookworm

LABEL maintainer="cdryzun"
LABEL description="Python builder image with pip, poetry and virtualenv"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Environment
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    ca-certificates \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install poetry
RUN curl -sSL https://install.python-poetry.org | python3 - && \
    ln -s /root/.local/bin/poetry /usr/local/bin/poetry

# Set working directory
WORKDIR /build

# Default command
CMD ["python", "--version"]
