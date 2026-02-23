#!/bin/bash
set -eo # 表示开启 pipeline 模式，执行期间发生错误，后续步骤多不进行执行。

# 加载 工具类及 模块脚本
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

# sonar scan 扫描主功能函数
function sonar_scan(){
	local SONAR_DIR=$SONAR_DIR
	cd "${SCRIPT_PATH}/${project_name}"
	echo "${SCRIPT_PATH}/${project_name}"

	# 当 sonarqube 扫描 Java 工程时, 进行生成所需依赖二进制目录
	if [ -f pom.xml ] && [ ! -d target/classes ];then
		if [ "${TEST_SHELL}" ];then
			if [ `echo ${TEST_SHELL}|grep mvn|wc -l` -ge 1 ];then
				shell_exec "${TEST_SHELL}"
			else
				shell_exec 'mvn test'
			fi
		else
			shell_exec ${BUILD_SHELL-'mvn clean package'}
		fi
	fi
	
	# 检查 gitlab ci 中设置的 SONAR_DIR 是否存在，当不存在的时候，根据实际使用的情况自动设置 
	if [ ! -d "${SONAR_DIR}" ];then
		local SONAR_DIR='./src'
		# 当一级目录 找不到时，尝试 到二级目录进行查找
		if [ ! -d "${SONAR_DIR}" -a `ls ./*/src|grep src|tr -d ':'|wc -l` -ge  1 ];then
			for SOURCE_PATH in `ls ./*/src|grep src|tr -d ':'`;do
				if [ ! "${SONAR_DIR_LIST}" ];then
					SONAR_DIR_LIST="$SOURCE_PATH"
				else
					SONAR_DIR_LIST="${SONAR_DIR_LIST},${SOURCE_PATH}"
				fi
			done
			local SONAR_DIR=${SONAR_DIR_LIST}
		elif [ ! -d "${SONAR_DIR}" ];then
			# 当上面 假设到 的 src 在 一二级目录多不存在时，则尝试设置为 app
			local SONAR_DIR='./app'
			if [ ! -d "${SONAR_DIR}" -a `ls ./*/app|grep app|tr -d ':'|wc -l` -ge  1 ];then
				for SOURCE_PATH in `ls ./*/src|grep src|tr -d ':'`;do
					if [ ! "${SONAR_DIR_LIST}" ];then
						SONAR_DIR_LIST="$SOURCE_PATH"
					else
						SONAR_DIR_LIST="${SONAR_DIR_LIST},${SOURCE_PATH}"
					fi
				done
				local SONAR_DIR=${SONAR_DIR_LIST}
			else
				# 多不满足时 程序执行错误退出
				echo "${Error}扫描对应源码目录未能找到，设置为默认目录 ${CRED}./${CEND}"
				SONAR_DIR='./'
			fi
		fi
	fi

	# 基于 SONAR_DIR 为其配置 SONAR_BINARIES 变量目录，JAVA 时需要。
	local SONAR_BINARIES=`echo ${SONAR_DIR}|sed 's#/src#/target/classes#g'`
	local ARGS="-Dsonar.sources=${SONAR_DIR}"

	local SONAR_SCAN_ARGS="${SONAR_SCAN_ARGS} ${ARGS}" # 基于 gitlab ci 中设置的 args 对变量做增加

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
		# 对敏感数据替换，同时输出扫描时所执行的命令，方便后续排错。
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

# 使用 _utils.sh 中 depthProjectExec 执行相关 job 主函数
depthProjectExec sonar_scan