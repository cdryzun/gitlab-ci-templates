#!/usr/bin/env bash
set -eo pipefail


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
                sed -i '/<finalName>/d' ${BUILD_MAVEN_POM_FILE} # Delete first to prevent conflicts
                if [ "${RELEASE_BUILD}" == 'true' ];then
                    sed -i "/<build>/a <finalName>${MAVEN_APP_NAME-"app"}-${CI_COMMIT_REF_NAME##v}<\/finalName>" ${BUILD_MAVEN_POM_FILE}
                else
                    sed -i "/<build>/a <finalName>${MAVEN_APP_NAME-"app"}<\/finalName>" ${BUILD_MAVEN_POM_FILE}
                fi
                shell_exec "${BUILD_SHELL-mvn clean package}"
            elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
                # Gradle project
                shell_exec "${BUILD_SHELL-gradle clean build -x test}"
            else
                echo "${Error}Maven or Gradle build file not found"
                exit 1
            fi
            ;;
        golang)
            # Go build: disable CGO, Linux/amd64; output name consistent with project name
            export CGO_ENABLED="${GO_CGO_ENABLED:-0}"
            export GOOS=linux
            export GOARCH="${GO_ARCH:-amd64}"
            # Apply GOPROXY if configured (supports private/mirror registries)
            if [ -n "${GO_GOPROXY}" ]; then
                export GOPROXY="${GO_GOPROXY}"
            fi
            # Apply GOPRIVATE if configured (bypass proxy/sumdb for private modules)
            if [ -n "${GO_GOPRIVATE}" ]; then
                export GOPRIVATE="${GO_GOPRIVATE}"
                export GONOSUMDB="${GO_GOPRIVATE}"
            fi
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
                cp -a ./build/libs/${MAVEN_APP_NAME-"app"}*.jar ${DOCKER_DAEMON_WORKSPACE}
            fi
            ;;
        python)
            mkdir -p ${DOCKER_DAEMON_WORKSPACE}
            cp -a ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}
            rm -rf ${DOCKER_DAEMON_WORKSPACE}/{.git,test} || true
            ;;
        golang)
            # Only copy built binary to docker build directory, uniformly named app
            cp -a "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" "${DOCKER_DAEMON_WORKSPACE}/app"
            ;;
        *)
            echo "${Tip}No corresponding image initialization configuration found."
    esac
}


function docker_workspace_prepare(){
    # Execute Docker build workspace pre-preparation command
    # Execute in DOCKER_DAEMON_WORKSPACE directory, used to prepare dependency configuration files needed for build
    if [ -n "${DOCKER_WORKSPACE_PREPARE_CMD}" ]; then
        echo "${Info}Executing Docker workspace pre-preparation command..."
        echo "${Tip}Command content: ${DOCKER_WORKSPACE_PREPARE_CMD}"
        echo "${Tip}Execution directory: ${DOCKER_DAEMON_WORKSPACE}"

        # Execute user-defined pre-command in a subshell for safety
        bash -euo pipefail -c "${DOCKER_WORKSPACE_PREPARE_CMD}"

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
    echo "${Info}Build workspace contents:"
    ls -lh | grep -v "^total"

    # Execute workspace pre-preparation command
    docker_workspace_prepare

    if [ ${CUSTOM_DOCKERFILE} ];then
        # Support custom Dockerfile path, prioritize CUSTOM_DOCKERFILE_PATH, otherwise use root directory Dockerfile
        local dockerfile_source="${CUSTOM_DOCKERFILE_PATH:-${CI_PROJECT_DIR}/Dockerfile}"
        rm -rf Dockerfile && cp "${dockerfile_source}" .
        # Dockerfile add image metadata information
        sed -ie '/^FROM.*base-image.*$/a\ARG CI_COMMIT_SHORT_SHA="develop"     CI_BUILD_DATE=""     APP_NAME="app"     CI_COMMIT_REF_NAME=""     CI_COMMIT_AUTHOR=""     CI_PROJECT_NAME=""\nLABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR}       CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA}       CI_BUILD_DATE=${CI_BUILD_DATE}       CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}       DOCKER_FILE_FORM="https://github.com/cdryzun/gitlab-ci-templates"       CI_PROJECT_NAME=${CI_PROJECT_NAME}\nENV APP=${APP_NAME}' Dockerfile
    fi

    if [ -e nginx.conf ] && [ "${PROJECT_TYPE}" == 'web' ];then
        sed -i "/RUN/iADD nginx.conf /etc/nginx/conf.d/nginx.conf" Dockerfile
    fi

    # Disable BuildKit for single-architecture builds (requires buildx plugin)
    echo "${Info}Building Docker image: ${DOCKER_IMAGE_NAME}"
    DOCKER_BUILDKIT=0 docker image build \
    -t "${DOCKER_IMAGE_NAME}" . \
    "${DOCKER_BUILD_FLAGS}" \
    --build-arg DOCKER_MIRROR_PREFIX="${DOCKER_MIRROR_PREFIX:-}" \
    --build-arg APP_NAME="${MAVEN_APP_NAME:-${CI_PROJECT_NAME}}" \
    --build-arg CI_COMMIT_SHORT_SHA="$CI_COMMIT_SHORT_SHA" \
    --build-arg CI_BUILD_DATE="$(date +%Y-%m-%d/%H:%M)" \
    --build-arg CI_PROJECT_NAME="${CI_PROJECT_NAME}" \
    --build-arg CI_COMMIT_AUTHOR="${CI_COMMIT_AUTHOR}" \
    --build-arg CI_COMMIT_REF_NAME="${CI_COMMIT_REF_NAME}" 2>&1 | grep -v "^Running in\|^Removing intermediate\|^ --->" || true

    # Add extra branch type tag (like latest, stable, main)
    docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    echo "${Info}Pushing Docker images..."
    # Push with clean output - filter repetitive "Waiting" messages
    docker push ${DOCKER_IMAGE_NAME} 2>&1 | grep -E "digest:|Pushed|Layer already exists|Error" || true
    docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" 2>&1 | grep -E "digest:|Pushed|Layer already exists|Error" || true
    docker rmi -f ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" 2>/dev/null || true
    echo "${Info}Docker images pushed successfully"
}


function docker_retag_push(){
    echo "${Tip}Release image matched successfully, performing ReTag based on this image"
    docker pull "${RETAG_IMGAE_NAME}" 2>&1 | grep -E "digest:|Downloaded|Layer already exists|Error" || true
    docker tag "${RETAG_IMGAE_NAME}" "${DOCKER_IMAGE_NAME}"
    # Add extra branch type tag (like latest, stable, main)
    docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    echo "${Info}Pushing Docker images..."
    docker push ${DOCKER_IMAGE_NAME} 2>&1 | grep -E "digest:|Pushed|Layer already exists|Error" || true
    docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" 2>&1 | grep -E "digest:|Pushed|Layer already exists|Error" || true
    docker rmi -f ${DOCKER_IMAGE_NAME} "${RETAG_IMGAE_NAME}" "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" 2>/dev/null || true
    echo "${Info}Docker images pushed successfully"
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
    echo "glab release create ${DOCKER_IMAGE_TAG} -F changelog.md \
        --ref ${CI_COMMIT_REF_NAME} --assets-links='[{\"name\":\"Project CD Charts URL\",\"url\":\"$(echo ${DEPLOY_REPO}| sed 's#\.git##g')/-/tree/${CI_COMMIT_REF_NAME}/${CI_PROJECT_NAME}\",\"link_type\":\"other\"}]'"|bash
}

if [ "${DOCKER_IMAGE_BUILD}" == "true" ];then
    if [ -n "${RETAG_IMGAE_NAME}" ] && [ "${RELEASE_RETAG_DISABLE}" != 'true' ] ;then
        # Execute docker image retag, no second build
        docker_retag_push
    else
        # Smart selection: single-architecture or multi-architecture build
        # If _multiarch.latest.sh is loaded and MULTIARCH_BUILD_ENABLE=true, use multi-architecture
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
