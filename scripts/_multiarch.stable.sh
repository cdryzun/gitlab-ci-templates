#!/usr/bin/env bash
# ============================================
# Multi-Architecture Build Extension Module
# Automatically loaded by build.latest.sh as utility library
# ============================================

# ============================================
# Initialize Docker Buildx
# ============================================
function init_buildx() {
    echo "${Info}Initializing Docker Buildx..."

    # Check Docker version
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    echo "${Tip}Docker server version: ${docker_version}"

    # Check if Buildx is available
    if ! docker buildx version &> /dev/null; then
        echo "${Warn}docker buildx command not available, attempting diagnosis and repair..."

        # Diagnostic information
        echo "${Tip}Docker version: ${docker_version}"
        echo "${Tip}Checking docker CLI plugin directories..."

        # Check plugin directories
        local plugin_dirs=(
            "/usr/local/lib/docker/cli-plugins"
            "/usr/lib/docker/cli-plugins"
            "/usr/libexec/docker/cli-plugins"
            "$HOME/.docker/cli-plugins"
        )

        local buildx_found=false
        for dir in "${plugin_dirs[@]}"; do
            if [ -f "${dir}/docker-buildx" ]; then
                echo "${Info}Found buildx plugin: ${dir}/docker-buildx"
                buildx_found=true

                # Ensure executable
                chmod +x "${dir}/docker-buildx" 2>/dev/null || true
            fi
        done

        if [ "${buildx_found}" = false ]; then
            echo "${Warn}docker-buildx plugin not found, attempting to extract from Docker container..."

            # Try to extract from Docker built-in buildx
            if docker info &> /dev/null; then
                # Create plugin directory
                mkdir -p /usr/libexec/docker/cli-plugins

                # Try to copy buildx (from Docker installation path)
                if [ -f /usr/libexec/docker/cli-plugins/docker-buildx ]; then
                    echo "${Info}Using system built-in buildx"
                else
                    echo "${Error}Unable to find or install docker buildx plugin"
                    echo "${Error}Please install docker-buildx-plugin in build image or use Docker version with buildx"
                    echo "${Tip}Solutions:"
                    echo "${Tip}  1. Add in CI image Dockerfile: RUN apk add docker-buildx (Alpine)"
                    echo "${Tip}  2. Or: RUN apt-get install -y docker-buildx-plugin (Debian/Ubuntu)"
                    echo "${Tip}  3. Or download binary from https://github.com/docker/buildx/releases"
                    exit 1
                fi
            fi
        fi

        # Check again
        if ! docker buildx version &> /dev/null; then
            echo "${Error}Docker Buildx still not available"
            echo "${Error}Please install docker-buildx plugin in CI build image"
            exit 1
        fi
    fi

    # Show buildx version
    echo "${Info}Buildx version: $(docker buildx version)"

    # Create or use multi-architecture builder
    local builder_name="${BUILDX_BUILDER_NAME:-multiarch-builder}"

    if ! docker buildx inspect "${builder_name}" &> /dev/null; then
        echo "${Info}Creating new builder: ${builder_name}"
        docker buildx create \
            --name "${builder_name}" \
            --driver "${BUILDX_DRIVER:-docker-container}" \
            --use
    else
        echo "${Info}Using existing builder: ${builder_name}"
        docker buildx use "${builder_name}"
    fi

    # Start builder (if not running)
    docker buildx inspect --bootstrap

    echo "${Info}Buildx initialization successful."
}

# ============================================
# Golang Multi-Architecture Build Initialization
# ============================================
function golang_multiarch_build_init() {
    echo "${Info}Initializing Golang multi-architecture build..."

    if [ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ]; then
        echo "${Info}Using Dockerfile mode for multi-architecture build (recommended)"
        echo "${Info}Skipping local compilation, will compile during Docker build stage"

        # Only copy source code to workspace (Dockerfile will handle compilation)
        mkdir -p ${DOCKER_DAEMON_WORKSPACE}

        # Copy necessary files
        echo "${Info}Copying source code to build workspace..."
        rsync -a --exclude='.git' --exclude='test' \
            ${CI_PROJECT_DIR}/ ${DOCKER_DAEMON_WORKSPACE}/ || \
        cp -r ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}/ 2>/dev/null || true

    elif [ "${GOLANG_MULTIARCH_MODE}" == "precompile" ]; then
        echo "${Info}Using precompile mode"

        # Pre-compile binaries for multiple architectures
        local architectures="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
        IFS=',' read -ra PLATFORMS <<< "$architectures"

        mkdir -p ${DOCKER_DAEMON_WORKSPACE}/binaries

        for platform in "${PLATFORMS[@]}"; do
            local os=$(echo $platform | cut -d'/' -f1)
            local arch=$(echo $platform | cut -d'/' -f2)
            local variant=$(echo $platform | cut -d'/' -f3)

            echo "${Info}Compiling ${platform} architecture..."

            # Set compilation environment variables
            export GOOS=${os}
            export GOARCH=${arch}
            export CGO_ENABLED="${GO_CGO_ENABLED:-0}"

            # Handle ARM variants
            if [ -n "${variant}" ]; then
                export GOARM="${variant//v/}"  # v7 -> 7
            fi

            # Compilation
            # File naming format consistent with Dockerfile: ${CI_PROJECT_NAME}-${os}-${arch}${variant}
            # e.g.: hysteria-linux-amd64, hysteria-linux-arm64, hysteria-linux-armv7
            local binary_name="${CI_PROJECT_NAME}-${os}-${arch}${variant}"

            if [ -n "${BUILD_SHELL}" ]; then
                # Use user-defined build script (e.g., build-ci.sh)
                echo "${Tip}Using custom build script: ${BUILD_SHELL}"
                echo "${Tip}Target platform: ${GOOS}/${GOARCH}"

                # Set output file name environment variable for user script
                export OUTPUT_NAME="${binary_name}"
                export OUTPUT_PATH="${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}"
                export TARGET_OS="${GOOS}"
                export TARGET_ARCH="${GOARCH}"

                # Execute user script
                sh -c "${BUILD_SHELL}"

                # Check output file and move to binaries directory
                # Check multiple possible output locations by priority
                local source_binary=""

                if [ -f "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" ]; then
                    # User script outputs directly to target location (used OUTPUT_PATH)
                    source_binary="ALREADY_IN_PLACE"
                    echo "${Tip}Binary file already in target location: ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}"
                elif [ -f "${CI_PROJECT_DIR}/${binary_name}" ]; then
                    # User script output to project directory, used OUTPUT_NAME
                    source_binary="${CI_PROJECT_DIR}/${binary_name}"
                elif [ -f "${CI_PROJECT_DIR}/../${binary_name}" ]; then
                    # User script output to project parent directory
                    source_binary="${CI_PROJECT_DIR}/../${binary_name}"
                elif [ -f "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" ]; then
                    # User script output to project name (no architecture suffix)
                    source_binary="${CI_PROJECT_DIR}/${CI_PROJECT_NAME}"
                elif [ -f "./${binary_name}" ]; then
                    # Current directory
                    source_binary="./${binary_name}"
                elif [ -f "../${binary_name}" ]; then
                    # Parent directory (relative path)
                    source_binary="../${binary_name}"
                fi

                # If not found yet, try searching
                if [ -z "${source_binary}" ]; then
                    echo "${Warn}Warning: Compilation output not found in expected locations, searching..."
                    # Search for most recently generated executable in current and parent directories
                    local found_binary=$(find . .. -maxdepth 1 -type f -name "${binary_name}" 2>/dev/null | head -n 1)
                    if [ -n "${found_binary}" ]; then
                        source_binary="${found_binary}"
                    fi
                fi

                # Move file to target location
                if [ "${source_binary}" = "ALREADY_IN_PLACE" ]; then
                    : # File already in correct location, no need to move
                elif [ -n "${source_binary}" ] && [ -f "${source_binary}" ]; then
                    echo "${Info}Found binary file: ${source_binary}"
                    mv "${source_binary}" "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}"
                else
                    echo "${Error}Error: Compilation complete but output file not found"
                    echo "${Error}Checked locations:"
                    echo "${Error}  - ${CI_PROJECT_DIR}/${binary_name}"
                    echo "${Error}  - ${CI_PROJECT_DIR}/../${binary_name}"
                    echo "${Error}  - ${CI_PROJECT_DIR}/${CI_PROJECT_NAME}"
                    echo "${Error}  - ./${binary_name}"
                    echo "${Error}  - ../${binary_name}"
                    echo "${Tip}Suggestion: Use OUTPUT_PATH environment variable in BUILD_SHELL to specify output path"
                    exit 1
                fi
            else
                # Default Go build command
                go build \
                    -ldflags "-s -w" \
                    -o "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" \
                    ./
            fi

            # Verify binary file
            if [ -f "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" ]; then
                echo "${Info}Compilation complete: ${binary_name}"

                # Show file info (file command may not be available)
                if command -v file >/dev/null 2>&1; then
                    echo "${Tip}File info: $(file ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name})"
                fi

                echo "${Tip}File size: $(du -h ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name} | awk '{print $1}')"
            else
                echo "${Error}Error: Compilation failed, binary file not generated"
                exit 1
            fi
        done

        # Show all compiled binary files
        echo "${Info}All compiled binary files:"
        ls -lh ${DOCKER_DAEMON_WORKSPACE}/binaries/
    else
        echo "${Error}Unknown GOLANG_MULTIARCH_MODE: ${GOLANG_MULTIARCH_MODE}"
        echo "${Error}Valid values: 'dockerfile', 'precompile'"
        exit 1
    fi
}

# ============================================
# Multi-Architecture Image Build and Push
# ============================================
function docker_buildx_push() {
    # Parse target platforms
    local platforms="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"

    echo "${Info}Starting multi-architecture image build"
    echo "${Tip}Target platforms: ${platforms}"
    echo "${Tip}Image name: ${DOCKER_IMAGE_NAME}"

    # Generate additional branch type tags (e.g., latest, stable, main)
    local extra_tag="${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    # Prepare build arguments
    local build_args=(
        --platform "${platforms}"
        --tag "${DOCKER_IMAGE_NAME}"
        --tag "${extra_tag}"
        --file "Dockerfile"
        --build-arg "CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA}"
        --build-arg "CI_BUILD_DATE=$(date +%Y-%m-%d/%H:%M)"
        --build-arg "CI_PROJECT_NAME=${CI_PROJECT_NAME}"
        --build-arg "CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR}"
        --build-arg "CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}"
        --build-arg "APP_NAME=${APP_NAME:-app}"
        --build-arg "PORT=${APP_PORT:-2025}"
    )

    # Add custom build arguments
    if [ -n "${GO_VERSION}" ]; then
        build_args+=(--build-arg "GO_VERSION=${GO_VERSION}")
    fi

    if [ -n "${GO_CGO_ENABLED}" ]; then
        build_args+=(--build-arg "CGO_ENABLED=${GO_CGO_ENABLED}")
    fi

    # Add extra build flags
    if [ -n "${DOCKER_BUILD_FLAGS}" ]; then
        build_args+=(${DOCKER_BUILD_FLAGS})
    fi

    # Cache configuration (optional)
    if [ "${BUILDX_CACHE_ENABLE}" == "true" ]; then
        build_args+=(
            --cache-from "type=registry,ref=${DOCKER_IMAGE_NAME}-cache"
            --cache-to "type=registry,ref=${DOCKER_IMAGE_NAME}-cache,mode=max"
        )
    fi

    # Execute build and push
    if [ "${DOCKER_IMAGE_PUSH:-true}" == "true" ]; then
        build_args+=(--push)
        echo "${Info}Building and pushing multi-architecture image..."
    else
        build_args+=(--load)
        echo "${Info}Building multi-architecture image only (no push)..."
    fi

    # Show full command (for debugging)
    if [ "${CI_DEBUG_TRACE}" == "true" ]; then
        echo "${Tip}Build command:"
        echo "docker buildx build ${build_args[@]} ."
    fi

    # Execute build
    docker buildx build "${build_args[@]}" .

    if [ $? -eq 0 ]; then
        echo "${Info}Multi-architecture image build successful!"

        # Show image information
        if [ "${DOCKER_IMAGE_PUSH:-true}" == "true" ]; then
            echo "${Info}View pushed image manifest:"
            docker buildx imagetools inspect "${DOCKER_IMAGE_NAME}" || true
        fi
    else
        echo "${Error}Multi-architecture build failed!"
        exit 1
    fi
}

# ============================================
# Multi-Architecture Build Main Flow (overrides single-architecture build_init)
# ============================================
function multiarch_build_init() {
    case "${PROJECT_TYPE}" in
        golang)
            golang_multiarch_build_init
            ;;
        web|java|python)
            # Other project types use original logic for now
            echo "${Info}Project type ${PROJECT_TYPE} does not support multi-architecture build yet, using single-architecture flow"
            build_init
            ;;
        *)
            echo "${Error}Unknown project type: ${PROJECT_TYPE}"
            exit 1
    esac
}

# ============================================
# Multi-Architecture Image Initialization (overrides single-architecture image_build_init)
# ============================================
function multiarch_image_build_init() {
    # For Golang multi-architecture build modes (dockerfile or precompile), skip this step
    # dockerfile mode: source code already copied
    # precompile mode: binary files already in binaries/ directory
    if [ "${PROJECT_TYPE}" == "golang" ] && \
       ([ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ] || [ "${GOLANG_MULTIARCH_MODE}" == "precompile" ]); then
        echo "${Info}Using multi-architecture build mode, skipping image initialization step"
        return 0
    fi

    # Other cases call original logic
    image_build_init
}

# ============================================
# Smart Selection: Single vs Multi-Architecture Build
# ============================================
function smart_docker_build_push() {
    if [ "${MULTIARCH_BUILD_ENABLE}" == "true" ]; then
        echo "${Info}Multi-architecture build enabled"
        echo "${Tip}Build platforms: ${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"

        # Multi-architecture build flow
        multiarch_build_init
        multiarch_image_build_init

        cd "${DOCKER_DAEMON_WORKSPACE}"
        ls -lha

        # Execute workspace pre-preparation command
        docker_workspace_prepare

        # Initialize Buildx
        init_buildx

        # Execute multi-architecture build
        docker_buildx_push
    else
        echo "${Info}Using single-architecture build (default)"

        # Call original single-architecture build flow
        build_init
        image_build_init

        cd "${DOCKER_DAEMON_WORKSPACE}"
        ls -lha

        # Execute workspace pre-preparation command
        docker_workspace_prepare

        # Handle custom Dockerfile
        if [ ${CUSTOM_DOCKERFILE} ];then
            # Support custom Dockerfile path, prioritize CUSTOM_DOCKERFILE_PATH, otherwise use root Dockerfile
            local dockerfile_source="${CUSTOM_DOCKERFILE_PATH:-${CI_PROJECT_DIR}/Dockerfile}"
            rm -rf Dockerfile && cp "${dockerfile_source}" .
            # Add image metadata to Dockerfile
            sed -ie '/^FROM.*base-image.*$/a\ARG CI_COMMIT_SHORT_SHA="develop"     CI_BUILD_DATE=""     APP_NAME="app"     CI_COMMIT_REF_NAME=""     CI_COMMIT_AUTHOR=""     CI_PROJECT_NAME=""\nLABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR}       CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA}       CI_BUILD_DATE=${CI_BUILD_DATE}       CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}       DOCKER_FILE_FORM="https://github.com/cdryzun/gitlab-ci-templates"       CI_PROJECT_NAME=${CI_PROJECT_NAME}\nENV APP=${APP_NAME}' Dockerfile
        fi

        if [ -e nginx.conf ] && [ "${PROJECT_TYPE}" == 'web' ];then
            sed -i "/RUN/iADD nginx.conf /etc/nginx/conf.d/nginx.conf" Dockerfile
        fi

        # Single-architecture Docker build (disable BuildKit to avoid buildx dependency)
        DOCKER_BUILDKIT=0 docker image build \
            -t "${DOCKER_IMAGE_NAME}" . \
            ${DOCKER_BUILD_FLAGS} \
            --build-arg CI_COMMIT_SHORT_SHA="$CI_COMMIT_SHORT_SHA" \
            --build-arg CI_BUILD_DATE="$(date +%Y-%m-%d/%H:%M)" \
            --build-arg CI_PROJECT_NAME="${CI_PROJECT_NAME}" \
            --build-arg CI_COMMIT_AUTHOR="${CI_COMMIT_AUTHOR}" \
            --build-arg CI_COMMIT_REF_NAME="${CI_COMMIT_REF_NAME}"

        # Add additional branch type tags (e.g., latest, stable, main)
        docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

        docker push ${DOCKER_IMAGE_NAME} \
          && docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" \
          && docker rmi -f ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"
    fi
}

echo "${Info}Multi-architecture build extension module loaded (MULTIARCH_BUILD_ENABLE=${MULTIARCH_BUILD_ENABLE:-false})"
