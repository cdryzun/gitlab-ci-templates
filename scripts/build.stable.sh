#!/usr/bin/env bash
set -eo # 表示开启 pipeline 模式，执行期间发生错误，后续步骤多不进行执行。

# env
DOCKER_SECRET_ARGS=''

# 加载 工具类及 模块脚本
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done


function build_init(){
    case "${PROJECT_TYPE}" in
        web)
            if [ -n "${CUSTOM_NGINX_CONF}" ] && [ -e "${CUSTOM_NGINX_CONF}" ];then
                mv ${CUSTOM_NGINX_CONF} ${DOCKER_DAEMON_WORKSPACE}/nginx.conf
            fi
            if [ "${PACKAGE_MANAGER}" == 'yarn' ];then
                export YARN_REGISTRY=${NODE_REGISTRY}
                yarn config set registry ${NODE_REGISTRY}
                yarn install
                shell_exec "${BUILD_SHELL:-"yarn run build"}"
            else
                # 配置 pnpm registry 和本地缓存目录（类似 Maven ~/.m2）
                cat > ${CI_PROJECT_DIR}/.npmrc << EOF
registry=${NODE_REGISTRY}
store-dir=${PNPM_STORE_DIR:-/root/.pnpm-store}
EOF
                pnpm install
                shell_exec "${BUILD_SHELL:-"pnpm run build"}"
            fi
            ;;
        java)
            # 检测是 Maven 还是 Gradle 项目
            if [ -f pom.xml ]; then
                # Maven 项目
                # release plugin 需要 scm 添加
                if [ $(sed -n -e '/<scm>/,/<\/scm>/p'  pom.xml |wc -l) -eq 0 ];then
                    sed -i '/<description>/a \
    <scm> \
        <url>scm:git:'$CI_PROJECT_URL'</url> \
        <connection>scm:git:'$CI_PROJECT_URL'.git</connection> \
        <developerConnection>scm:git:'$CI_PROJECT_URL'.git</developerConnection> \
        <tag>HEAD</tag> \
    </scm>
            ' ${BUILD_MAVEN_POM_FILE}
                fi

                BUILD_SHELL=${BUILD_SHELL-'mvn clean package'}
                # release build
                if [ "${RELEASE_LIB_BUILD}" == 'true' ];then
                    # 修复文件更改, 导致 release plugin 失败
                    cd ${CI_PROJECT_DIR} && git add . && git commit -m "null" -a
                    # 下载 release lib 脚本执行
                    RELEASE_SHELL="$(curl -fsSL --header "PRIVATE-TOKEN: ${GITLAB_READ_TOKEN}" ${TEMPLATE_REPO%/devops*}/api/v4/projects/${TEMPLATE_REPO_PROJECT_ID}/repository/files/hack%2Frelease-lib.${TEMPLATE_CONTEXT}.sh/raw?ref=${TEMPLATE_BRANCH_NAME})"
                    shell_exec "${RELEASE_SHELL}"
                fi

                # 更改最终 jar 包名称
                sed -i '/<finalName>/d' ${BUILD_MAVEN_POM_FILE} # `先做一下删除，防止冲突`
                if [ "${RELEASE_BUILD}" == 'true' ];then
                    sed -i "/<build>/a <finalName>${MAVEN_APP_NAME-"app"}-${CI_BUILD_REF_NAME##v}<\/finalName>" ${BUILD_MAVEN_POM_FILE}
                else
                    sed -i "/<build>/a <finalName>${MAVEN_APP_NAME-"app"}<\/finalName>" ${BUILD_MAVEN_POM_FILE}
                fi

                shell_exec "${BUILD_SHELL}"
            elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
                # Gradle 项目
                shell_exec "${BUILD_SHELL-'gradle clean build -x test'}"
            else
                echo "${Error}未找到 Maven 或 Gradle 构建文件"
                exit 1
            fi
            ;;
        python)
            # 安装生成 whl 包前的 依赖项
            if [ -f ./requestments-build.txt ];then
                pip install -r ./requestments-build.txt -i "${PYPI}"
            fi
            # 执行构建命令
            shell_exec "${BUILD_SHELL}"
            ;;
        golang)
            # Go 构建：禁用 CGO，Linux/amd64；输出名与项目名一致
            export CGO_ENABLED="${GO_CGO_ENABLED:-0}"
            export GOOS=linux
            export GOARCH="${GO_ARCH:-amd64}"
            if [ -f go.mod ]; then
                echo "module found, start to download dependencies..."
            fi
            if [ -n "${BUILD_SHELL}" ]; then
                sh -c "${BUILD_SHELL}"
            else
                go build -ldflags "-s -w" -o "${CI_PROJECT_NAME}" ./
            fi
            ;;
        *)
            shell_exec "${BUILD_SHELL:-"echo build-shell"}"
    esac
}


function image_build_init(){
    case "${PROJECT_TYPE}" in
        web)
            cp -a ./${STATIC_FILE_NAME:-"dist"} ${DOCKER_DAEMON_WORKSPACE}
            # 如果打包输出的静态目录不是dist,重命名为dist
            if [ -n "${STATIC_FILE_NAME}" ] && [ "${STATIC_FILE_NAME}" != "dist" ];then
            cd ${DOCKER_DAEMON_WORKSPACE}
            mv ${STATIC_FILE_NAME} dist
            cd ..
            fi
            ;;
        java)
            # 检测是 Maven 还是 Gradle 项目，复制相应的 JAR 文件
            if [ -f pom.xml ]; then
                # Maven 项目：从 target 目录复制
                cp -a ./target/${MAVEN_APP_NAME-"app"}*.jar ${DOCKER_DAEMON_WORKSPACE}
            elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
                # Gradle 项目：从 build/libs 目录复制
                for app in $(ls ./build/libs/${MAVEN_APP_NAME-"app"}*.jar|grep -v 'plain'|head -n 1);do
                    cp -a ${app} ${DOCKER_DAEMON_WORKSPACE}/app.jar
                done
            fi
            ;;
        python)
            cp -a ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}
            rm -rf ${DOCKER_DAEMON_WORKSPACE}/{_*,run.sh} || true
            ;;
        py_model)
            cp -a ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}
            git remote remove origin && cp -a ${CI_PROJECT_DIR}/.git ${DOCKER_DAEMON_WORKSPACE}
            rm -rf ${DOCKER_DAEMON_WORKSPACE}/{_*,run.sh} || true
            ;;
        golang)
            # 仅复制已构建的二进制到 docker 构建目录，统一命名为 app
            cp -a "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" "${DOCKER_DAEMON_WORKSPACE}/app"
            ;;
        *)
            echo "${Tip}未找到对应的镜像初始化配置."
    esac
}


function docker_secret(){
    # 找出 当前 Dockerfile secret id 并刷入 docker build args 中
    if [[ $(cat Dockerfile 2>/dev/null|head -n 1|grep syntax|wc -l) -eq 1 ]];then
        for SECRET_ID in $(cat Dockerfile|grep 'mount=type=secret'|egrep -o 'id=[_A-Z0-9a-z]+'|awk -F '=' '{print $2}');do
            if [ ! -z "${SECRET_ID}" ];then
                if [ -z "${DOCKER_SECRET_ARGS}" ];then
                    DOCKER_SECRET_ARGS="--secret id=$SECRET_ID,src=${SECRET_ID_FILE[${SECRET_ID}]}"
                else
                    DOCKER_SECRET_ARGS="${DOCKER_SECRET_ARGS} --secret id=$SECRET_ID,src=${SECRET_ID_FILE[${SECRET_ID}]}"
                fi
            fi
        done
    fi
}

function docker_base_pull_latest(){
IFS='
'
    # get arg load env
    for ARG in $(cat Dockerfile |grep '^ARG'|grep '_VERSION'|sed "s#ARG##g"|tr -d ' "');do
        export ${ARG}
    done

    # pull dockerfile from images
    for FROM in $(cat Dockerfile |grep ^FROM);do
        if [[ "${FROM}" =~ '--platform' ]];then
            IMAGE_NAME=$(echo ${FROM}|awk '{print $3}')
        else
            IMAGE_NAME=$(echo ${FROM}|awk '{print $2}')
        fi

        if [ "${IMAGE_NAME}" != 'scratch' ];then
            echo "docker pull ${IMAGE_NAME}"|bash
        fi
    done
}

function docker_workspace_prepare(){
    # 执行 Docker 构建工作区前置准备命令
    # 在 DOCKER_DAEMON_WORKSPACE 目录下执行，用于准备构建所需的依赖配置文件
    if [ -n "${DOCKER_WORKSPACE_PREPARE_CMD}" ]; then
        echo "${Info}执行 Docker 工作区前置准备命令..."
        echo "${Tip}命令内容: ${DOCKER_WORKSPACE_PREPARE_CMD}"
        echo "${Tip}执行目录: ${DOCKER_DAEMON_WORKSPACE}"

        # 执行用户自定义的前置命令
        eval "${DOCKER_WORKSPACE_PREPARE_CMD}"

        if [ $? -eq 0 ]; then
            echo "${Info}工作区准备命令执行成功"
            ls -lha
        else
            echo "${Error}工作区准备命令执行失败，退出构建"
            exit 1
        fi
    fi
}

function docker_build_push(){

    build_init
    image_build_init
    cd "${DOCKER_DAEMON_WORKSPACE}"
    ls -lha

    # 执行工作区前置准备命令
    docker_workspace_prepare

    # 处理自定义 Dockerfile
    if [ -n "${CUSTOM_DOCKERFILE}" ];then
        # 支持自定义 Dockerfile 路径，优先使用 CUSTOM_DOCKERFILE_PATH，否则使用根目录的 Dockerfile
        local dockerfile_source="${CUSTOM_DOCKERFILE_PATH:-${CI_PROJECT_DIR}/Dockerfile}"
        rm -rf Dockerfile && cp "${dockerfile_source}" .
        # Dockerfile 添加 image 元数据信息
        sed -ie '/^FROM.*base-image.*$/a\ARG CI_COMMIT_SHORT_SHA="develop"     CI_BUILD_DATE=""     APP_NAME="app"     CI_COMMIT_REF_NAME=""     CI_COMMIT_AUTHOR=""     CI_PROJECT_NAME=""\nLABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR}       CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA}       CI_BUILD_DATE=${CI_BUILD_DATE}       CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}       DOCKER_FILE_FORM="https://gitlab.cpinnov.run/ci-cd/build-image.git"       CI_PROJECT_NAME=${CI_PROJECT_NAME}\nENV APP=${APP_NAME}' Dockerfile
    fi

    if [ -e nginx.conf ] && [ "${PROJECT_TYPE}" == 'web' ];then
        sed -i "/RUN/iADD nginx.conf /etc/nginx/conf.d/nginx.conf" Dockerfile
    fi
    # 获取当前 dockerifle secret id
    docker_secret
    # 拉取最新的 base image #58
    docker_base_pull_latest
    echo """docker build ${DOCKER_SECRET_ARGS}  \
    -t "${DOCKER_IMAGE_NAME}" . \
    "${DOCKER_BUILD_FLAGS}" \
    --build-arg CI_COMMIT_SHORT_SHA="$CI_COMMIT_SHORT_SHA" \
    --build-arg CI_BUILD_DATE="$(date +%Y-%m-%d/%H:%M)" \
    --build-arg CI_PROJECT_NAME="${CI_PROJECT_NAME}" \
    --build-arg CI_COMMIT_AUTHOR="$(echo $CI_COMMIT_AUTHOR|awk -F '[ <>]' '{print $3}')" \
    --build-arg CI_COMMIT_REF_NAME="${CI_COMMIT_REF_NAME}"
    """|bash

    docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    docker push ${DOCKER_IMAGE_NAME} \
      && docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" \
      && docker rmi -f ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"
}


function docker_retag_push(){
    echo "${Tip}release镜像匹配成功，正基于此镜像进行 ReTag"
    docker pull "${RETAG_IMGAE_NAME}"
    docker tag "${RETAG_IMGAE_NAME}" "${DOCKER_IMAGE_NAME}"
    docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    docker push ${DOCKER_IMAGE_NAME} \
      && docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" \
      && docker rmi -f ${DOCKER_IMAGE_NAME} "${RETAG_IMGAE_NAME}" "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"
}

function auto_delete_tag(){
    echo "${Tip}检测为 ${CI_COMMIT_REF_NAME} 分支，执行清理 Tag 动作，目前设置保留最新 ${PRD_CD_CREATE_TAG_NUM} 个 Tag。"
    for claen_tag in `glab release list ls|grep "${_CI_COMMIT_REF_NAME}-"|awk '{print $1}'|sort|head -n -${PRD_CD_CREATE_TAG_NUM}`;do
        glab release delete "$claen_tag" -y --with-tag
        echo "${Tip} 正在进行删除 Docker 镜像: ${CRED}${IMG_NAME}:${claen_tag}${CEND}..."
        _PROJECT_NAME=$(echo `glab repo view|head -n 1|sed 's# / #%252F#g;s#name:##g'`)

        # 清理 harbor 镜像
		if [[ `curl -u ${HARBOR_USER}:${HARBOR_PASSWD}  -X 'DELETE' \
		"${HARBOR_URL}/api/v2.0/projects/"${CI_PROJECT_NAME}"/repositories/${_PROJECT_NAME}/artifacts/${claen_tag}/tags/${claen_tag}" \
		-H 'accept: application/json' \
		-H 'X-Harbor-CSRF-Token: j8Uot7L4+17WtFRlT2O7TunAGMeKgZKfcjUXehiExpcnU8nv0vFBA+PKktX/B+vk/g3Si/+fURNJRRa0MQ7Aiw==' 2>&1` =~ (errors) ]];then
			echo "${Tip} 镜像删除失败, 请进行检查..."
		else
			echo "${Info} 镜像清理成功..."
		fi
    done
}

function auto_create_tag(){
    cat > changelog.md << EOF
## Release
- Create Trigger User: \`${GITLAB_USER_NAME}\`
- Create time: \`$(date +"%Y-%m-%d-%H:%M")\`
- Create Ref Branch: \`${CI_COMMIT_REF_NAME}\`
- Create Message: \`${PRD_CD_CREATE_TAG_MESSAGE}\`
EOF
    if [ ${DEPLOY_REPO} ];then
        echo "glab release create ${DOCKER_IMAGE_TAG} -F changelog.md \
            --ref ${CI_COMMIT_REF_NAME} --assets-links='[{\"name\":\"项目 CD Charts 地址\",\"url\":\"$(echo ${DEPLOY_REPO}| sed 's#\.git##g')/-/tree/${CI_COMMIT_REF_NAME}/${CI_PROJECT_NAME}\",\"link_type\":\"other\"}]'"|bash
    else
        echo "glab release create ${DOCKER_IMAGE_TAG} -F changelog.md \
            --ref ${CI_COMMIT_REF_NAME}"|bash
    fi
}


# 如果是 python 工程 且需要 构建成 whl 包，则将构建结果上传至 nexus pip 私服中，而不进行构建 Docker 镜像了。
if [ ! -z "${BUILD_SHELL}" -a "${PROJECT_TYPE}" == "python" ];then
    # 执行构建
    build_init
    echo "${Info}执行 ${PROJECT_TYPE} 打包构建."

    # 将结果上传至 nexus 私服中，规范目录为: dist
    for package in `ls ${PYPI_TARGET_PATH:-dist}/*.whl`;do
        pip install twine -i "${PYPI}" >/dev/null 2>&1
        twine upload -u ${NEXUS_USER} -p ${NEXUS_PASSWD} \
        --repository-url "${PYPI_PRIVATE}" "${package}"
    done

else
    if [ "${DOCKER_IMAGE_BUILD}" == "true" ];then
        if [ -n "${RETAG_IMGAE_NAME}" ] && [ "${RELEASE_RETAG_DISABLE}" != 'true' ] ;then
            # 执行 docker image retag, 不进行二次构建
            docker_retag_push
        else
            # 智能选择：单架构或多架构构建
            # 如果 _multiarch.stable.sh 已加载且 MULTIARCH_BUILD_ENABLE=true，使用多架构
            # 否则使用原有的单架构构建
            if declare -f smart_docker_build_push > /dev/null; then
                smart_docker_build_push
            else
                docker_build_push
            fi
        fi
    else
        echo "${Tip}镜像开关未开启，跳过镜像构建阶段。"
        if [ "${PRD_BUILD_CREATE_TAG}" == 'true' ];then
            echo "${Tip}检测为 ${CI_COMMIT_REF_NAME} 分支，执行创建 Tag 动作。"
            mkdir -p ~/.config/glab-cli
            CD_GIT_HOSTNAME="$(git remote -v|grep push|awk -F '/' '{print $3}')"
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
            auto_create_tag  # 自动创建代码仓库 Tag
            auto_delete_tag # 且保留最新的 n 个 Tag
        else
            build_init
        fi
    fi
fi
