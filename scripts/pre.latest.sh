#!/usr/bin/env bash

#------ ENV environment; Process variable-related preprocessing
# Convert special characters in branch names to prevent errors when generating tags from branches
dotenv _CI_COMMIT_REF_NAME `echo ${CI_COMMIT_REF_NAME}|tr '/' '-'`
# _BUILD_ENV=`echo "${CI_COMMIT_REF_NAME}"|awk -F '/' '{print $2}'`
BUILD_TIME=`date +"%Y%m%d%H%M"` # Timestamp in container Tag, accurate to minute

dotenv LOG_LEVEL ${LOG_LEVEL}

# Docker image name construction
# For Docker Hub, use DOCKER_HUB_ORGANIZATION instead of CI_PROJECT_NAMESPACE
# because Docker Hub only supports single-level organization/username
# Also flatten multi-level namespace into image name to avoid conflicts
if [ "${DOCKER_REGISTRY}" = "docker.io" ]; then
  # Flatten namespace: replace / with -
  _flat_namespace=$(echo "${CI_PROJECT_NAMESPACE}" | tr '/' '-')
  if [ -n "${DOCKER_HUB_ORGANIZATION}" ]; then
    # Docker Hub format: docker.io/{organization}/{namespace-project}
    # Use _ to separate flattened namespace and project name
    dotenv IMG_NAME ${DOCKER_REGISTRY}/${DOCKER_HUB_ORGANIZATION}/${_flat_namespace}_${CI_PROJECT_NAME}
  else
    # Docker Hub without organization: use flattened namespace as organization
    dotenv IMG_NAME ${DOCKER_REGISTRY}/${_flat_namespace}/${_flat_namespace}_${CI_PROJECT_NAME}
  fi
else
  # Private registry: use original multi-level namespace format
  dotenv IMG_NAME ${DOCKER_REGISTRY}/${CI_PROJECT_NAMESPACE}/${CI_PROJECT_NAME}
fi

# Determine docker image tag name based on branch name
if [ "${RELEASE_BUILD}" == 'true' ];then
  _CI_COMMIT_REF_NAME=`echo ${_CI_COMMIT_REF_NAME}|sed "s#v##g"` # Remove v from docker Tag name
  dotenv DOCKER_IMAGE_TAG ${_CI_COMMIT_REF_NAME}
  dotenv BUILD_ENV prd
  dotenv REMOTE_BRANCH prd
else
  if [ ${_CI_COMMIT_REF_NAME} == 'sit' -o ${_CI_COMMIT_REF_NAME} == 'prd' ];then
    dotenv BUILD_ENV ${_CI_COMMIT_REF_NAME}
    dotenv REMOTE_BRANCH ${_CI_COMMIT_REF_NAME}
    dotenv DOCKER_IMAGE_TAG "${_CI_COMMIT_REF_NAME}-${BUILD_TIME}-${CI_COMMIT_SHORT_SHA}-${CI_PIPELINE_ID}"
  elif [[ ${_CI_COMMIT_REF_NAME} =~ ^prd-.*+$ ]];then
    dotenv REMOTE_BRANCH prd
    dotenv DOCKER_IMAGE_TAG "${_CI_COMMIT_REF_NAME}"
  elif [[ ${_CI_COMMIT_REF_NAME} =~ ^feat.*$ ]] || [[ ${_CI_COMMIT_REF_NAME} =~ ^feature.*$ ]];then
    # feat/feature branch recognition, deployment target is dev environment
    dotenv BUILD_ENV feat
    dotenv REMOTE_BRANCH dev
    dotenv DOCKER_IMAGE_TAG "${_CI_COMMIT_REF_NAME}-${BUILD_TIME}-${CI_COMMIT_SHORT_SHA}-${CI_PIPELINE_ID}"
  else
    dotenv BUILD_ENV dev
    dotenv REMOTE_BRANCH dev
    dotenv DOCKER_IMAGE_TAG "${_CI_COMMIT_REF_NAME}-${BUILD_TIME}-${CI_COMMIT_SHORT_SHA}-${CI_PIPELINE_ID}"
  fi
fi

# Combine image & tag into complete image name
dotenv DOCKER_IMAGE_NAME "${IMG_NAME}:${DOCKER_IMAGE_TAG}"

if [ "${RELEASE_BUILD}" ];then
  dotenv RELEASE_BUILD "${RELEASE_BUILD}"
fi

# If current project type is not specified, automatically match what code type the current project is, output $PROJECT_TYPE
if [ -z "${PROJECT_TYPE}" ];then
  depthProjectExec
elif [ -z "${BUILD_SHELL}" ] && [ "${PROJECT_TYPE}" == 'python' ];then
  # Python type without BUILD_SHELL set, update project type to model, subsequent execution will copy full source code
  dotenv PROJECT_TYPE 'py_model'
fi

# When DOCKERFILE_BUILD_JDK_VERSION jdk version is set, automatically set corresponding image version
if [[ ! ${DOCKERFILE_BUILD_JDK_VERSION} =~ '8' ]];then
    _jdk_version=$(echo ${DOCKERFILE_BUILD_JDK_VERSION}|awk -F '-' '{print $1}')
    _MAVEN_IMAGE="docker.io/cdryzun/glci-builder-java:jdk${_jdk_version}"
    _SONAR_IMAGE="docker.io/cdryzun/glci-builder-java:jdk${_jdk_version}"
    dotenv MAVEN_IMAGE ${_MAVEN_IMAGE}
    dotenv SONAR_IMAGE ${_SONAR_IMAGE}
fi

# Unit test image list - maps PROJECT_TYPE to corresponding builder image
# Project types: java, web, python, golang, golang_nodejs, py_model
declare -A UNIT_IMAGE_LIST=(
	["java"]="${MAVEN_IMAGE}"
	["web"]="${NODE_IMAGE}"
	["python"]="${PYTHON_IMAGE}"
	["golang"]="${GO_IMAGE}"
	["golang_nodejs"]="${GOLANG_NODEJS_IMAGE}"
	["py_model"]="${PYTHON_IMAGE}"
)

# Set base image used for unit testing and build
if [ -z "${UNIT_IMAGE_LIST[$PROJECT_TYPE]}" ];then
  echo "${Error}Unknown PROJECT_TYPE: ${PROJECT_TYPE}, falling back to toolbox image"
  dotenv _BUILD_IMAGE "${TOOLBOX_IMAGE}"
else
  dotenv _BUILD_IMAGE "${UNIT_IMAGE_LIST[$PROJECT_TYPE]}"
fi

# Determine final BUILD_IMAGE based on context:
# 1. prd branch: use toolbox (needs git for tag creation)
# 2. BASE_BUILD_IMAGE override: use user-specified image
# 3. Default: use project-type-specific builder image
if [ "${CI_COMMIT_REF_NAME}" == 'prd' ];then
    dotenv BUILD_IMAGE "${TOOLBOX_IMAGE}"
elif [ -n "${BASE_BUILD_IMAGE}" ];then
    dotenv BUILD_IMAGE "${BASE_BUILD_IMAGE}"
else
    dotenv BUILD_IMAGE "${_BUILD_IMAGE}"
fi

# # For pipeline running on prd branch, set to not build image in build stage, but create Tag instead
# if [ "${CI_COMMIT_REF_NAME}" == 'prd' ];then
#     dotenv DOCKER_IMAGE_BUILD 'false'
#     dotenv PRD_BUILD_CREATE_TAG 'true'
# fi

#  Determine whether feat feature branch builds Docker image
if [ "${FEAT_BRANCH}" ];then
  if [ "${FEAT_DOCKER_IMAGE_BUILD}" == 'true' ];then
    dotenv DOCKER_IMAGE_BUILD "${FEAT_DOCKER_IMAGE_BUILD}"
  else
    dotenv DOCKER_IMAGE_BUILD 'false'
  fi
fi

# Only prd branch can perform create tag action
if [ "${PRD_BUILD_CREATE_TAG}" == 'true' -a "${REMOTE_BRANCH}" != 'prd' ];then
    dotenv PRD_BUILD_CREATE_TAG 'false'
fi


# Check if Dockerfile file exists in project root, if so use Dockerfile from current repository, skip built-in
# Check if custom Dockerfile exists (supports custom path or default root directory)
# Use absolute path to ensure detection is in project root, not subproject directory
DOCKERFILE_TO_CHECK=""
if [ -n "${CUSTOM_DOCKERFILE_PATH}" ];then
  # Support both absolute and relative paths: absolute path used directly, relative path based on project root
  if [[ "${CUSTOM_DOCKERFILE_PATH}" == /* ]];then
    _dockerfile_path="${CUSTOM_DOCKERFILE_PATH}"
  else
    _dockerfile_path="${CI_PROJECT_DIR}/${CUSTOM_DOCKERFILE_PATH}"
  fi
  [ -f "${_dockerfile_path}" ] && DOCKERFILE_TO_CHECK="${_dockerfile_path}"
elif [ -f "${CI_PROJECT_DIR}/Dockerfile" ];then
  DOCKERFILE_TO_CHECK="${CI_PROJECT_DIR}/Dockerfile"
fi

if [ -n "${DOCKERFILE_TO_CHECK}" ];then
  if [ $(cat "${DOCKERFILE_TO_CHECK}"|egrep -v "^#|^$"|egrep "^(ENTRYPOINT|USER|WORKDIR|HEALTHCHECK|LABEL|MAINTAINER|CMD)"|wc -l) -gt 0 ];then
      echo "${Error} Invalid instructions detected in custom Dockerfile (${DOCKERFILE_TO_CHECK})"
      exit 1
  else
      dotenv CUSTOM_DOCKERFILE 'true'
  fi
fi

# # For tag builds based on release branch retag, image is not rebuilt
# if [ ${REMOTE_BRANCH} == 'prd' ];then
#    RELEASE_IMAGE_NAME=`echo ${DOCKER_IMAGE_NAME}| sed 's#:v#:release-#g'`
#    dotenv RELEASE_IMAGE_NAME "${RELEASE_IMAGE_NAME}"
#    docker pull "${RELEASE_IMAGE_NAME}"
#    if [ "$?" -eq 0  ];then
#       dotenv RETAG_IMGAE_NAME ${RELEASE_IMAGE_NAME}
#     else
#       dotenv RETAG_IMGAE_NAME ''
#    fi
# fi