#!/usr/bin/env bash
set -eo # Enable pipeline mode, exit on error during execution

# env
DOCKER_SECRET_ARGS=''

# Load utility classes and module scripts
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
            # Configure pnpm registry and local cache directory (similar to Maven ~/.m2)
                cat > ${CI_PROJECT_DIR}/.npmrc << EOF
registry=${NODE_REGISTRY}
store-dir=${PNPM_STORE_DIR:-/root/.pnpm-store}
EOF
                pnpm install
                shell_exec "${BUILD_SHELL:-"pnpm run build"}"
            fi
            ;;
        java)
            # Detect Maven or Gradle project
            if [ -f pom.xml ]; then
                # Maven project
                # release plugin requires scm to be added
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
                    # Fix file changes that cause release plugin to fail
                    cd ${CI_PROJECT_DIR} && git add . && git commit -m "null" -a
                    # Download and execute release lib script
                    RELEASE_SHELL="$(curl -fsSL --header "PRIVATE-TOKEN: ${GITLAB_READ_TOKEN}" ${TEMPLATE_REPO%/devops*}/api/v4/projects/${TEMPLATE_REPO_PROJECT_ID}/repository/files/hack%2Frelease-lib.${TEMPLATE_CONTEXT}.sh/raw?ref=${TEMPLATE_BRANCH_NAME})"
                    shell_exec "${RELEASE_SHELL}"
                fi

                # Change final jar package name
                sed -i '/<finalName>/d' ${BUILD_MAVEN_POM_FILE} # Delete first to prevent conflicts
                if [ "${RELEASE_BUILD}" == 'true' ];then
                    sed -i "/<build>/a <finalName>${MAVEN_APP_NAME-"app"}-${CI_BUILD_REF_NAME##v}<\/finalName>" ${BUILD_MAVEN_POM_FILE}
                else
                    sed -i "/<build>/a <finalName>${MAVEN_APP_NAME-"app"}<\/finalName>" ${BUILD_MAVEN_POM_FILE}
                fi

                shell_exec "${BUILD_SHELL}"
            elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
                # Gradle project
                shell_exec "${BUILD_SHELL-'gradle clean build -x test'}"
            else
                echo "${Error}Maven or Gradle build file not found"
                exit 1
            fi
            ;;
        python)
            # Install dependencies before building whl package
            if [ -f ./requestments-build.txt ];then
                pip install -r ./requestments-build.txt -i "${PYPI}"
            fi
            # Execute build command
            shell_exec "${BUILD_SHELL}"
            ;;
        golang)
            # Go build: disable CGO, Linux/amd64; output name consistent with project name
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
            # If build output static directory is not dist, rename to dist
            if [ -n "${STATIC_FILE_NAME}" ] && [ "${STATIC_FILE_NAME}" != "dist" ];then
            cd ${DOCKER_DAEMON_WORKSPACE}
            mv ${STATIC_FILE_NAME} dist
            cd ..
            fi
            ;;
        java)
            # Detect Maven or Gradle project, copy corresponding JAR file
            if [ -f pom.xml ]; then
                # Maven project: copy from target directory
                cp -a ./target/${MAVEN_APP_NAME-"app"}*.jar ${DOCKER_DAEMON_WORKSPACE}
            elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
                # Gradle project: copy from build/libs directory
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
            # Only copy built binary to docker build directory, uniformly named app
            cp -a "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" "${DOCKER_DAEMON_WORKSPACE}/app"
            ;;
        *)
            echo "${Tip}No corresponding image initialization configuration found."
    esac
}


function docker_secret(){
    # Find current Dockerfile secret id and inject into docker build args
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
    # Execute Docker build workspace pre-preparation command
    # Execute in DOCKER_DAEMON_WORKSPACE directory, used to prepare dependency configuration files needed for build
    if [ -n "${DOCKER_WORKSPACE_PREPARE_CMD}" ]; then
        echo "${Info}Executing Docker workspace pre-preparation command..."
        echo "${Tip}Command content: ${DOCKER_WORKSPACE_PREPARE_CMD}"
        echo "${Tip}Execution directory: ${DOCKER_DAEMON_WORKSPACE}"

        # Execute user-defined pre-command
        eval "${DOCKER_WORKSPACE_PREPARE_CMD}"

        if [ $? -eq 0 ]; then
            echo "${Info}Workspace preparation command executed successfully"
            ls -lha
        else
            echo "${Error}Workspace preparation command failed, exiting build"
            exit 1
        fi
    fi
}

function docker_build_push(){

    build_init
    image_build_init
    cd "${DOCKER_DAEMON_WORKSPACE}"
    ls -lha

    # Execute workspace pre-preparation command
    docker_workspace_prepare

    # Handle custom Dockerfile
    if [ -n "${CUSTOM_DOCKERFILE}" ];then
        # Support custom Dockerfile path, prioritize CUSTOM_DOCKERFILE_PATH, otherwise use root directory Dockerfile
        local dockerfile_source="${CUSTOM_DOCKERFILE_PATH:-${CI_PROJECT_DIR}/Dockerfile}"
        rm -rf Dockerfile && cp "${dockerfile_source}" .
        # Dockerfile add image metadata information
        sed -ie '/^FROM.*base-image.*$/a\ARG CI_COMMIT_SHORT_SHA="develop"     CI_BUILD_DATE=""     APP_NAME="app"     CI_COMMIT_REF_NAME=""     CI_COMMIT_AUTHOR=""     CI_PROJECT_NAME=""\nLABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR}       CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA}       CI_BUILD_DATE=${CI_BUILD_DATE}       CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}       DOCKER_FILE_FORM="https://github.com/cdryzun/gitlab-ci-templates"       CI_PROJECT_NAME=${CI_PROJECT_NAME}\nENV APP=${APP_NAME}' Dockerfile
    fi

    if [ -e nginx.conf ] && [ "${PROJECT_TYPE}" == 'web' ];then
        sed -i "/RUN/iADD nginx.conf /etc/nginx/conf.d/nginx.conf" Dockerfile
    fi
    # Get current Dockerfile secret id
    docker_secret
    # Pull latest base image #58
    docker_base_pull_latest
    # Disable BuildKit for single-architecture builds (requires buildx plugin)
    echo """DOCKER_BUILDKIT=0 docker build ${DOCKER_SECRET_ARGS}  \
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
    echo "${Tip}Release image matched successfully, performing ReTag based on this image"
    docker pull "${RETAG_IMGAE_NAME}"
    docker tag "${RETAG_IMGAE_NAME}" "${DOCKER_IMAGE_NAME}"
    docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    docker push ${DOCKER_IMAGE_NAME} \
      && docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" \
      && docker rmi -f ${DOCKER_IMAGE_NAME} "${RETAG_IMGAE_NAME}" "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"
}

function auto_delete_tag(){
    echo "${Tip}Detected ${CI_COMMIT_REF_NAME} branch, executing Tag cleanup action, currently keeping latest ${PRD_CD_CREATE_TAG_NUM} Tags."
    for claen_tag in `glab release list ls|grep "${_CI_COMMIT_REF_NAME}-"|awk '{print $1}'|sort|head -n -${PRD_CD_CREATE_TAG_NUM}`;do
        glab release delete "$claen_tag" -y --with-tag
        echo "${Tip} Deleting Docker image: ${CRED}${IMG_NAME}:${claen_tag}${CEND}..."
        _PROJECT_NAME=$(echo `glab repo view|head -n 1|sed 's# / #%252F#g;s#name:##g'`)

        # Clean up registry images (Harbor API example)
        # Users can configure REGISTRY_CLEANUP_API variable to enable image cleanup
        # Example: REGISTRY_CLEANUP_API="https://harbor.example.com/api/v2.0"
        if [ -n "${REGISTRY_CLEANUP_API}" ] && [ -n "${REGISTRY_USER}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
            if curl -u ${REGISTRY_USER}:${REGISTRY_PASSWORD} -X 'DELETE' \
                "${REGISTRY_CLEANUP_API}/projects/${CI_PROJECT_NAME}/repositories/${_PROJECT_NAME}/artifacts/${claen_tag}/tags/${claen_tag}" \
                -H 'accept: application/json' 2>&1 | grep -q "errors"; then
                echo "${Tip} Image deletion failed, please check..."
            else
                echo "${Info} Image cleanup successful..."
            fi
        else
            echo "${Tip} REGISTRY_CLEANUP_API not configured, skipping image cleanup..."
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
            --ref ${CI_COMMIT_REF_NAME} --assets-links='[{\"name\":\"Project CD Charts URL\",\"url\":\"$(echo ${DEPLOY_REPO}| sed 's#\.git##g')/-/tree/${CI_COMMIT_REF_NAME}/${CI_PROJECT_NAME}\",\"link_type\":\"other\"}]'"|bash
    else
        echo "glab release create ${DOCKER_IMAGE_TAG} -F changelog.md \
            --ref ${CI_COMMIT_REF_NAME}"|bash
    fi
}


# If it is a python project and needs to be built into a whl package, upload the build result to nexus pip private server instead of building Docker image.
if [ ! -z "${BUILD_SHELL}" -a "${PROJECT_TYPE}" == "python" ];then
    # Execute build
    build_init
    echo "${Info}Executing ${PROJECT_TYPE} package build."

    # Upload results to nexus private server, standard directory is: dist
    for package in `ls ${PYPI_TARGET_PATH:-dist}/*.whl`;do
        pip install twine -i "${PYPI}" >/dev/null 2>&1
        twine upload -u ${NEXUS_USER} -p ${NEXUS_PASSWD} \
        --repository-url "${PYPI_PRIVATE}" "${package}"
    done

else
    if [ "${DOCKER_IMAGE_BUILD}" == "true" ];then
        if [ -n "${RETAG_IMGAE_NAME}" ] && [ "${RELEASE_RETAG_DISABLE}" != 'true' ] ;then
            # Execute docker image retag, no second build
            docker_retag_push
        else
            # Smart selection: single-architecture or multi-architecture build
            # If _multiarch.stable.sh is loaded and MULTIARCH_BUILD_ENABLE=true, use multi-architecture
            # Otherwise use original single-architecture build
            if declare -f smart_docker_build_push > /dev/null; then
                smart_docker_build_push
            else
                docker_build_push
            fi
        fi
    else
        echo "${Tip}Image build switch not enabled, skipping image build stage."
        if [ "${PRD_BUILD_CREATE_TAG}" == 'true' ];then
            echo "${Tip}Detected ${CI_COMMIT_REF_NAME} branch, executing create Tag action."
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
            auto_create_tag  # Automatically create repository Tag
            auto_delete_tag # And keep latest n Tags
        else
            build_init
        fi
    fi
fi
