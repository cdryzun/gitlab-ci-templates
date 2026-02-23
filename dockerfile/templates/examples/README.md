# Dockerfile 工作区前置命令使用示例

本目录包含使用 `DOCKER_WORKSPACE_PREPARE_CMD` 变量的实际示例。

## 示例列表

### 1. web-multi-config.gitlab-ci.yml

**场景：** Web 应用需要准备多个配置文件和 SSL 证书

**适用于：**
- 需要多个 Nginx 配置文件
- 需要 SSL/TLS 证书
- 需要额外的静态资源文件

**关键特性：**
- 复制多个 Nginx 配置文件
- 准备 SSL 证书并设置正确权限
- 创建必要的目录结构

**使用方法：**
```bash
# 复制示例到项目
cp web-multi-config.gitlab-ci.yml your-project/.gitlab-ci.yml

# 调整项目结构以匹配示例中的说明
mkdir -p config/nginx config/ssl
```

---

### 2. web-dynamic-config.gitlab-ci.yml

**场景：** 根据分支/环境动态选择配置文件

**适用于：**
- 多环境部署（dev/sit/prd）
- 需要根据分支选择不同配置
- 需要生成构建元数据

**关键特性：**
- 基于 `CI_COMMIT_REF_NAME` 判断环境
- 动态选择对应环境的配置文件
- 自动生成构建信息 JSON 文件

**使用方法：**
```bash
# 准备不同环境的配置文件
mkdir -p config
touch config/nginx.dev.conf
touch config/nginx.sit.conf
touch config/nginx.prod.conf
touch config/app.dev.json
touch config/app.sit.json
touch config/app.prod.json
```

---

### 3. java-with-config.gitlab-ci.yml

**场景：** Java 应用打包外部配置文件到镜像

**适用于：**
- Spring Boot 应用
- 需要外部配置文件覆盖内置配置
- 需要自定义启动脚本

**关键特性：**
- 准备 Spring Boot 配置文件
- 生成自定义启动脚本
- 使用 `-Dspring.config.location` 加载外部配置

**使用方法：**
```bash
# 准备配置文件
mkdir -p deploy docker
touch deploy/application.yml
touch deploy/logback-spring.xml

# 创建自定义 Dockerfile
# 参考示例中的注释内容
vi docker/Dockerfile
```

---

## 通用使用步骤

### 1. 准备项目结构

根据选择的示例，准备对应的目录结构和配置文件。

### 2. 复制示例配置

```bash
# 选择合适的示例
cp examples/web-multi-config.gitlab-ci.yml .gitlab-ci.yml
```

### 3. 调整配置

根据项目实际情况，调整以下内容：
- 构建命令 (`BUILD_SHELL`)
- 配置文件路径
- 前置命令逻辑

### 4. 测试验证

```bash
# 提交代码触发 CI/CD
git add .
git commit -m "feat: add docker workspace prepare config"
git push
```

## 命令执行流程

```
┌─────────────────────────┐
│  1. build_init()        │  构建初始化（编译代码）
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  2. image_build_init()  │  复制构建产物到 DOCKER_DAEMON_WORKSPACE
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  3. cd WORKSPACE        │  切换到 Docker 构建工作区
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  4. PREPARE_CMD 执行    │  ⭐ 在这里执行前置准备命令
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  5. 处理 Dockerfile     │  生成或复制 Dockerfile
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  6. docker build        │  构建 Docker 镜像
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│  7. docker push         │  推送镜像到 Harbor
└─────────────────────────┘
```

## 调试技巧

### 1. 查看工作区内容

在 `DOCKER_WORKSPACE_PREPARE_CMD` 中添加：
```bash
echo "当前工作目录："
pwd
echo "目录内容："
ls -lha
```

### 2. 验证文件内容

```bash
echo "配置文件内容："
cat nginx.conf
```

### 3. 检查环境变量

```bash
echo "CI 环境变量："
echo "分支: ${CI_COMMIT_REF_NAME}"
echo "提交: ${CI_COMMIT_SHORT_SHA}"
echo "构建环境: ${BUILD_ENV}"
```

### 4. 错误处理

```bash
# 添加错误检查
if [ ! -f "${CI_PROJECT_DIR}/config/nginx.conf" ]; then
    echo "错误: 找不到 nginx.conf 文件"
    exit 1
fi
```

## 常见问题

### Q1: 前置命令什么时候执行？

**A:** 在以下步骤之间执行：
- 已完成：代码编译、产物复制到 DOCKER_DAEMON_WORKSPACE
- 未开始：生成 Dockerfile、执行 docker build

### Q2: 命令在哪个目录执行？

**A:** 在 `DOCKER_DAEMON_WORKSPACE` 目录（默认为 `./docker-build`）

### Q3: 如何引用项目文件？

**A:** 使用 `${CI_PROJECT_DIR}` 变量：
```bash
cp ${CI_PROJECT_DIR}/config/app.conf .
```

### Q4: 命令执行失败会怎样？

**A:** 构建会立即终止，不会继续执行 docker build

### Q5: 能否执行多行命令？

**A:** 可以，使用 YAML 多行字符串语法：
```yaml
DOCKER_WORKSPACE_PREPARE_CMD: |
  command1
  command2
  command3
```

## 最佳实践

1. **添加日志输出**
   ```bash
   echo "开始准备配置文件..."
   # 执行命令
   echo "配置文件准备完成"
   ```

2. **验证文件存在**
   ```bash
   if [ ! -f "nginx.conf" ]; then
       echo "错误: nginx.conf 未准备成功"
       exit 1
   fi
   ```

3. **使用清晰的目录结构**
   ```bash
   mkdir -p config ssl certs
   cp ${CI_PROJECT_DIR}/deploy/*.conf config/
   ```

4. **避免硬编码路径**
   ```bash
   # 不推荐
   cp /path/to/file .

   # 推荐
   cp ${CI_PROJECT_DIR}/config/file .
   ```

## 更多信息

- 主文档: [../../README.md](../../README.md)
- 模板文档: [../README.md](../README.md)
- 变量配置: [../../../vars/default-vars.stable.gitlab-ci.yml](../../../vars/default-vars.stable.gitlab-ci.yml)
