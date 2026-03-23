#!/usr/bin/env bash
set -euo pipefail

# Load utility classes and module scripts
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

ENV_FILE=${CD_ENV_FILE}

# Default preset ${DEPLOY_REPO_PROJ} to current project name
_DEPLOY_REPO_PROJ=${DEPLOY_REPO_PROJ:-$CI_PROJECT_NAME}

DEPLOY_REPO_PROJ_NUM=$(echo $_DEPLOY_REPO_PROJ| awk -F, '{print NF}')
DEPLOY_REPO_PROJ_ARR=(${_DEPLOY_REPO_PROJ//,/" "})


# Basic validation
: "${DEPLOY_REPO:?DEPLOY_REPO is required}"
: "${DEPLOY_REPO_YAML_TAG:?DEPLOY_REPO_YAML_TAG is required}"
: "${DEPLOY_VALUE_FILE:?DEPLOY_VALUE_FILE is required}"
command -v yq >/dev/null 2>&1 || { echo "yq not found in PATH"; exit 1; }

# Print current deployment environment
echo "Deploy branch: ${REMOTE_BRANCH}"

# Uniformly process deploy_repo to prevent errors (remove protocol prefix and trailing .git)
_DEPLOY_REPO_NOPROTO="${DEPLOY_REPO#*://}"
export _DEPLOY_REPO="${_DEPLOY_REPO_NOPROTO%.git}"
if [[ "${DEPLOY_REPO}" == *"://"* ]]; then
  _SCHEME="${DEPLOY_REPO%%://*}"
else
  _SCHEME="https"
fi

# argocd binary download URL
# ARGOCD_FILE_URL: Configure ArgoCD CLI download URL if not using glci-toolbox image

git config --global user.email "${GIT_AUTO_COMMIT_EMAIL}"
git config --global user.name "${GIT_AUTO_COMMIT_NAME}"
git clone --branch "${REMOTE_BRANCH}" --depth 1 "${_SCHEME}://${GIT_AUTO_COMMIT_NAME}:${GITLAB_REPO_COMMIT_TOKEN}@${_DEPLOY_REPO}.git" repo

# Update DEPLOY_VALUE_FILE with new image tag via yq
# Works for any YAML structure: Helm values.yaml, Kustomize kustomization.yaml, etc.
# The target field is specified by DEPLOY_REPO_YAML_TAG (e.g., ".image.tag")
function update_deploy_file() {
  local deploy_file="${1}"
  local old_tag
  old_tag=$(yq e "${DEPLOY_REPO_YAML_TAG}" "${deploy_file}")
  old_tag="${old_tag##*:}"
  if [ -n "${old_tag}" ]; then
    echo "old value: ${CYELLOW}${old_tag}${CEND}"
    echo "replacing with: ${CGREEN}${DOCKER_IMAGE_TAG}${CEND}"
    DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG}" yq e -i "${DEPLOY_REPO_YAML_TAG} = strenv(DOCKER_IMAGE_TAG)" "${deploy_file}"
    echo "${Info}verified: $(yq e "${DEPLOY_REPO_YAML_TAG}" "${deploy_file}")"
  else
    echo "${Error}${DEPLOY_REPO_YAML_TAG} is null in ${deploy_file}"
    exit 1
  fi
  echo "${old_tag}"
}

# Replace image tag for project and mark old image for rollback stage
if [ ${DEPLOY_REPO_PROJ_NUM} -gt 1 ];then
    DEPLOY_OLD_IMAGE=''
    for PROJ_ID in "${!DEPLOY_REPO_PROJ_ARR[@]}";do
      cd "${CI_PROJECT_DIR}/repo/${DEPLOY_REPO_PROJ_ARR[$PROJ_ID]}"
      ls -l
      # Get old image from current project for replacement
      _oldImage=$(cat ${DEPLOY_VALUE_FILE}|yq e "${DEPLOY_REPO_YAML_TAG}" -)
      oldImage="${_oldImage##*:}" # Fix initContainers tag & image on same line issue
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

    # Support comma-separated multiple deploy files
    IFS=',' read -ra _DEPLOY_FILES <<< "${DEPLOY_VALUE_FILE}"
    oldImage=""
    for _df in "${_DEPLOY_FILES[@]}"; do
      _df=$(echo "${_df}" | xargs)
      test -f "${_df}" || { echo "${Error}deploy file not found: ${_df}"; exit 1; }
      echo "${Info}Updating ${_df} [${DEPLOY_REPO_YAML_TAG}]..."
      oldImage=$(update_deploy_file "${_df}")
    done
    cd "${CI_PROJECT_DIR}"
    dotenv DEPLOY_OLD_IMAGE "${_DEPLOY_REPO_PROJ}___+++${oldImage}"
fi

# Detect if current file has changes, commit and push after changes

cd "${CI_PROJECT_DIR}"/repo \
  && git add . || true >/dev/null 2>&1
  
if ! git diff-index --quiet HEAD --; then
  git status -s
  git commit -m "${DEPLOY_COMMIT_MESSAGE}"
  if [ "${REMOTE_BRANCH}" == 'prd' ];then  # If current environment is prd, don't commit directly, create MR to prd branch instead
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
  echo "${Tip}No file changes detected, or target file already updated."
fi

####
cd "${CI_PROJECT_DIR}"
dotenv DEPLOY_OLD_REPO "${_DEPLOY_REPO}"
dotenv _DEPLOY_REPO "${_DEPLOY_REPO}"
