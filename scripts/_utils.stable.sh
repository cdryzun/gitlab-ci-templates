#!/usr/bin/env bash

if [ ${CI_DEBUG_TRACE} == 'true' ];then
  LOG_LEVEL=debug
fi

if [ "${LOG_LEVEL}" == 'debug' ];then
    set -x
fi
# 存放脚本执行中的 初始内置变量 及  工具函数
# 此段到下一段说明为加载 工具函数 和 变量
function shell_exec(){
    set -eo # 表示开启 pipeline 模式，执行期间发生错误，后续步骤多不进行执行。
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

# 输出 message 携带文字相关变量
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
export Info="${CGREEN}[信息]: ${CEND}"
export Error="${CRED}[错误]: ${CEND}"
export Tip="${CYELLOW}[注意]: ${CEND}"

# 初始化变量，默认值为空
PROJECT_TYPE_REX=''
EXCLUDE_PROJECT_LIST=''

# 继承 gitlab ci 中的排除列表变量
EXCLUDE_PROJECT=${SONAR_EXCLUDE_PATH:-''}

# 切割 exclude 的列表，使用 "|" 相连接，方便 grep 进行过滤
if [ $EXCLUDE_PROJECT ];then
	echo "${Info}当前已设置排除列表，列表如下:"
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

# 获取当前脚本的路径，后续脚本引用和执行方便脚本
SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(cd "$SCRIPT_PATH" && pwd)
if [[ -z "$SCRIPT_PATH" ]] ; then
  exit 1
fi

# 工程类型字典，更具此字典输出 对应的 messgae
declare -A TYPE_LIST=(
	["pom.xml"]="java"
	["build.gradle"]="java"
	["build.gradle.kts"]="java"
	["package.json"]="web"
	["requirements.txt"]="python"
	["go.mod"]="golang"
)

# 工程类型字典，更具此字典输出 对应的 messgae
declare -A BRANCH_TYPE_LIST=(
	["dev"]="main"
	["feat"]="dev"
	["sit"]="stable"
	["prd"]="latest"
	["prod"]="latest"
)

# unit test image 列表
declare -A UNIT_IMAGE_LIST=(
	["java"]="${MAVEN_IMAGE}"
	["web"]="${NODE_IMAGE}"
	["python"]="${PYTHON_IMAGE}"
	["golang"]="${GO_IMAGE}"
)

# Docker Build Secret ID 字典
declare -A SECRET_ID_FILE=(
  ["PIP_CONFIG"]="/root/.pip/pip.conf"
)

# pre 阶段 变量前置处理相关 function
function dotenv() {
  # 使用绝对路径确保在不同目录下操作同一个 build.env 文件
  local ENV_FILE_ABS="${CI_PROJECT_DIR}/${ENV_FILE}"
  echo ${1}=${2} >> "${ENV_FILE_ABS}"
  source "${ENV_FILE_ABS}"
}

# 对当前 project 类型进行输出
function project_type_info() {
	case $1 in
		*)
			echo "${Info}当前工程自动识别为 ${CRED}${TYPE_LIST[$1]}${CEND} 工程, 项目ID为: ${CGREEN}${2}${CEND}"
      dotenv PROJECT_TYPE ${TYPE_LIST[$1]}
	esac
}

# 对 TYPE_LIST 中这个字典的值，自动生成正则表达式
for type_each in "${!TYPE_LIST[@]}";do
	type_each=`echo "${type_each}"|sed "s#\.#\\\\\.#g"`
	if [ ! $PROJECT_TYPE_REX ];then
		PROJECT_TYPE_REX="${type_each}"
	else
		PROJECT_TYPE_REX="${PROJECT_TYPE_REX}\|${type_each}"
	fi
done
PROJECT_TYPE_REX=`echo '.*/\('${PROJECT_TYPE_REX}'\)$'`
depth1_file_num=`find . -maxdepth 1 -regex "${PROJECT_TYPE_REX}"|wc -l`  # find 查找深度 1 ，是否有对应正则所匹配的文件。


if [ "${depth1_file_num}" -gt 1 ];then # 第一层目录下，如果有多个工程文件直接报错
	echo "#{Error}当前项目存在多个工程文件，无法进行区分构建，请进行确认后重试."
	exit 1
fi

# 对项目中的，子 project 进行自动区分，将 匹配到到 project 传送给 $1 进行执行相应动作。
function depthProjectExec() {
  if [ "${depth1_file_num}" -eq 1 ];then  # 查找第一层目录下，是否有对应的工程文件
    project_type_info `find . -maxdepth 1 -regex "${PROJECT_TYPE_REX}"|sed "s#./##g"` ${CI_PROJECT_NAME}
    if [ ${1} ];then
      ${1} ${CI_PROJECT_NAME}
    fi
  elif [ "${depth1_file_num}" -gt 1 ];then # 第一层目录下，如果有多个工程文件直接报错
    echo "#{Error}当前项目存在多个工程文件，无法进行区分构建，请进行确认后重试."
  else
    # 当第一层，没有工程文件时，则查找第二层
    if [ ! `find . -maxdepth 2 -regex "${PROJECT_TYPE_REX}"|egrep -v ${EXCLUDE_PROJECT_LIST:-" "}|wc -l` -eq 0 ];then
      # 收集所有子项目信息
      local all_projects=(`find . -maxdepth 2 -regex "${PROJECT_TYPE_REX}"|egrep -v ${EXCLUDE_PROJECT_LIST:-" "}`)
      local project_count=${#all_projects[@]}
      local first_project_type=""
      local sub_project_names=()

      # 遍历项目，收集信息
      for project in "${all_projects[@]}";do
        project_name=`echo "${project}"|sed 's#\./# #g'|awk -F '/' '{print $1}'|tr -d ' '`
        project_file=`echo "${project}"|sed 's#\./# #g'|awk -F '/' '{print $2}'|tr -d ' '`

        # 记录第一个项目的类型
        if [ -z "${first_project_type}" ];then
          first_project_type="${TYPE_LIST[${project_file}]}"
        fi

        # 收集子项目名称
        _CI_PROJECT_NAME=`echo ${project_name}|sed "s#${CI_PROJECT_NAME}[_-]##g"|xargs -I {} echo ${CI_PROJECT_NAME}-{}`
        sub_project_names+=("${_CI_PROJECT_NAME}")
      done

      # 只输出一次汇总信息
      echo "${Info}当前工程自动识别为 ${CRED}${first_project_type}${CEND} 工程, 检测到 ${CGREEN}${project_count}${CEND} 个子项目: ${CGREEN}${sub_project_names[@]}${CEND}"
      dotenv PROJECT_TYPE ${first_project_type}

      # 执行实际的构建动作
      for project in "${all_projects[@]}";do
        project_name=`echo "${project}"|sed 's#\./# #g'|awk -F '/' '{print $1}'|tr -d ' '`
        cd "${SCRIPT_PATH}/${project_name}"

        if [ ${1} ];then
          ${1} ${CI_PROJECT_NAME}
        fi
      done
    else
      echo "${Error}未能找到所匹配的工程文件, 程序执行退出"
      exit 1
    fi
  fi
}

# URL 环境前缀转换函数
# 参数: 目标 URL
# 功能: 根据 URL 中的环境标识 (PRE/TEST/PROD)，将其替换为对应的内部前缀
# 注意: 这是一个示例实现，用户可以根据自己的需求修改
function convert_url() {
  local url=$1
  # 用户可以配置自己的内部 URL 前缀
  local internalURL="${INTERNAL_URL_PREFIX:-http://internal.example.com}"
  local baseURL="${BASE_URL:-https://api.example.com}"

  # 定义环境与内部地址的映射
  declare -A envDict
  envDict=(
    ["PRE"]="${internalURL}/pre/"
    ["TEST"]="${internalURL}/test/"
    ["PROD"]="${internalURL}/prod/"
  )

  # 检查 URL 属于哪个环境，并替换前缀
  for env in "PRE" "TEST" "PROD"; do
    if [[ "${url}" == *"${env}"* ]]; then
      # 使用 | 作为 sed 分隔符，避免与 URL 中的 / 冲突
      echo "${url}" | sed "s|${baseURL}/${env}/|${envDict[$env]}|g"
      return 0
    fi
  done

  # 如果 URL 不匹配任何环境，返回原 URL
  echo "${url}"
  return 0
}