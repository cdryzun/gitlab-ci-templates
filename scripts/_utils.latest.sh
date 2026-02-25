#!/usr/bin/env bash

if [ ${CI_DEBUG_TRACE} == 'true' ];then
  LOG_LEVEL=debug
fi

if [ "${LOG_LEVEL}" == 'debug' ];then
    set -x
fi

# Store initial built-in variables and utility functions during script execution
# This section loads utility functions and variables
function shell_exec(){
    set -eo # Enable pipeline mode, exit on error during execution
    echo "${1}"|bash
}

echo=echo
for cmd in `echo /bin/echo`; do
$cmd >/dev/null 2>&1 || continue
if ! $cmd -e "" | grep -qE '^-e'; then
    echo=$cmd
    break
fi
done

# Output message with text-related variables
export CSI=$($echo -e "\033[")
export CEND="${CSI}0m"
export CDGREEN="${CSI}32m"
export CRED="${CSI}1;31m"
export CGREEN="${CSI}1;32m"
export CYELLOW="${CSI}1;33m"
export CBLUE="${CSI}1;34m"
export CMAGENTA="${CSI}1;35m"
export CCYAN="${CSI}1;36m"
export CSUCCESS="$CDGREEN"
export CFAILURE="$CRED"
export CQUESTION="$CMAGENTA"
export CWARNING="$CYELLOW"
export CMSG="$CCYAN"
export Info="${CGREEN}[Info]: ${CEND}"
export Error="${CRED}[Error]: ${CEND}"
export Tip="${CYELLOW}[Note]: ${CEND}"

# Initialize variables with empty default values
PROJECT_TYPE_REX=''
EXCLUDE_PROJECT_LIST=''

# Inherit exclusion list variable from GitLab CI
EXCLUDE_PROJECT=${SONAR_EXCLUDE_PATH:-''}

# Split exclude list using "|" as separator for grep filtering
if [ $EXCLUDE_PROJECT ];then
	echo "${Info}Exclusion list is set, list as follows:"
	EXCLUDE_PROJECT_arr=(${EXCLUDE_PROJECT//,/" "})
	for exclude_path_index in "${!EXCLUDE_PROJECT_arr[@]}";do
		printf "  %-1s %-4s \n" "(${exclude_path_index})" "${EXCLUDE_PROJECT_arr[$exclude_path_index]}"
		if [ ! $EXCLUDE_PROJECT_LIST ];then
			EXCLUDE_PROJECT_LIST="${EXCLUDE_PROJECT_arr[$exclude_path_index]}"
		else
			EXCLUDE_PROJECT_LIST="${EXCLUDE_PROJECT_LIST}|${EXCLUDE_PROJECT_arr[$exclude_path_index]}"
		fi
	done
fi

# Get current script path for convenient script references and execution
SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(cd "$SCRIPT_PATH" && pwd)
if [[ -z "$SCRIPT_PATH" ]] ; then
  exit 1
fi

# Project type dictionary, outputs corresponding message based on this dictionary
declare -A TYPE_LIST=(
	["pom.xml"]="java"
	["build.gradle"]="java"
	["build.gradle.kts"]="java"
	["package.json"]="web"
	["requirements.txt"]="python"
	["go.mod"]="golang"
)

# Branch type dictionary, used to generate additional Docker image tags
# For example: sit branch generates additional :stable tag, prd branch generates additional :latest tag
declare -A BRANCH_TYPE_LIST=(
	["dev"]="main"
	["feat"]="dev"
	["sit"]="stable"
	["prd"]="latest"
	["prod"]="latest"
)

# Unit test image list - maps PROJECT_TYPE to corresponding builder image
# Project types: java, web, python, golang, py_model
declare -A UNIT_IMAGE_LIST=(
	["java"]="${MAVEN_IMAGE}"
	["web"]="${NODE_IMAGE}"
	["python"]="${PYTHON_IMAGE}"
	["golang"]="${GO_IMAGE}"
	["py_model"]="${PYTHON_IMAGE}"
)


# Docker Build Secret ID dictionary

declare -A SECRET_ID_FILE=(
  ["PIP_CONFIG"]="/root/.pip/pip.conf"
)

# Pre-stage variable preprocessing related function
function dotenv() {
  # Use absolute path to ensure operations on the same build.env file across different directories
  local ENV_FILE_ABS="${CI_PROJECT_DIR}/${ENV_FILE}"
  echo ${1}=${2} >> "${ENV_FILE_ABS}"
  source "${ENV_FILE_ABS}"
}

# Output current project type
function project_type_info() {
	case $1 in
		*)
			echo "${Info}Current project auto-detected as ${CRED}${TYPE_LIST[$1]}${CEND} project, Project ID: ${CGREEN}${2}${CEND}"
      dotenv PROJECT_TYPE ${TYPE_LIST[$1]}
	esac
}

# Automatically generate regex pattern from TYPE_LIST dictionary values
for type_each in "${!TYPE_LIST[@]}";do
	type_each=`echo "${type_each}"|sed "s#\.#\\\\\.#g"`
	if [ ! $PROJECT_TYPE_REX ];then
		PROJECT_TYPE_REX="${type_each}"
	else
		PROJECT_TYPE_REX="${PROJECT_TYPE_REX}\|${type_each}"
	fi
done
PROJECT_TYPE_REX=`echo '.*/\('${PROJECT_TYPE_REX}'\)$'`
depth1_file_num=`find . -maxdepth 1 -regex "${PROJECT_TYPE_REX}"|wc -l`  # Find depth 1, check if there are files matching the regex pattern


if [ "${depth1_file_num}" -gt 1 ];then # Error if multiple project files exist in the first level directory
	echo "#{Error}Multiple project files detected in current project, unable to distinguish builds. Please confirm and retry."
	exit 1
fi

# Automatically distinguish sub-projects in the project, pass matched projects to $1 for execution
function depthProjectExec() {
  if [ "${depth1_file_num}" -eq 1 ];then  # Check if there is a corresponding project file in the first level directory
    project_type_info `find . -maxdepth 1 -regex "${PROJECT_TYPE_REX}"|sed "s#./##g"` ${CI_PROJECT_NAME}
    if [ ${1} ];then
      ${1} ${CI_PROJECT_NAME}
    fi
  elif [ "${depth1_file_num}" -gt 1 ];then # Error if multiple project files exist in the first level directory
    echo "#{Error}Multiple project files detected in current project, unable to distinguish builds. Please confirm and retry."
  else
    # When no project file is found in the first level, search in the second level
    if [ ! `find . -maxdepth 2 -regex "${PROJECT_TYPE_REX}"|egrep -v ${EXCLUDE_PROJECT_LIST:-" "}|wc -l` -eq 0 ];then
      # Collect all sub-project information
      local all_projects=(`find . -maxdepth 2 -regex "${PROJECT_TYPE_REX}"|egrep -v ${EXCLUDE_PROJECT_LIST:-" "}`)
      local project_count=${#all_projects[@]}
      local first_project_type=""
      local sub_project_names=()

      # Iterate through projects and collect information
      for project in "${all_projects[@]}";do
        project_name=`echo "${project}"|sed 's#\./# #g'|awk -F '/' '{print $1}'|tr -d ' '`
        project_file=`echo "${project}"|sed 's#\./# #g'|awk -F '/' '{print $2}'|tr -d ' '`

        # Record the first project type
        if [ -z "${first_project_type}" ];then
          first_project_type="${TYPE_LIST[${project_file}]}"
        fi

        # Collect sub-project names
        _CI_PROJECT_NAME=`echo ${project_name}|sed "s#${CI_PROJECT_NAME}[_-]##g"|xargs -I {} echo ${CI_PROJECT_NAME}-{}`
        sub_project_names+=("${_CI_PROJECT_NAME}")
      done

      # Output summary information only once
      echo "${Info}Current project auto-detected as ${CRED}${first_project_type}${CEND} project, detected ${CGREEN}${project_count}${CEND} sub-projects: ${CGREEN}${sub_project_names[@]}${CEND}"
      dotenv PROJECT_TYPE ${first_project_type}

      # Execute actual build actions
      for project in "${all_projects[@]}";do
        project_name=`echo "${project}"|sed 's#\./# #g'|awk -F '/' '{print $1}'|tr -d ' '`
        cd "${SCRIPT_PATH}/${project_name}"

        if [ ${1} ];then
          ${1} ${CI_PROJECT_NAME}
        fi
      done
    else
      echo "${Error}Unable to find matching project file, program exiting"
      exit 1
    fi
  fi
}