#!/usr/bin/env bash

#------ ENV 环境; 处理变量相关预处理。
# 对分支名称中的特殊字符做出转换，分支生成 tag 时出现异常
dotenv _CI_COMMIT_REF_NAME `echo ${CI_COMMIT_REF_NAME}|tr '/' '-'`
# _BUILD_ENV=`echo "${CI_COMMIT_REF_NAME}"|awk -F '/' '{print $2}'`
BUILD_TIME=`date +"%Y%m%d%H%M"` # 容器 Tag 中的时间戳，精确到分

# docker image 的名称
dotenv IMG_NAME ${DOCKER_REGISTRY}/${CI_PROJECT_NAMESPACE}/${CI_PROJECT_NAME}

# 根据 分支名称来确定 docker image tag name
if [ "${RELEASE_BUILD}" == 'true' ];then
  _CI_COMMIT_REF_NAME=`echo ${_CI_COMMIT_REF_NAME}|sed "s#v##g"` # docker Tag 名称去掉 v
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
    # feat/feature 分支识别，部署目标为 dev 环境
    dotenv BUILD_ENV feat
    dotenv REMOTE_BRANCH dev
    dotenv DOCKER_IMAGE_TAG "${_CI_COMMIT_REF_NAME}-${BUILD_TIME}-${CI_COMMIT_SHORT_SHA}-${CI_PIPELINE_ID}"
  else
    dotenv BUILD_ENV dev
    dotenv REMOTE_BRANCH dev
    dotenv DOCKER_IMAGE_TAG "${_CI_COMMIT_REF_NAME}-${BUILD_TIME}-${CI_COMMIT_SHORT_SHA}-${CI_PIPELINE_ID}"
  fi
fi

# 使用 image & tag 拼接成一个完整的 image name
dotenv DOCKER_IMAGE_NAME "${IMG_NAME}:${DOCKER_IMAGE_TAG}"

if [ "${RELEASE_BUILD}" ];then
  dotenv RELEASE_BUILD "${RELEASE_BUILD}"
fi

# 如果当前工程未指定类型，则自动匹配当前项目属于是什么代码类型，输出 $PROJECT_TYPE
if [ -z "${PROJECT_TYPE}" ];then
  depthProjectExec
elif [ -z "${BUILD_SHELL}" ] && [ "${PROJECT_TYPE}" == 'python' ];then
  # BUILD_SHELL 未设置的 python 类型，更新项目类型为 model, 后续执行全量 COPY 源代码动作
  dotenv PROJECT_TYPE 'py_model'
fi

# 设置 单元测试时 所使用的 基础镜像
if [ -z ${UNIT_IMAGE_LIST[$PROJECT_TYPE]} ];then
  dotenv _BUILD_IMAGE "${UNIT_IMAGE_LIST[python]}"
else
  dotenv _BUILD_IMAGE "${UNIT_IMAGE_LIST[$PROJECT_TYPE]}"
fi

# 当 prd 分支运行 build stage 时，不需要构建镜像，而是需要 创建分支，使用 git 命令，某些 镜像没有 git
# 如果设置了 BASE_BUILD_IMAGE 变量，则优先使用该变量定义的镜像
if [ "${CI_COMMIT_REF_NAME}" == 'prd' ];then
    dotenv BUILD_IMAGE "${TOOLBOX_IMAGE}"
elif [ -n "${BASE_BUILD_IMAGE}" ];then
    dotenv BUILD_IMAGE "${BASE_BUILD_IMAGE}"
else
    dotenv BUILD_IMAGE "${_BUILD_IMAGE}"
fi

# # 针对 prd 分支运行的 pipeline, 设置在 build 阶段不构建镜像, 而是且创建 Tag
# if [ "${CI_COMMIT_REF_NAME}" == 'prd' ];then
#     dotenv DOCKER_IMAGE_BUILD 'false'
#     dotenv PRD_BUILD_CREATE_TAG 'true'
# fi

#  判断 feat 特性分支是否构建 Docker 镜像
if [ "${FEAT_BRANCH}" ];then
  if [ "${FEAT_DOCKER_IMAGE_BUILD}" == 'true' ];then
    dotenv DOCKER_IMAGE_BUILD "${FEAT_DOCKER_IMAGE_BUILD}"
  else
    dotenv DOCKER_IMAGE_BUILD 'false'
  fi
fi

# prd 分支上，才能进行 创建 tag  动作
if [ "${PRD_BUILD_CREATE_TAG}" == 'true' -a "${REMOTE_BRANCH}" != 'prd' ];then
    dotenv PRD_BUILD_CREATE_TAG 'false'
fi


# 检测项目根目录是否存在 Dockerfile 文件，有则使用当前仓库下的 Dockerfile 跳过内置的
# 检查是否存在自定义的 Dockerfile（支持自定义路径或默认根目录）
# 使用绝对路径确保检测的是项目根目录，而非子项目目录
DOCKERFILE_TO_CHECK=""
if [ -n "${CUSTOM_DOCKERFILE_PATH}" ];then
  # 支持绝对路径和相对路径：绝对路径直接使用，相对路径基于项目根目录
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
      echo "${Error} 检测到 自定义 Dockerfile (${DOCKERFILE_TO_CHECK}) 中存在无效指令"
      exit 1
  else
      dotenv CUSTOM_DOCKERFILE 'true'
  fi
fi

# # 对 tag 的构建且进行基于 release 分支的 retag，镜像不进行二次构建
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