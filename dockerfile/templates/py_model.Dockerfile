# Python Model Library Dockerfile Template
# Lightweight container for Python model libraries
# Designed to be used as an initContainer mounted to a main container

FROM alpine:latest as py_model

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
      maintainer="DevOps Team" \
      description="Python model library for initContainer deployment"

# Set environment variables
ENV APP=${APP_NAME}

# Set working directory
WORKDIR /usr/src/${APP_NAME}

# Copy all model files
# Note: This image is designed to be used as an initContainer
# The files will be copied to a shared volume at runtime
COPY . .

# Default command (usually overridden by initContainer configuration)
CMD ["sh", "-c", "echo 'Model library image ready. This should be used as an initContainer.'"]
