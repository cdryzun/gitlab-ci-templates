#!/usr/bin/env bash
set -euo pipefail

# Load utility classes and module scripts
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

# Sonar scan main function
function sonar_scan(){
	local SONAR_DIR=$SONAR_DIR
	cd "${SCRIPT_PATH}/${project_name}"
	echo "${SCRIPT_PATH}/${project_name}"

	# When sonarqube scans Java project, generate required dependency binary directory
	if [ -f pom.xml ] && [ ! -d target/classes ];then
		if [ "${TEST_SHELL}" ];then
			if [ `echo ${TEST_SHELL}|grep mvn|wc -l` -ge 1 ];then
				shell_exec "${TEST_SHELL}"
			else
				shell_exec 'mvn test'
			fi
		else
			shell_exec "${BUILD_SHELL-mvn clean package}"
		fi
	fi

	# Check if SONAR_DIR set in gitlab ci exists, if not, automatically set based on project type
	if [ ! -d "${SONAR_DIR}" ];then
		# Set source directory based on project type
		case "${PROJECT_TYPE}" in
			golang)
				# Go projects typically have source files in root directory
				local SONAR_DIR='./'
				echo "[Info] Go project detected, using project root as source directory"
				;;
			java)
				# Java projects typically use src/main/java
				if [ -d "./src/main/java" ]; then
					local SONAR_DIR='./src/main/java'
				elif [ -d "./src" ]; then
					local SONAR_DIR='./src'
				else
					local SONAR_DIR='./'
				fi
				;;
			nodejs|web)
				# Node.js/Web projects may have src directory
				if [ -d "./src" ]; then
					local SONAR_DIR='./src'
				else
					local SONAR_DIR='./'
				fi
				;;
			python)
				# Python projects may have src or app directory
				if [ -d "./src" ]; then
					local SONAR_DIR='./src'
				elif [ -d "./app" ]; then
					local SONAR_DIR='./app'
				else
					local SONAR_DIR='./'
				fi
				;;
			*)
				# For unknown project types, try to detect source directory
				local SONAR_DIR='./src'
				if [ ! -d "${SONAR_DIR}" ]; then
					# Try searching in subdirectories
					if ls ./*/src 2>/dev/null | grep -q src; then
						SONAR_DIR_LIST=""
						for SOURCE_PATH in $(ls ./*/src 2>/dev/null | grep src | tr -d ':'); do
							if [ ! "${SONAR_DIR_LIST}" ];then
								SONAR_DIR_LIST="$SOURCE_PATH"
							else
								SONAR_DIR_LIST="${SONAR_DIR_LIST},${SOURCE_PATH}"
							fi
						done
						local SONAR_DIR=${SONAR_DIR_LIST}
					else
						# Use project root as fallback
						echo "[Warning] Unable to find source directory, using project root ./"
						local SONAR_DIR='./'
					fi
				fi
				;;
		esac
	fi

	# Configure SONAR_BINARIES variable directory based on SONAR_DIR, required for JAVA
	# Only apply this for Java projects to avoid unnecessary transformations
	if [ "${PROJECT_TYPE}" == "java" ] && [[ "${SONAR_DIR}" == *"/src"* ]]; then
		local SONAR_BINARIES=$(echo "${SONAR_DIR}" | sed 's#/src#/target/classes#g')
	else
		# For non-Java projects, binaries directory is not applicable
		local SONAR_BINARIES=""
	fi
	local ARGS="-Dsonar.sources=${SONAR_DIR}"

	local SONAR_SCAN_ARGS="${SONAR_SCAN_ARGS} ${ARGS}" # Add to args variable set in gitlab ci

	local GLOBAL_PROJECT_ARGS="-Dsonar.projectKey=${1}
							-Dsonar.projectName=${1} 
							-Dsonar.projectVersion=${CI_COMMIT_REF_NAME} 
							-Dsonar.projectDescription=${CI_PROJECT_TITLE}"

	local GLOBAL_SERVER_ARGS="-Dsonar.ws.timeout=30
							-Dsonar.links.homepage=${CI_PROJECT_URL} 
							-Dsonar.host.url=${SONAR_URL}
							-Dsonar.login=${SONAR_TOKEN}
							-Dsonar.sourceEncoding=UTF-8
							-Dsonar.java.binaries="${SONAR_BINARIES}"
							-Dsonar.java.test.binaries="${SONAR_TEST_BINARIES}"
							-Dsonar.java.surefire.report=target/surefire-reports"

	local GLOBAL_MR_ARGS="-Dsonar.pullrequest.key=${CI_MERGE_REQUEST_IID} 
					-Dsonar.pullrequest.branch=${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME} 
					-Dsonar.pullrequest.base=${CI_MERGE_REQUEST_TARGET_BRANCH_NAME} 
					-Dsonar.gitlab.ref_name=${CI_COMMIT_REF_NAME} 
					-Dsonar.gitlab.commit_sha=${CI_COMMIT_SHA} 
					-Dsonar.gitlab.project_id=${CI_PROJECT_PATH} 
					-Dsonar.pullrequest.gitlab.repositorySlug=${CI_PROJECT_ID}"

	local MULTI_BRANCH_ARGS="-Dsonar.branch.name=${CI_COMMIT_REF_NAME}"

	set +x
	if [ $CI_PIPELINE_SOURCE == 'merge_request_event' ];then
		# Replace sensitive data and output scan command for troubleshooting
		if [ $SONAR_GATE == "true" ];then
			echo "sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS} ${GLOBAL_MR_ARGS} -Dsonar.qualitygate.wait=true"| sed "s#${SONAR_TOKEN}#******#g" 
			
			sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS} ${GLOBAL_MR_ARGS} -Dsonar.qualitygate.wait=true
		else
			echo "sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS} ${GLOBAL_MR_ARGS}"|sed "s#${SONAR_TOKEN}#******#g"

			sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS} ${GLOBAL_MR_ARGS}
		fi
	else
		if [ $SONAR_GATE == "true" ];then
			echo "sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \ 
				${SONAR_SCAN_ARGS} -Dsonar.qualitygate.wait=true"|sed "s#${SONAR_TOKEN}#******#g"

			sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS} -Dsonar.qualitygate.wait=true
		else
			echo "sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS}"|sed "s#${SONAR_TOKEN}#******#g"

			sonar-scanner ${GLOBAL_PROJECT_ARGS} ${GLOBAL_SERVER_ARGS} \
				${SONAR_SCAN_ARGS}
		fi
	fi
}

# Use depthProjectExec from _utils.sh to execute related job main function
depthProjectExec sonar_scan