#!/usr/bin/env bash
set -euo pipefail

# 加载 工具类及 模块脚本
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

ENV_FILE=${CD_ENV_FILE}

# 默认预设 ${DEPLOY_REPO_PROJ} 为当前 project 的名称
_DEPLOY_REPO_PROJ=${DEPLOY_REPO_PROJ:-$CI_PROJECT_NAME}

DEPLOY_REPO_PROJ_NUM=$(echo $_DEPLOY_REPO_PROJ| awk -F, '{print NF}')
DEPLOY_REPO_PROJ_ARR=(${_DEPLOY_REPO_PROJ//,/" "})


# 基础校验
: "${DEPLOY_REPO:?DEPLOY_REPO is required}"
: "${DEPLOY_REPO_YAML_TAG:?DEPLOY_REPO_YAML_TAG is required}"
: "${DEPLOY_VALUE_FILE:?DEPLOY_VALUE_FILE is required}"
command -v yq >/dev/null 2>&1 || { echo "yq not found in PATH"; exit 1; }

# 打印当前的部署环境
echo "Deploy branch: ${REMOTE_BRANCH}"

# 统一对 deploy_repo 做一下处理，防止异常错误（去掉协议前缀与结尾 .git）
_DEPLOY_REPO_NOPROTO="${DEPLOY_REPO#*://}"
export _DEPLOY_REPO="${_DEPLOY_REPO_NOPROTO%.git}"
if [[ "${DEPLOY_REPO}" == *"://"* ]]; then
  _SCHEME="${DEPLOY_REPO%%://*}"
else
  _SCHEME="https"
fi

# argocd 二进制下载地址
# ARGOCD_FILE_URL='https://nexus.iquantex.com/repository/static-file/tools/argocd'

git config --global user.email "${GIT_AUTO_COMMIT_EMAIL}"
git config --global user.name "${GIT_AUTO_COMMIT_NAME}"
git clone --branch "${REMOTE_BRANCH}" --depth 1 "${_SCHEME}://${GIT_AUTO_COMMIT_NAME}:${GITLAB_REPO_COMMIT_TOKEN}@${_DEPLOY_REPO}.git" repo

# 为 project 替换 image tag，同时对老的镜像进行标识存储，提供给 rollback stage 使用
if [ ${DEPLOY_REPO_PROJ_NUM} -gt 1 ];then
    DEPLOY_OLD_IMAGE=''
    for PROJ_ID in "${!DEPLOY_REPO_PROJ_ARR[@]}";do
      cd "${CI_PROJECT_DIR}/repo/${DEPLOY_REPO_PROJ_ARR[$PROJ_ID]}"
      ls -l
      # 获取当前 proj 中 老的 image 进行替换
      _oldImage=$(cat ${DEPLOY_VALUE_FILE}|yq e "${DEPLOY_REPO_YAML_TAG}" -)
      oldImage="${_oldImage##*:}" # 修复 initContainers tag & image 在一行问题
      if [ "${oldImage}" ];then
        echo "project name: ${CYELLOW}${DEPLOY_REPO_PROJ_ARR[$PROJ_ID]}${CEND}"
        echo "old value: ${CYELLOW}${oldImage}${CEND}"
        echo "replacing with new value: ${CGREEN}${DOCKER_IMAGE_TAG}${CEND}"
        DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG}" yq e -i "${DEPLOY_REPO_YAML_TAG} = strenv(DOCKER_IMAGE_TAG)" "${DEPLOY_VALUE_FILE}"
        echo "${Info}verifying new value: $(yq e "${DEPLOY_REPO_YAML_TAG}" "${DEPLOY_VALUE_FILE}")"
      else
        echo "Get ${DEPLOY_REPO_YAML_TAG} values is null, please check and retry."
        exit 1
      fi
      if [ ! ${DEPLOY_OLD_IMAGE} ];then
          DEPLOY_OLD_IMAGE="${DEPLOY_REPO_PROJ_ARR[$PROJ_ID]}___+++${oldImage}"
      else
          DEPLOY_OLD_IMAGE="${DEPLOY_OLD_IMAGE},${DEPLOY_REPO_PROJ_ARR[$PROJ_ID]}___+++${oldImage}"
      fi
    done
    cd "${CI_PROJECT_DIR}"
    echo ${DEPLOY_OLD_IMAGE}
    dotenv DEPLOY_OLD_IMAGE "${DEPLOY_OLD_IMAGE}"
else
    cd "${CI_PROJECT_DIR}/repo/${_DEPLOY_REPO_PROJ}"
    # 校验 values 文件存在
    test -f "${DEPLOY_VALUE_FILE}" || { echo "values file not found: ${DEPLOY_VALUE_FILE}"; exit 1; }
    _oldImage=$(yq e "${DEPLOY_REPO_YAML_TAG}" "${DEPLOY_VALUE_FILE}")
    oldImage="${_oldImage##*:}" # 修复 initContainers tag & image 在一行问题

    if [ "${oldImage}" ];then
      echo "old value: ${CYELLOW}${oldImage}${CEND}"
      echo "replacing with new value: ${CGREEN}${DOCKER_IMAGE_TAG}${CEND}"
      DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG}" yq e -i "${DEPLOY_REPO_YAML_TAG} = strenv(DOCKER_IMAGE_TAG)" "${DEPLOY_VALUE_FILE}"
      echo "${Info}verifying new value: $(yq e "${DEPLOY_REPO_YAML_TAG}" "${DEPLOY_VALUE_FILE}")"
    else
      echo "Get ${DEPLOY_REPO_YAML_TAG} values is null, please check and retry."
      exit 1
    fi
    cd "${CI_PROJECT_DIR}"
    dotenv DEPLOY_OLD_IMAGE "${_DEPLOY_REPO_PROJ}___+++${oldImage}"
fi

# 检测当前 文件是否有 变更，变更后 commit push

cd "${CI_PROJECT_DIR}"/repo \
  && git add . || true >/dev/null 2>&1
  
if ! git diff-index --quiet HEAD --; then
  git status -s
  git commit -m "${DEPLOY_COMMIT_MESSAGE}"
  if [ "${REMOTE_BRANCH}" == 'prd' ];then  # 如果当前是 prd 环境不之间 commit 而是 发起 MR 进入 prd 分支
    CD_GIT_HOSTNAME="$(echo $_DEPLOY_REPO|awk -F '/' '{print $1}')"
    mkdir -p ~/.config/glab-cli
    cat > ~/.config/glab-cli/config.yml << EOF
git_protocol: https
glamour_style: dark
check_update: false
display_hyperlinks: false
hosts:
    ${CD_GIT_HOSTNAME#*@}:
        token: ${GITLAB_API_TOKEN}
        api_protocol: https
        api_host: ${CD_GIT_HOSTNAME#*@}
EOF
    _PROJECT_NAME=$(echo `glab repo view|head -n 1|sed 's# / #%2F#g;s#name:##g'`)
    reviewers=''
    for user in `glab api projects/${_PROJECT_NAME}/members/all \
      |jq '.[] | select(.state=="active") | select(.access_level==50)|.username' | tr -d '\"'`;do
      if [ ! ${reviewers} ];then
        reviewers="${user}"
      else
        reviewers="${reviewers},${user}"
      fi
    done
    git checkout -b "$(date +%Y%m%d-%H%M%S)"
    glab mr create --fill --fill-commit-body  \
      --yes --remove-source-branch --reviewer ${reviewers} \
      --target-branch ${REMOTE_BRANCH} --assignee ${reviewers}
  else
    git push origin "${REMOTE_BRANCH}"
  fi
else
  echo "${Tip}检测到未有文件发生变更，或目标文件以完成更新。"
fi

####
cd "${CI_PROJECT_DIR}"
dotenv DEPLOY_OLD_REPO "${_DEPLOY_REPO}"
dotenv _DEPLOY_REPO "${_DEPLOY_REPO}"
