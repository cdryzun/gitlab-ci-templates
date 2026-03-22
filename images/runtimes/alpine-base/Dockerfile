# Alpine Base Runtime Image
# Minimal base for various applications

FROM alpine:3.22

LABEL maintainer="cdryzun"
LABEL description="Minimal Alpine base runtime"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Install common tools
RUN apk add --no-cache \
    curl \
    wget \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=Asia/Shanghai

# Create app directory
RUN mkdir -p /app

WORKDIR /app

CMD ["sh"]
