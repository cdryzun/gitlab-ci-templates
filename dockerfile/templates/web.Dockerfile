# Web Frontend Dockerfile Template
# 基于 Nginx 的前端静态资源容器镜像

ARG DOCKER_MIRROR_PREFIX=""
ARG NGINX_VERSION=1.24-alpine
FROM ${DOCKER_MIRROR_PREFIX}nginx:${NGINX_VERSION} as web

# Build arguments for metadata
ARG CI_COMMIT_SHORT_SHA="develop"
ARG CI_BUILD_DATE=""
ARG APP_NAME="app"
ARG CI_COMMIT_REF_NAME=""
ARG CI_COMMIT_AUTHOR=""
ARG CI_PROJECT_NAME=""

# Add metadata labels
LABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR} \
      CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA} \
      CI_BUILD_DATE=${CI_BUILD_DATE} \
      CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME} \
      CI_PROJECT_NAME=${CI_PROJECT_NAME} \
      maintainer="DevOps Team"

# Set environment variables
ENV APP=${APP_NAME}

# Add static files
# Note: The build process should generate files in the 'dist' directory
ADD dist /opt/deployments/dist

# Set proper ownership and create symlink for nginx
RUN chown -R nginx:nginx /opt/deployments/dist && \
    if [ ! -e /usr/share/nginx/html ]; then \
        mkdir -p /usr/share/nginx && \
        ln -sv /opt/deployments/dist /usr/share/nginx/html; \
    else \
        rm -rf /usr/share/nginx/html && \
        ln -sv /opt/deployments/dist /usr/share/nginx/html; \
    fi

# Custom nginx configuration (optional)
# Uncomment the following line if you have a custom nginx.conf
# This will be automatically added by the build script if CUSTOM_NGINX_CONF is set
# ADD nginx.conf /etc/nginx/conf.d/nginx.conf

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
