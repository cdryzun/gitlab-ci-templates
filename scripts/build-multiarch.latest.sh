#!/usr/bin/env bash
set -eo

# ============================================
# Multi-architecture build script extension
# Adds multi-architecture support on top of original build.latest.sh
# ============================================

# Load utility classes and module scripts
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

# ============================================
# Multi-architecture build functions
# ============================================

# Initialize Docker Buildx
function init_buildx() {
    echo "[INFO] Initializing Docker Buildx..."

    # Check if Buildx is available
    if ! docker buildx version &> /dev/null; then
        echo "[ERROR] Docker Buildx is not available. Please upgrade Docker to 19.03+."
        exit 1
    fi

    # Create or use multi-architecture builder
    local builder_name="${BUILDX_BUILDER_NAME:-multiarch-builder}"

    if ! docker buildx inspect "${builder_name}" &> /dev/null; then
        echo "[INFO] Creating new builder: ${builder_name}"
        docker buildx create \
            --name "${builder_name}" \
            --driver "${BUILDX_DRIVER:-docker-container}" \
            --use
    else
        echo "[INFO] Using existing builder: ${builder_name}"
        docker buildx use "${builder_name}"
    fi

    # Start builder (if not running)
    docker buildx inspect --bootstrap

    echo "[SUCCESS] Buildx initialized successfully."
}

# Build multi-architecture image
function docker_buildx_push() {
    # Parse target platforms
    local platforms="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"

    echo "[INFO] Building multi-arch image for platforms: ${platforms}"
    echo "[INFO] Image name: ${DOCKER_IMAGE_NAME}"

    # Prepare build arguments
    local build_args=(
        --platform "${platforms}"
        --tag "${DOCKER_IMAGE_NAME}"
        --file "${DOCKER_DAEMON_WORKSPACE}/Dockerfile"
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
    if [ "${DOCKER_IMAGE_PUSH}" == "true" ]; then
        build_args+=(--push)
        echo "[INFO] Building and pushing multi-arch image..."
    else
        build_args+=(--load)
        echo "[INFO] Building multi-arch image (local only)..."
    fi

    # Display full command (for debugging)
    if [ "${CI_DEBUG_TRACE}" == "true" ]; then
        echo "[DEBUG] Build command:"
        echo "docker buildx build ${build_args[@]} ${DOCKER_DAEMON_WORKSPACE}"
    fi

    # Execute build
    cd "${DOCKER_DAEMON_WORKSPACE}"
    docker buildx build "${build_args[@]}" .

    if [ $? -eq 0 ]; then
        echo "[SUCCESS] Multi-arch image built successfully!"

        # Display image information
        if [ "${DOCKER_IMAGE_PUSH}" == "true" ]; then
            echo "[INFO] Inspecting pushed manifest:"
            docker buildx imagetools inspect "${DOCKER_IMAGE_NAME}"
        fi
    else
        echo "[ERROR] Multi-arch build failed!"
        exit 1
    fi
}

# ============================================
# Golang multi-architecture build initialization
# ============================================

function golang_multiarch_build_init() {
    echo "[INFO] Initializing Golang multi-arch build..."

    # Option selection:
    # 1. If using multi-architecture Dockerfile (recommended), skip local compilation
    # 2. If using pre-compilation approach, compile binaries for multiple architectures here

    if [ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ]; then
        echo "[INFO] Using Dockerfile-based multi-arch build (recommended)"
        echo "[INFO] Skipping local compilation, will compile in Docker build stage"

        # Only copy source code to workspace (Dockerfile will handle compilation)
        mkdir -p ${DOCKER_DAEMON_WORKSPACE}

        # Copy necessary files
        cp -r ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}/ || true
        cp -r ${CI_PROJECT_DIR}/.* ${DOCKER_DAEMON_WORKSPACE}/ 2>/dev/null || true

        # Clean up unnecessary files
        rm -rf ${DOCKER_DAEMON_WORKSPACE}/.git
        rm -rf ${DOCKER_DAEMON_WORKSPACE}/test

    elif [ "${GOLANG_MULTIARCH_MODE}" == "precompile" ]; then
        echo "[INFO] Using pre-compilation mode"

        # Pre-compile binaries for multiple architectures
        local architectures="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
        IFS=',' read -ra PLATFORMS <<< "$architectures"

        mkdir -p ${DOCKER_DAEMON_WORKSPACE}/binaries

        for platform in "${PLATFORMS[@]}"; do
            local os=$(echo $platform | cut -d'/' -f1)
            local arch=$(echo $platform | cut -d'/' -f2)
            local variant=$(echo $platform | cut -d'/' -f3)

            echo "[INFO] Compiling for ${platform}..."

            # Set compilation environment variables
            export GOOS=${os}
            export GOARCH=${arch}
            export CGO_ENABLED="${GO_CGO_ENABLED:-0}"

            # Handle ARM variants
            if [ -n "${variant}" ]; then
                export GOARM="${variant//v/}"  # v7 -> 7
            fi

            # Compile
            local binary_name="${CI_PROJECT_NAME}-${os}-${arch}${variant:+-${variant}}"

            if [ -n "${BUILD_SHELL}" ]; then
                sh -c "${BUILD_SHELL}"
                # Assume user script outputs to correct location
            else
                go build \
                    -ldflags "-s -w" \
                    -o "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" \
                    ./
            fi

            echo "[SUCCESS] Compiled ${binary_name} ($(file ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}))"
        done
    else
        echo "[ERROR] Unknown GOLANG_MULTIARCH_MODE: ${GOLANG_MULTIARCH_MODE}"
        echo "[ERROR] Valid values: 'dockerfile', 'precompile'"
        exit 1
    fi
}

# ============================================
# Main workflow functions (override original functions)
# ============================================

function build_init() {
    case "${PROJECT_TYPE}" in
        golang)
            if [ "${MULTIARCH_BUILD_ENABLE}" == "true" ]; then
                golang_multiarch_build_init
            else
                # Fallback to original single-architecture build
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

                # Copy binary to Docker workspace
                mkdir -p ${DOCKER_DAEMON_WORKSPACE}
                cp -a "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" "${DOCKER_DAEMON_WORKSPACE}/app"
            fi
            ;;
        web|java|python)
            # Call original build_init logic (maintain backward compatibility)
            source build.latest.sh
            build_init
            ;;
        *)
            echo "[WARNING] Unknown project type: ${PROJECT_TYPE}"
            shell_exec "${BUILD_SHELL:-echo 'No build command specified'}"
    esac
}

function image_build_init() {
    # Skip this step for Golang multi-architecture Dockerfile mode
    if [ "${PROJECT_TYPE}" == "golang" ] && \
       [ "${MULTIARCH_BUILD_ENABLE}" == "true" ] && \
       [ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ]; then
        echo "[INFO] Using Dockerfile-based build, skipping image_build_init"
        return 0
    fi

    # Call original logic for other project types
    source build.latest.sh
    image_build_init
}

# ============================================
# Main execution flow
# ============================================

function main() {
    echo "=========================================="
    echo "  Multi-Architecture Build Pipeline"
    echo "=========================================="
    echo "Project Type: ${PROJECT_TYPE}"
    echo "Multi-Arch Enabled: ${MULTIARCH_BUILD_ENABLE:-false}"
    echo "Platforms: ${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
    echo "=========================================="

    # 1. Project compilation initialization
    build_init

    # 2. Image build initialization
    image_build_init

    # 3. Docker workspace preparation
    if [ -n "${DOCKER_WORKSPACE_PREPARE_CMD}" ]; then
        echo "[INFO] Executing workspace prepare command..."
        cd ${DOCKER_DAEMON_WORKSPACE}
        eval "${DOCKER_WORKSPACE_PREPARE_CMD}"
        cd -
    fi

    # 4. Execute image build
    if [ "${DOCKER_IMAGE_BUILD}" == "true" ]; then
        if [ "${MULTIARCH_BUILD_ENABLE}" == "true" ]; then
            # Multi-architecture build process
            init_buildx
            docker_buildx_push
        else
            # Single-architecture build process (original logic)
            source build.latest.sh
            docker_build_push
        fi
    else
        echo "[INFO] Docker image build is disabled (DOCKER_IMAGE_BUILD=${DOCKER_IMAGE_BUILD})"
    fi

    echo "[SUCCESS] Build pipeline completed!"
}

# Execute main flow
main
