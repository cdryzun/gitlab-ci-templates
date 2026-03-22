# Java Application Dockerfile Template
# 基于 OpenJDK 的标准 Java 应用容器镜像

ARG DOCKER_MIRROR_PREFIX=""
ARG OPENJDK_VERSION=17-alpine
FROM ${DOCKER_MIRROR_PREFIX}eclipse-temurin:${OPENJDK_VERSION} as java

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

# Copy the JAR file
# Note: The build process should ensure the JAR is named app*.jar
COPY --chown=daemon:daemon app*.jar /opt/deployments/${APP}.jar

# Set working directory
WORKDIR /opt/deployments

# Ensure proper permissions
RUN chown -R daemon:daemon /opt/deployments

# Switch to non-root user
USER daemon

# JVM configuration optimized for container environments
# - UseContainerSupport: Automatically detect container memory limits
# - InitialRAMPercentage: Initial heap size as percentage of total memory
# - MinRAMPercentage: Minimum heap size as percentage of total memory
# - MaxRAMPercentage: Maximum heap size as percentage of total memory
# Use shell form to ensure proper variable expansion and entrypoint compatibility
CMD java -jar -XX:+UseContainerSupport -XX:InitialRAMPercentage=40.0 -XX:MinRAMPercentage=50.0 -XX:MaxRAMPercentage=90.0 -XshowSettings:vm /opt/deployments/${APP}.jar

# Health check (optional, customize the path based on your application)
# HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
#   CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1
