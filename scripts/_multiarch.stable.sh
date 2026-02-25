#!/usr/bin/env bash
# ============================================
# 多架构构建扩展模块
# 作为工具库被 build.latest.sh 自动加载
# ============================================

# ============================================
# 初始化 Docker Buildx
# ============================================
function init_buildx() {
    echo "${Info}初始化 Docker Buildx..."

    # 检查 Docker 版本
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    echo "${Tip}Docker 服务端版本: ${docker_version}"

    # 检查 Buildx 是否可用
    if ! docker buildx version &> /dev/null; then
        echo "${Warn}docker buildx 命令不可用，尝试诊断和修复..."

        # 诊断信息
        echo "${Tip}Docker 版本: ${docker_version}"
        echo "${Tip}检查 docker CLI 插件目录..."

        # 检查插件目录
        local plugin_dirs=(
            "/usr/local/lib/docker/cli-plugins"
            "/usr/lib/docker/cli-plugins"
            "/usr/libexec/docker/cli-plugins"
            "$HOME/.docker/cli-plugins"
        )

        local buildx_found=false
        for dir in "${plugin_dirs[@]}"; do
            if [ -f "${dir}/docker-buildx" ]; then
                echo "${Info}找到 buildx 插件: ${dir}/docker-buildx"
                buildx_found=true

                # 确保可执行
                chmod +x "${dir}/docker-buildx" 2>/dev/null || true
            fi
        done

        if [ "${buildx_found}" = false ]; then
            echo "${Warn}未找到 docker-buildx 插件，尝试从 Docker 容器中提取..."

            # 尝试从 Docker 内置 buildx 提取
            if docker info &> /dev/null; then
                # 创建插件目录
                mkdir -p /usr/libexec/docker/cli-plugins

                # 尝试复制 buildx（从 Docker 安装路径）
                if [ -f /usr/libexec/docker/cli-plugins/docker-buildx ]; then
                    echo "${Info}使用系统内置 buildx"
                else
                    echo "${Error}无法找到或安装 docker buildx 插件"
                    echo "${Error}请在构建镜像中安装 docker-buildx-plugin 或使用包含 buildx 的 Docker 版本"
                    echo "${Tip}解决方案："
                    echo "${Tip}  1. 在 CI 镜像 Dockerfile 中添加: RUN apk add docker-buildx (Alpine)"
                    echo "${Tip}  2. 或: RUN apt-get install -y docker-buildx-plugin (Debian/Ubuntu)"
                    echo "${Tip}  3. 或从 https://github.com/docker/buildx/releases 下载二进制文件"
                    exit 1
                fi
            fi
        fi

        # 再次检查
        if ! docker buildx version &> /dev/null; then
            echo "${Error}Docker Buildx 仍然不可用"
            echo "${Error}请在 CI 构建镜像中安装 docker-buildx 插件"
            exit 1
        fi
    fi

    # 显示 buildx 版本
    echo "${Info}Buildx 版本: $(docker buildx version)"

    # 创建或使用多架构 builder
    local builder_name="${BUILDX_BUILDER_NAME:-multiarch-builder}"

    if ! docker buildx inspect "${builder_name}" &> /dev/null; then
        echo "${Info}创建新的 builder: ${builder_name}"
        docker buildx create \
            --name "${builder_name}" \
            --driver "${BUILDX_DRIVER:-docker-container}" \
            --use
    else
        echo "${Info}使用现有 builder: ${builder_name}"
        docker buildx use "${builder_name}"
    fi

    # 启动 builder（如果未运行）
    docker buildx inspect --bootstrap

    echo "${Info}Buildx 初始化成功。"
}

# ============================================
# Golang 多架构构建初始化
# ============================================
function golang_multiarch_build_init() {
    echo "${Info}初始化 Golang 多架构构建..."

    if [ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ]; then
        echo "${Info}使用 Dockerfile 模式进行多架构构建（推荐）"
        echo "${Info}跳过本地编译，将在 Docker 构建阶段编译"

        # 仅复制源代码到工作区（Dockerfile 会处理编译）
        mkdir -p ${DOCKER_DAEMON_WORKSPACE}

        # 复制必要文件
        echo "${Info}复制源代码到构建工作区..."
        rsync -a --exclude='.git' --exclude='test' \
            ${CI_PROJECT_DIR}/ ${DOCKER_DAEMON_WORKSPACE}/ || \
        cp -r ${CI_PROJECT_DIR}/* ${DOCKER_DAEMON_WORKSPACE}/ 2>/dev/null || true

    elif [ "${GOLANG_MULTIARCH_MODE}" == "precompile" ]; then
        echo "${Info}使用预编译模式"

        # 预编译多个架构的二进制
        local architectures="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
        IFS=',' read -ra PLATFORMS <<< "$architectures"

        mkdir -p ${DOCKER_DAEMON_WORKSPACE}/binaries

        for platform in "${PLATFORMS[@]}"; do
            local os=$(echo $platform | cut -d'/' -f1)
            local arch=$(echo $platform | cut -d'/' -f2)
            local variant=$(echo $platform | cut -d'/' -f3)

            echo "${Info}编译 ${platform} 架构..."

            # 设置编译环境变量
            export GOOS=${os}
            export GOARCH=${arch}
            export CGO_ENABLED="${GO_CGO_ENABLED:-0}"

            # 处理 ARM 变体
            if [ -n "${variant}" ]; then
                export GOARM="${variant//v/}"  # v7 -> 7
            fi

            # 编译
            # 文件命名格式与 Dockerfile 保持一致: ${CI_PROJECT_NAME}-${os}-${arch}${variant}
            # 例如: hysteria-linux-amd64, hysteria-linux-arm64, hysteria-linux-armv7
            local binary_name="${CI_PROJECT_NAME}-${os}-${arch}${variant}"

            if [ -n "${BUILD_SHELL}" ]; then
                # 使用用户自定义的构建脚本（如 build-ci.sh）
                echo "${Tip}使用自定义构建脚本: ${BUILD_SHELL}"
                echo "${Tip}目标平台: ${GOOS}/${GOARCH}"

                # 设置输出文件名环境变量，供用户脚本使用
                export OUTPUT_NAME="${binary_name}"
                export OUTPUT_PATH="${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}"
                export TARGET_OS="${GOOS}"
                export TARGET_ARCH="${GOARCH}"

                # 执行用户脚本
                sh -c "${BUILD_SHELL}"

                # 检查输出文件并移动到 binaries 目录
                # 按优先级检查多个可能的输出位置
                local source_binary=""

                if [ -f "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" ]; then
                    # 用户脚本直接输出到目标位置（使用了 OUTPUT_PATH）
                    source_binary="ALREADY_IN_PLACE"
                    echo "${Tip}二进制文件已在目标位置: ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}"
                elif [ -f "${CI_PROJECT_DIR}/${binary_name}" ]; then
                    # 用户脚本输出到项目目录，使用了 OUTPUT_NAME
                    source_binary="${CI_PROJECT_DIR}/${binary_name}"
                elif [ -f "${CI_PROJECT_DIR}/../${binary_name}" ]; then
                    # 用户脚本输出到项目父目录
                    source_binary="${CI_PROJECT_DIR}/../${binary_name}"
                elif [ -f "${CI_PROJECT_DIR}/${CI_PROJECT_NAME}" ]; then
                    # 用户脚本输出到项目名（无架构后缀）
                    source_binary="${CI_PROJECT_DIR}/${CI_PROJECT_NAME}"
                elif [ -f "./${binary_name}" ]; then
                    # 当前目录
                    source_binary="./${binary_name}"
                elif [ -f "../${binary_name}" ]; then
                    # 父目录（相对路径）
                    source_binary="../${binary_name}"
                fi

                # 如果还没找到，尝试搜索
                if [ -z "${source_binary}" ]; then
                    echo "${Warn}警告: 未在预期位置找到编译输出，尝试搜索..."
                    # 搜索当前目录和父目录中最近生成的可执行文件
                    local found_binary=$(find . .. -maxdepth 1 -type f -name "${binary_name}" 2>/dev/null | head -n 1)
                    if [ -n "${found_binary}" ]; then
                        source_binary="${found_binary}"
                    fi
                fi

                # 移动文件到目标位置
                if [ "${source_binary}" = "ALREADY_IN_PLACE" ]; then
                    : # 文件已在正确位置，无需移动
                elif [ -n "${source_binary}" ] && [ -f "${source_binary}" ]; then
                    echo "${Info}找到二进制文件: ${source_binary}"
                    mv "${source_binary}" "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}"
                else
                    echo "${Error}错误: 编译完成但未找到输出文件"
                    echo "${Error}已检查位置:"
                    echo "${Error}  - ${CI_PROJECT_DIR}/${binary_name}"
                    echo "${Error}  - ${CI_PROJECT_DIR}/../${binary_name}"
                    echo "${Error}  - ${CI_PROJECT_DIR}/${CI_PROJECT_NAME}"
                    echo "${Error}  - ./${binary_name}"
                    echo "${Error}  - ../${binary_name}"
                    echo "${Tip}建议: 在 BUILD_SHELL 中使用 OUTPUT_PATH 环境变量指定输出路径"
                    exit 1
                fi
            else
                # 默认 Go 构建命令
                go build \
                    -ldflags "-s -w" \
                    -o "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" \
                    ./
            fi

            # 验证二进制文件
            if [ -f "${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name}" ]; then
                echo "${Info}编译完成: ${binary_name}"

                # 显示文件信息（file 命令可能不可用）
                if command -v file >/dev/null 2>&1; then
                    echo "${Tip}文件信息: $(file ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name})"
                fi

                echo "${Tip}文件大小: $(du -h ${DOCKER_DAEMON_WORKSPACE}/binaries/${binary_name} | awk '{print $1}')"
            else
                echo "${Error}错误: 编译失败，未生成二进制文件"
                exit 1
            fi
        done

        # 显示所有编译的二进制文件
        echo "${Info}所有编译的二进制文件:"
        ls -lh ${DOCKER_DAEMON_WORKSPACE}/binaries/
    else
        echo "${Error}未知的 GOLANG_MULTIARCH_MODE: ${GOLANG_MULTIARCH_MODE}"
        echo "${Error}有效值: 'dockerfile', 'precompile'"
        exit 1
    fi
}

# ============================================
# 多架构镜像构建和推送
# ============================================
function docker_buildx_push() {
    # 解析目标平台
    local platforms="${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"

    echo "${Info}开始构建多架构镜像"
    echo "${Tip}目标平台: ${platforms}"
    echo "${Tip}镜像名称: ${DOCKER_IMAGE_NAME}"

    # 生成额外的分支类型标签 (如 latest, stable, main)
    local extra_tag="${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

    # 准备构建参数
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
    if [ "${DOCKER_IMAGE_PUSH:-true}" == "true" ]; then
        build_args+=(--push)
        echo "${Info}构建并推送多架构镜像..."
    else
        build_args+=(--load)
        echo "${Info}仅构建多架构镜像（不推送）..."
    fi

    # 显示完整命令（调试用）
    if [ "${CI_DEBUG_TRACE}" == "true" ]; then
        echo "${Tip}构建命令:"
        echo "docker buildx build ${build_args[@]} ."
    fi

    # 执行构建
    docker buildx build "${build_args[@]}" .

    if [ $? -eq 0 ]; then
        echo "${Info}多架构镜像构建成功!"

        # 显示镜像信息
        if [ "${DOCKER_IMAGE_PUSH:-true}" == "true" ]; then
            echo "${Info}查看推送的镜像 manifest:"
            docker buildx imagetools inspect "${DOCKER_IMAGE_NAME}" || true
        fi
    else
        echo "${Error}多架构构建失败!"
        exit 1
    fi
}

# ============================================
# 多架构构建主流程（覆盖单架构 build_init）
# ============================================
function multiarch_build_init() {
    case "${PROJECT_TYPE}" in
        golang)
            golang_multiarch_build_init
            ;;
        web|java|python)
            # 其他项目类型暂时使用原有逻辑
            echo "${Info}项目类型 ${PROJECT_TYPE} 暂不支持多架构构建，使用单架构流程"
            build_init
            ;;
        *)
            echo "${Error}未知项目类型: ${PROJECT_TYPE}"
            exit 1
    esac
}

# ============================================
# 多架构镜像初始化（覆盖单架构 image_build_init）
# ============================================
function multiarch_image_build_init() {
    # 对于 Golang 多架构构建模式（dockerfile 或 precompile），跳过此步骤
    # dockerfile 模式：源代码已复制
    # precompile 模式：二进制文件已在 binaries/ 目录
    if [ "${PROJECT_TYPE}" == "golang" ] && \
       ([ "${GOLANG_MULTIARCH_MODE}" == "dockerfile" ] || [ "${GOLANG_MULTIARCH_MODE}" == "precompile" ]); then
        echo "${Info}使用多架构构建模式，跳过镜像初始化步骤"
        return 0
    fi

    # 其他情况调用原有逻辑
    image_build_init
}

# ============================================
# 智能选择：单架构 vs 多架构构建
# ============================================
function smart_docker_build_push() {
    if [ "${MULTIARCH_BUILD_ENABLE}" == "true" ]; then
        echo "${Info}多架构构建已启用"
        echo "${Tip}构建平台: ${DOCKER_BUILD_PLATFORMS:-linux/amd64,linux/arm64}"

        # 多架构构建流程
        multiarch_build_init
        multiarch_image_build_init

        cd "${DOCKER_DAEMON_WORKSPACE}"
        ls -lha

        # 执行工作区前置准备命令
        docker_workspace_prepare

        # 初始化 Buildx
        init_buildx

        # 执行多架构构建
        docker_buildx_push
    else
        echo "${Info}使用单架构构建（默认）"

        # 调用原有的单架构构建流程
        build_init
        image_build_init

        cd "${DOCKER_DAEMON_WORKSPACE}"
        ls -lha

        # 执行工作区前置准备命令
        docker_workspace_prepare

        # 处理自定义 Dockerfile
        if [ ${CUSTOM_DOCKERFILE} ];then
            # 支持自定义 Dockerfile 路径，优先使用 CUSTOM_DOCKERFILE_PATH，否则使用根目录的 Dockerfile
            local dockerfile_source="${CUSTOM_DOCKERFILE_PATH:-${CI_PROJECT_DIR}/Dockerfile}"
            rm -rf Dockerfile && cp "${dockerfile_source}" .
            # Dockerfile 添加 image 元数据信息
            sed -ie '/^FROM.*base-image.*$/a\ARG CI_COMMIT_SHORT_SHA="develop"     CI_BUILD_DATE=""     APP_NAME="app"     CI_COMMIT_REF_NAME=""     CI_COMMIT_AUTHOR=""     CI_PROJECT_NAME=""\nLABEL CI_COMMIT_AUTHOR=${CI_COMMIT_AUTHOR}       CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA}       CI_BUILD_DATE=${CI_BUILD_DATE}       CI_COMMIT_REF_NAME=${CI_COMMIT_REF_NAME}       DOCKER_FILE_FORM="https://github.com/cdryzun/gitlab-ci-templates"       CI_PROJECT_NAME=${CI_PROJECT_NAME}\nENV APP=${APP_NAME}' Dockerfile
        fi

        if [ -e nginx.conf ] && [ "${PROJECT_TYPE}" == 'web' ];then
            sed -i "/RUN/iADD nginx.conf /etc/nginx/conf.d/nginx.conf" Dockerfile
        fi

        # 单架构 Docker 构建
        docker image build \
            -t "${DOCKER_IMAGE_NAME}" . \
            ${DOCKER_BUILD_FLAGS} \
            --build-arg CI_COMMIT_SHORT_SHA="$CI_COMMIT_SHORT_SHA" \
            --build-arg CI_BUILD_DATE="$(date +%Y-%m-%d/%H:%M)" \
            --build-arg CI_PROJECT_NAME="${CI_PROJECT_NAME}" \
            --build-arg CI_COMMIT_AUTHOR="${CI_COMMIT_AUTHOR}" \
            --build-arg CI_COMMIT_REF_NAME="${CI_COMMIT_REF_NAME}"

        # 添加额外的分支类型标签 (如 latest, stable, main)
        docker tag ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"

        docker push ${DOCKER_IMAGE_NAME} \
          && docker push "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}" \
          && docker rmi -f ${DOCKER_IMAGE_NAME} "${DOCKER_IMAGE_NAME%:*}:${BRANCH_TYPE_LIST[${REMOTE_BRANCH}]}"
    fi
}

echo "${Info}多架构构建扩展模块已加载 (MULTIARCH_BUILD_ENABLE=${MULTIARCH_BUILD_ENABLE:-false})"
