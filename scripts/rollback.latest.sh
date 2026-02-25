#!/usr/bin/env bash

set -eu

# printenv

# Load utility classes and module scripts
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

echo ${DEPLOY_OLD_IMAGE}

git config --global user.email "${GIT_AUTO_COMMIT_EMAIL}"
git config --global user.name "${GIT_AUTO_COMMIT_NAME}"
git clone --branch ${REMOTE_BRANCH} --depth 1 "${DEPLOY_REPO%://*}://${GIT_AUTO_COMMIT_NAME}:${GITLAB_REPO_COMMIT_TOKEN}@${DEPLOY_OLD_REPO}.git" repo

DEPLOY_OLD_REPO_PROJ_NUM=$(echo ${DEPLOY_OLD_IMAGE}| awk -F, '{print NF}')
DEPLOY_OLD_REPO_PROJ_ARR=(${DEPLOY_OLD_IMAGE//,/" "})

if [ ${DEPLOY_OLD_REPO_PROJ_NUM} -gt 1 ];then
    # When DEPLOY_OLD_IMAGE contains multiple items, split before replacing
    for PROJ_ID in "${!DEPLOY_OLD_REPO_PROJ_ARR[@]}";do
        PROJ_NAME_TAG="${DEPLOY_OLD_REPO_PROJ_ARR[$PROJ_ID]}"
        _PROJECT_NAME=`echo ${PROJ_NAME_TAG%___+++*}`
        _PROJECT_TAG=`echo ${PROJ_NAME_TAG#*___+++}`
        cd "${CI_PROJECT_DIR}/repo/${_PROJECT_NAME}"
        ls -l
        # Get current value from yaml
        _targetImageTag=`cat ${DEPLOY_VALUE_FILE}|yq e "${DEPLOY_REPO_YAML_TAG}" -`
        targetImageTag="${_targetImageTag##*:}" # Fix tag & image on same line issue

        if [ "${targetImageTag}" ];then
          echo "project name: ${CYELLOW}${_PROJECT_NAME}${CEND}"
          sed -i "s#${targetImageTag}#${_PROJECT_TAG}#g" ${DEPLOY_VALUE_FILE}
          echo "${Info}verifying rollback value: `cat ${DEPLOY_VALUE_FILE}|yq e "${DEPLOY_REPO_YAML_TAG}" -`"
        else
          echo "Get ${DEPLOY_REPO_YAML_TAG} values is null, please check and retry."
          exit 1
        fi
    done
else
      _PROJECT_NAME=`echo ${DEPLOY_OLD_IMAGE%___+++*}`
      _PROJECT_TAG=`echo ${DEPLOY_OLD_IMAGE#*___+++}`

      cd "${CI_PROJECT_DIR}/repo/${_PROJECT_NAME}"
      ls -l
      # Get current value from yaml
      _targetImageTag=`cat ${DEPLOY_VALUE_FILE}|yq e "${DEPLOY_REPO_YAML_TAG}" -`
      targetImageTag="${_targetImageTag##*:}" # Fix tag & image on same line issue
      
      if [ "${targetImageTag}" ];then
        sed -i "s#${targetImageTag}#${_PROJECT_TAG}#g" ${DEPLOY_VALUE_FILE}
        echo "${Info}verifying rollback value: `cat ${DEPLOY_VALUE_FILE}|yq e "${DEPLOY_REPO_YAML_TAG}" -`"
      else
        echo "Get ${DEPLOY_REPO_YAML_TAG} values is null, please check and retry."
        exit 1
      fi
fi

# Detect if current file has changes, commit and push after changes

cd "${CI_PROJECT_DIR}"/repo \
  && git add . || true >/dev/null 2>&1

if ! git diff-index --quiet HEAD --; then
  git status
  git commit -m "${ROLLBACK_COMMIT_MESSAGE}"
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