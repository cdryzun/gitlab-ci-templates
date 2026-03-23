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

# Helper: update image tag in a single values file (Helm mode)
function update_helm_values() {
  local values_file="${1}"
  local old_tag
  old_tag=$(yq e "${DEPLOY_REPO_YAML_TAG}" "${values_file}")
  old_tag="${old_tag##*:}"
  if [ -n "${old_tag}" ]; then
    echo "old value: ${CYELLOW}${old_tag}${CEND}"
    echo "replacing with: ${CGREEN}${DOCKER_IMAGE_TAG}${CEND}"
    DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG}" yq e -i "${DEPLOY_REPO_YAML_TAG} = strenv(DOCKER_IMAGE_TAG)" "${values_file}"
    echo "${Info}verified: $(yq e "${DEPLOY_REPO_YAML_TAG}" "${values_file}")"
  else
    echo "${Error}${DEPLOY_REPO_YAML_TAG} is null in ${values_file}"
    exit 1
  fi
  echo "${old_tag}"
}

# Helper: update image tag via Kustomize
function update_kustomize_image() {
  local img_name="${KUSTOMIZE_IMAGE_NAME:-${IMG_NAME}}"
  echo "old image: ${CYELLOW}${img_name}${CEND}"
  echo "new tag: ${CGREEN}${DOCKER_IMAGE_TAG}${CEND}"
  if command -v kustomize >/dev/null 2>&1; then
    kustomize edit set image "${img_name}:${DOCKER_IMAGE_TAG}"
  else
    # Fallback: use yq to edit kustomization.yaml
    yq e -i "(.images[] | select(.name == \"${img_name}\")).newTag = \"${DOCKER_IMAGE_TAG}\"" kustomization.yaml
  fi
  echo "${Info}verified: $(grep -A2 "${img_name}" kustomization.yaml)"
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

    if [ -f kustomization.yaml ]; then
      # Auto-detected: Kustomize project
      echo "${Info}Kustomize project detected (kustomization.yaml found)"
      update_kustomize_image
      dotenv DEPLOY_OLD_IMAGE "${_DEPLOY_REPO_PROJ}___+++kustomize"
    else
      # Helm mode: support comma-separated multiple value files
      IFS=',' read -ra _VALUE_FILES <<< "${DEPLOY_VALUE_FILE}"
      oldImage=""
      for _vf in "${_VALUE_FILES[@]}"; do
        _vf=$(echo "${_vf}" | xargs)  # trim whitespace
        test -f "${_vf}" || { echo "${Error}values file not found: ${_vf}"; exit 1; }
        echo "${Info}Updating ${_vf}..."
        oldImage=$(update_helm_values "${_vf}")
      done
      cd "${CI_PROJECT_DIR}"
      dotenv DEPLOY_OLD_IMAGE "${_DEPLOY_REPO_PROJ}___+++${oldImage}"
    fi
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
