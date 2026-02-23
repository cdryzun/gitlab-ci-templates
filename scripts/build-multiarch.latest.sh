#!/usr/bin/env bash
set -eo

# ============================================
# 多架构构建脚本扩展
# 在原有 build.latest.sh 基础上增加多架构支持
# ============================================

# 加载工具类及模块脚本
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

# ============================================
# 多架构构建函数
# ============================================

# 初始化 Docker Buildx
function init_buildx() {
    echo "[INFO] Initializing Docker Buildx..."

    # 检查 Buildx 是否可用
    if ! docker buildx version &> /dev/null; then
        echo "[ERROR] Docker Buildx is not available. Please upgrade Docker to 19.03+."
        exit 1
    fi

    # 创建或使用多架构 builder
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

    # 启动 builder（如果未运行）
    docker buildx inspect --bootstrap

    echo "[SUCCESS] Buildx initialized successfully."
}

# 构建多架构镜像
function docker_buildx_push() {
    # 解析目标平台
    local platforms="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"

    echo "[INFO] Building multi-arch image for platforms: ${platforms}"
    echo "[INFO] Image name: ${DOCKER_IMAGE_NAME}"

    # 准备构建参数
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

    # 添加自定义构建参数
    if [ -n "${GO_VERSION}" ]; then
        build_args+=(--build-arg "GO_VERSION=${GO_VERSION}")
    fi

    if [ -n "${GO_CGO_ENABLED}" ]; then
        build_args+=(--build-arg "CGO_ENABLED=${GO_CGO_ENABLED}")
    fi

    # 添加额外的构建标志
    if [ -n "${DOCKER_BUILD_FLAGS}" ]; then
        build_args+=(${DOCKER_BUILD_FLAGS})
    fi

    # 缓存配置（可选）
    if [ "${BUILDX_CACHE_ENABLE}" == "true" ]; then
        build_args+=(
            --cache-from "type=registry,ref=${DOCKER_IMAGE_NAME}-cache"
            --cache-to "type=registry,ref=${DOCKER_IMAGE_NAME}-cache,mode=max"
        )
    fi

    # 执行构建并推送
    if [ "${DOCKER_IMAGE_PUSH}" == "true" ]; then
        build_args+=(--push)
        echo "[INFO] Building and pushing multi-arch image..."
    else
        build_args+=(--load)
        echo "[INFO] Building multi-arch image (local only)..."
    fi

    # 显示完整命令（调试用）
    if [ "${CI_DEBUG_TRACE}" == "true" ]; then
        echo "[DEBUG] Build command:"
        echo "docker buildx build ${build_args[@]} ${DOCKER_DAEMON_WORKSPACE}"
    fi

    # 执行构建
    cd "${DOCKER_DAEMON_WORKSPACE}"
    docker buildx build "${build_args[@]}" .

    if [ $? -eq 0 ]; then
        echo "[SUCCESS] Multi-arch image built successfully!"

        # 显示镜像信息
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
# Golang 多架构构建初始化
# ============================================

function golang_multiarch_build_init() {
    echo "[INFO] Initializing Golang multi-arch build..."

    # 方案选择：
    # 1. 如果使用多架构 Dockerfile（推荐），跳过本地编译
    # 2. 如果使用预编译方案，在这里编译多个架构的二进制

    if [ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ]; then
        echo "[INFO] Using Dockerfile-based multi-arch build (recommended)"
        echo "[INFO] Skipping local compilation, will compile in Docker build stage"

        # 仅复制源代码到工作区（Dockerfile 会处理编译）
        mkdir -p ${DOCKER_DAEMON_WORKSPACE}

        # 复制必要文件
        cp -r ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}/ || true
        cp -r ${CI_PROJECT_DIR}/.* ${DOCKER_DAEMON_WORKSPACE}/ 2>/dev/null || true

        # 清理不必要的文件
        rm -rf ${DOCKER_DAEMON_WORKSPACE}/.git
        rm -rf ${DOCKER_DAEMON_WORKSPACE}/test

    elif [ "${GOLANG_MULTIARCH_MODE}" == "precompile" ]; then
        echo "[INFO] Using pre-compilation mode"

        # 预编译多个架构的二进制
        local architectures="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
        IFS=',' read -ra PLATFORMS <<< "$architectures"

        mkdir -p ${DOCKER_DAEMON_WORKSPACE}/binaries

        for platform in "${PLATFORMS[@]}"; do
            local os=$(echo $platform | cut -d'/' -f1)
            local arch=$(echo $platform | cut -d'/' -f2)
            local variant=$(echo $platform | cut -d'/' -f3)

            echo "[INFO] Compiling for ${platform}..."

            # 设置编译环境变量
            export GOOS=${os}
            export GOARCH=${arch}
            export CGO_ENABLED="${GO_CGO_ENABLED:-0}"

            # 处理 ARM 变体
            if [ -n "${variant}" ]; then
                export GOARM="${variant//v/}"  # v7 -> 7
            fi

            # 编译
            local binary_name="${CI_PROJECT_NAME}-${os}-${arch}${variant:+-${variant}}"

            if [ -n "${BUILD_SHELL}" ]; then
                sh -c "${BUILD_SHELL}"
                # 假设用户脚本输出到正确位置
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
# 主流程函数（覆盖原有函数）
# ============================================

function build_init() {
    case "${PROJECT_TYPE}" in
        golang)
            if [ "${MULTIARCH_BUILD_ENABLE}" == "true" ]; then
                golang_multiarch_build_init
            else
                # 回退到原有的单架构构建
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

                # 复制二进制到 Docker 工作区
                mkdir -p ${DOCKER_DAEMON_WORKSPACE}
                cp -a "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" "${DOCKER_DAEMON_WORKSPACE}/app"
            fi
            ;;
        web|java|python)
            # 调用原有的 build_init 逻辑（保持向后兼容）
            source build.latest.sh
            build_init
            ;;
        *)
            echo "[WARNING] Unknown project type: ${PROJECT_TYPE}"
            shell_exec "${BUILD_SHELL:-echo 'No build command specified'}"
    esac
}

function image_build_init() {
    # 对于 Golang 多架构 Dockerfile 模式，跳过此步骤
    if [ "${PROJECT_TYPE}" == "golang" ] && \
       [ "${MULTIARCH_BUILD_ENABLE}" == "true" ] && \
       [ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ]; then
        echo "[INFO] Using Dockerfile-based build, skipping image_build_init"
        return 0
    fi

    # 其他项目类型调用原有逻辑
    source build.latest.sh
    image_build_init
}

# ============================================
# 主执行流程
# ============================================

function main() {
    echo "=========================================="
    echo "  Multi-Architecture Build Pipeline"
    echo "=========================================="
    echo "Project Type: ${PROJECT_TYPE}"
    echo "Multi-Arch Enabled: ${MULTIARCH_BUILD_ENABLE:-false}"
    echo "Platforms: ${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
    echo "=========================================="

    # 1. 项目编译初始化
    build_init

    # 2. 镜像构建初始化
    image_build_init

    # 3. Docker 工作区准备
    if [ -n "${DOCKER_WORKSPACE_PREPARE_CMD}" ]; then
        echo "[INFO] Executing workspace prepare command..."
        cd ${DOCKER_DAEMON_WORKSPACE}
        eval "${DOCKER_WORKSPACE_PREPARE_CMD}"
        cd -
    fi

    # 4. 执行镜像构建
    if [ "${DOCKER_IMAGE_BUILD}" == "true" ]; then
        if [ "${MULTIARCH_BUILD_ENABLE}" == "true" ]; then
            # 多架构构建流程
            init_buildx
            docker_buildx_push
        else
            # 单架构构建流程（原有逻辑）
            source build.latest.sh
            docker_build_push
        fi
    else
        echo "[INFO] Docker image build is disabled (DOCKER_IMAGE_BUILD=${DOCKER_IMAGE_BUILD})"
    fi

    echo "[SUCCESS] Build pipeline completed!"
}

# 执行主流程
main
