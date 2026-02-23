# Nginx Runtime Image
# For serving static files (frontend applications)

ARG NGINX_VERSION=1.24
FROM nginx:${NGINX_VERSION}-alpine

LABEL maintainer="cdryzun"
LABEL description="Nginx runtime for static files"
LABEL org.opencontainers.image.source="https://github.com/cdryzun/gitlab-ci-templates"

# Install additional tools
RUN apk add --no-cache \
    curl \
    tzdata

# Set timezone
ENV TZ=Asia/Shanghai

# Create directories
RUN mkdir -p /opt/deployments/dist && \
    chown -R nginx:nginx /opt/deployments

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --start-period=5s --interval=30s --timeout=3s --retries=3 \
    CMD curl -fs http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
