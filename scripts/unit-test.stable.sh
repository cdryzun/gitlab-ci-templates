#!/usr/bin/env bash
set -eo # 表示开启 pipeline 模式，执行期间发生错误，后续步骤多不进行执行。


# 加载 工具类及 模块脚本
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

# load ci env vars
_PYTHON_UNIT_TEST_SHELL=${PYTHON_UNIT_TEST_SHELL}
_NODE_UNIT_TEST_SHELL=${NODE_UNIT_TEST_SHELL}
_GO_UNIT_TEST_SHELL=${GO_UNIT_TEST_SHELL}
_JAVA_UNIT_TEST_SHELL=${JAVA_UNIT_TEST_SHELL}

declare -A UNIT_TEST_CMD=(
	["java"]=${_JAVA_UNIT_TEST_SHELL:-'mvn test'}
	["web"]=${_NODE_UNIT_TEST_SHELL:-'pnpm test'}
	["python"]=${_PYTHON_UNIT_TEST_SHELL:-'python -m unittest'}
	["golang"]=${_JAVA_UNIT_TEST_SHELL:-'go test'}
	["py_model"]=${_PYTHON_UNIT_TEST_SHELL:-'python -m unittest'}
)

# unit test main function
function unit_test() {
  # 对于 java 项目，检测是 Maven 还是 Gradle
  if [ "${PROJECT_TYPE}" == "java" ]; then
    if [ -f pom.xml ]; then
      # Maven 项目
      shell_exec "${_JAVA_UNIT_TEST_SHELL:-'mvn test'}"
    elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
      # Gradle 项目
      shell_exec "${_JAVA_UNIT_TEST_SHELL:-'gradle test'}"
    fi
  else
    shell_exec "${UNIT_TEST_CMD[${PROJECT_TYPE}]}"
  fi
}

# 使用 _utils.sh 中 depthProjectExec 执行相关 job 主函数
depthProjectExec unit_test