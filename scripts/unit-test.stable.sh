#!/usr/bin/env bash
set -eo # Enable pipeline mode, exit on error during execution


# Load utility classes and module scripts
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
	["golang"]=${_GO_UNIT_TEST_SHELL:-'go test ./... -count=1'}
	["py_model"]=${_PYTHON_UNIT_TEST_SHELL:-'python -m unittest'}
)

# unit test main function
function unit_test() {
  # For java projects, detect Maven or Gradle
  if [ "${PROJECT_TYPE}" == "java" ]; then
    if [ -f pom.xml ]; then
      # Maven project
      shell_exec "${_JAVA_UNIT_TEST_SHELL:-'mvn test'}"
    elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
      # Gradle project
      shell_exec "${_JAVA_UNIT_TEST_SHELL:-'gradle test'}"
    fi
  elif [ "${PROJECT_TYPE}" == "python" ] || [ "${PROJECT_TYPE}" == "py_model" ]; then
    # Python projects: install dependencies first, then run tests
    if [ -f requirements.txt ]; then
      echo "${Info}Installing Python dependencies from requirements.txt..."
      pip3 install -r requirements.txt -i ${PYPI}
    fi
    shell_exec "${UNIT_TEST_CMD[${PROJECT_TYPE}]}"
  elif [ "${PROJECT_TYPE}" == "web" ]; then
    # Node.js projects: install dependencies first, then run tests
    if [ -f package.json ]; then
      echo "${Info}Installing Node.js dependencies..."
      if [ "${PACKAGE_MANAGER}" == 'yarn' ]; then
        yarn install
      else
        # Default to pnpm, fallback to npm if pnpm is not available
        if command -v pnpm &> /dev/null; then
          pnpm install
        else
          npm install
        fi
      fi
    fi
    shell_exec "${UNIT_TEST_CMD[${PROJECT_TYPE}]}"
  else
    shell_exec "${UNIT_TEST_CMD[${PROJECT_TYPE}]}"
  fi
}

# Use depthProjectExec in _utils.sh to execute relevant job main function
depthProjectExec unit_test