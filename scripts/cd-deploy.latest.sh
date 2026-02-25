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
# ARGOCD_FILE_URL='https://nexus.iquantex.com/repository/static-file/tools/argocd'

git config --global user.email "${GIT_AUTO_COMMIT_EMAIL}"
git config --global user.name "${GIT_AUTO_COMMIT_NAME}"

git clone --branch "${REMOTE_BRANCH}" --depth 1 "${_SCHEME}://${GIT_AUTO_COMMIT_NAME}:${GITLAB_REPO_COMMIT_TOKEN}@${_DEPLOY_REPO}.git" repo
cd "repo/${_DEPLOY_REPO_PROJ}"

# Validate values file exists
if [ ! -f "${DEPLOY_VALUE_FILE}" ]; then
  echo "values file not found: ${DEPLOY_VALUE_FILE}"
  exit 1
fi

# Get current value from yaml
_oldImage=$(yq e "${DEPLOY_REPO_YAML_TAG}" "${DEPLOY_VALUE_FILE}")
oldImage="${_oldImage##*:}" # Fix tag & image on same line issue

if [ -n "${oldImage}" ]; then
  echo "old value: ${CYELLOW}${oldImage}${CEND}"
  echo "replacing with new value: ${CGREEN}${DOCKER_IMAGE_TAG}${CEND}"
  DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG}" yq e -i "${DEPLOY_REPO_YAML_TAG} = strenv(DOCKER_IMAGE_TAG)" "${DEPLOY_VALUE_FILE}"
  echo "${Info}verifying new value: $(yq e "${DEPLOY_REPO_YAML_TAG}" "${DEPLOY_VALUE_FILE}")"
else
  echo "Get ${DEPLOY_REPO_YAML_TAG} values is null, please check and retry."
  exit 1
fi

git add . || true >/dev/null 2>&1

if ! git diff-index --quiet HEAD --; then
  git status -s
  git commit -m "${DEPLOY_COMMIT_MESSAGE}"
  if [ "${REMOTE_BRANCH}" == 'prd' ];then
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
    git checkout -b "$(date +%Y%m%d-%H%M)"
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
dotenv DEPLOY_OLD_IMAGE "${oldImage}"
dotenv DEPLOY_OLD_REPO_PROJ "${_DEPLOY_REPO_PROJ}"
dotenv DEPLOY_OLD_REPO "${_DEPLOY_REPO}"

# argocd to sync project (see ARGOCD_FILE_URL comment to enable)
