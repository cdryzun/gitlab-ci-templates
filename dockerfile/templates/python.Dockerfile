# Python Application Dockerfile Template
# Python application container image

ARG DOCKER_MIRROR_PREFIX=""
FROM ${DOCKER_MIRROR_PREFIX}python:3.11-alpine as python

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

# Set working directory
WORKDIR /usr/src/${APP_NAME}

# Configure pip settings
ENV PIP_DEFAULT_TIMEOUT=100 \
    PYPI_HOST='https://pypi.org/simple'

# Copy application files
COPY . .

# Install dependencies and cleanup
RUN pip install --no-cache-dir -r ./requirements.txt

# Expose port (customize based on your application)
# EXPOSE 8080

# Health check (optional, customize based on your application)
# HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
#   CMD curl -f http://localhost:8080/health || exit 1

# Run the application
CMD ["python", "main.py"]
