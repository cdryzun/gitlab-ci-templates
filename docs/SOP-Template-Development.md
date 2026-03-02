# GitLab CI/CD Template Development SOP

## Overview

标准化的 GitLab CI/CD 模板开发、验证和调试流程，确保模板更改的可靠性和可维护性。

---

## Phase 1: Requirements Analysis & Code Review

### 1.1 变更审查

**目标**：理解变更内容和影响范围

**步骤**：
1. 检查分支差异
   ```bash
   git diff main..feature-branch
   git log main..feature-branch --oneline
   ```

2. 识别变更类型
   - [ ] Bug 修复
   - [ ] 新功能
   - [ ] 重构
   - [ ] 文档更新

3. 影响范围评估
   - [ ] 哪些项目类型受影响（Java/Node/Python/Go）
   - [ ] 哪些阶段受影响（pre/build/test/deploy）
   - [ ] 是否有破坏性更改

**检查点**：
- [ ] 所有变更都有明确的 commit message
- [ ] 没有遗留的调试代码或注释
- [ ] Shell 脚本语法正确（`bash -n script.sh`）

---

## Phase 2: Merge & Integration

### 2.1 代码合并

**目标**：安全地合并分支到目标分支

**步骤**：
1. 确保分支同步
   ```bash
   git checkout main
   git pull origin main
   git checkout feature-branch
   git merge main
   ```

2. 解决冲突（如有）
   - 保留正确的更改
   - 验证合并后的代码逻辑

3. 合并到主分支
   ```bash
   git checkout main
   git merge feature-branch
   git push origin main
   ```

**检查点**：
- [ ] 合并无冲突
- [ ] Git 历史清晰
- [ ] 远程分支已更新

---

## Phase 3: Pipeline Validation

### 3.1 触发验证流水线

**目标**：在真实项目中验证模板更改

**步骤**：
1. 选择合适的测试项目
   - 优先选择简单的项目（如 go-hello）
   - 确保项目有合适的测试分支

2. 触发流水线
   ```bash
   # 方法 1: 创建空 commit
   cd /path/to/test-project
   git checkout test-branch
   git commit --allow-empty -m "chore: trigger pipeline to test template changes"
   git push origin test-branch

   # 方法 2: API 触发（如果允许）
   glab api -X POST projects/namespace%2Fproject/pipeline --field ref=branch-name
   ```

3. 监控流水线状态
   ```bash
   # 获取最新流水线
   glab api projects/namespace%2Fproject/pipelines | jq '.[0] | {id, status, web_url}'

   # 查看所有 jobs
   glab api projects/namespace%2Fproject/pipelines/PIPELINE_ID/jobs | jq '.[] | {name, status, duration}'
   ```

**检查点**：
- [ ] 流水线已触发
- [ ] pre 阶段成功
- [ ] build 阶段成功

---

## Phase 4: Debugging Failed Pipelines

### 4.1 日志收集

**目标**：获取详细的失败信息

**步骤**：
1. 定位失败的 job
   ```bash
   glab api projects/namespace%2Fproject/pipelines/PIPELINE_ID/jobs | \
     jq '.[] | select(.status=="failed") | {id, name, stage}'
   ```

2. 获取 job 日志
   ```bash
   # 获取完整日志
   glab api projects/namespace%2Fproject/jobs/JOB_ID/trace

   # 获取最后 100 行
   glab api projects/namespace%2Fproject/jobs/JOB_ID/trace | tail -100
   ```

3. 提取关键错误
   - 搜索 "ERROR"、"Error"、"failed" 关键字
   - 检查 exit code
   - 注意 "unbound variable"、"command not found" 等错误

**检查点**：
- [ ] 识别失败阶段
- [ ] 获取错误日志
- [ ] 定位错误文件和行号

---

### 4.2 根因分析

**目标**：找到问题的根本原因

**常见问题模式**：

| 错误类型 | 可能原因 | 调试方法 |
|---------|---------|---------|
| `unbound variable` | `set -u` 导致未定义变量报错 | 检查变量是否在 GitLab CI 中定义 |
| `command not found` | 依赖工具未安装 | 检查 builder image 是否包含该工具 |
| `exit code 1` (无明确错误) | 命令静默失败 | 启用 `set -x` 或 `CI_DEBUG_TRACE=true` |
| `permission denied` | 权限不足 | 检查文件权限和用户权限 |

**分析步骤**：
1. 检查脚本语法
   ```bash
   bash -n scripts/*.sh
   ```

2. 检查最近的更改
   ```bash
   git log --oneline -5
   git show COMMIT_ID --stat
   ```

3. 理解脚本设计意图
   - 脚本是否依赖 GitLab CI 变量注入？
   - 是否有 `set` 标志的更改？
   - 是否有环境假设？

**检查点**：
- [ ] 识别根本原因
- [ ] 确认影响范围
- [ ] 记录问题模式

---

## Phase 5: Fix Implementation

### 5.1 修复策略

**目标**：实施最小化、精确的修复

**修复原则**：
1. **KISS**：保持简单，避免过度设计
2. **YAGNI**：只修复当前问题，不添加不必要的功能
3. **可逆性**：确保修复可以回滚

**修复步骤**：
1. 创建修复分支
   ```bash
   git checkout -b fix/description
   ```

2. 实施修复
   - 只修改必要的部分
   - 保留有效的更改
   - 回滚有害的更改

3. 本地验证
   ```bash
   # 语法检查
   bash -n scripts/*.sh

   # 如果有本地测试
   ./hack/test-pre-matrix.sh
   ```

4. 提交修复
   ```bash
   git add specific-files
   git commit -m "fix: clear description of the fix

   - What was wrong
   - Why it was wrong
   - How this fixes it"
   ```

**检查点**：
- [ ] 修复最小化
- [ ] 语法正确
- [ ] Commit message 清晰

---

## Phase 6: Verification & Deployment

### 6.1 验证修复

**目标**：确保修复有效且无副作用

**步骤**：
1. 推送修复
   ```bash
   git push origin fix-branch
   git checkout main
   git merge fix-branch
   git push origin main
   ```

2. 等待 CDN 缓存过期
   - GitHub raw URL 有 5 分钟缓存
   - 等待 5+ 分钟后再测试

3. 触发验证流水线
   ```bash
   cd /path/to/test-project
   git commit --allow-empty -m "chore: verify fix"
   git push origin test-branch
   ```

4. 对比验证
   ```bash
   # 对比失败和成功的流水线
   # 失败流水线
   glab api projects/ns/prj/pipelines/OLD_ID/jobs | jq '.[] | {name, status, duration}'

   # 成功流水线
   glab api projects/ns/prj/pipelines/NEW_ID/jobs | jq '.[] | {name, status, duration}'
   ```

**成功标准**：
- [ ] 所有阶段成功完成
- [ ] 执行时间正常（无异常延迟）
- [ ] 输出日志正常（无隐藏错误）

---

### 6.2 文档更新

**目标**：记录修复和经验教训

**更新内容**：
1. 更新 CLAUDE.md（如需要）
2. 更新 README.md（如有破坏性更改）
3. 添加到 CHANGELOG（如果是重要修复）
4. 更新 memory 文件（记录经验教训）

**检查点**：
- [ ] 文档已更新
- [ ] Memory 已更新
- [ ] 团队已通知（如需要）

---

## Tools Reference

### GitLab CLI (glab)

```bash
# 认证检查
glab auth status

# 流水线操作
glab api projects/namespace%2Fproject/pipelines | jq '.[0]'
glab api projects/namespace%2Fproject/pipelines/ID/jobs
glab api projects/namespace%2Fproject/jobs/ID/trace

# 触发流水线
glab api -X POST projects/namespace%2Fproject/pipeline --field ref=branch
```

### Git Operations

```bash
# 查看差异
git diff main..feature
git log main..feature --oneline

# 安全合并
git checkout main && git pull
git checkout feature && git merge main
git checkout main && git merge feature

# 创建空 commit
git commit --allow-empty -m "chore: trigger pipeline"
```

### Script Validation

```bash
# 语法检查
bash -n scripts/*.sh

# ShellCheck（如果安装）
shellcheck scripts/*.sh

# 本地测试
./hack/test-pre-matrix.sh
```

---

## Common Pitfalls

### 1. `set -u` 与 GitLab CI 变量

**问题**：添加 `set -u` 导致脚本在 GitLab CI 环境中失败

**原因**：脚本设计依赖 GitLab CI 变量注入，不是所有变量都有默认值

**解决**：
- 不要盲目添加 `set -u`
- 理解脚本的运行环境
- 使用 `${VAR:-default}` 语法提供默认值（如果确实需要）

### 2. GitHub Raw URL 缓存

**问题**：修复后流水线仍然失败

**原因**：GitHub CDN 缓存了旧版本的脚本（5 分钟 TTL）

**解决**：
- 等待 5+ 分钟
- 使用不同的分支名测试
- 检查 URL 是否正确：`curl -I https://raw.githubusercontent.com/...`

### 3. 多行命令输出折叠

**问题**：GitLab CI 日志显示 `# collapsed multi-line command`，看不到错误

**解决**：
- 启用调试：`CI_DEBUG_TRACE=true`
- 在脚本中添加 `set -x`
- 检查 before_script 和 script 的分离

---

## Checklist: Before Declaring Done

- [ ] **代码质量**
  - [ ] 语法正确
  - [ ] 无调试代码
  - [ ] Commit message 清晰

- [ ] **功能验证**
  - [ ] pre 阶段成功
  - [ ] build 阶段成功
  - [ ] 其他阶段成功（如有）

- [ ] **影响评估**
  - [ ] 无破坏性更改（或已文档化）
  - [ ] 向后兼容
  - [ ] 性能无明显下降

- [ ] **文档**
  - [ ] CLAUDE.md 已更新
  - [ ] Memory 已更新
  - [ ] 团队已通知

---

## Example: Complete Workflow

```bash
# 1. 审查变更
git diff open..codex/analyze-project
git log open..codex/analyze-project --oneline

# 2. 合并分支
git checkout open && git pull
git merge codex/analyze-project
git push origin open

# 3. 触发验证
cd /tmp/go-hello
git checkout feat-test
git commit --allow-empty -m "chore: trigger pipeline"
git push origin feat-test

# 4. 监控流水线
glab api projects/sre%2Fdevops%2Fgo-hello/pipelines | jq '.[0] | {id, status}'
# 假设 pipeline ID 是 6159

# 5. 如果失败，获取日志
glab api projects/sre%2Fdevops%2Fgo-hello/pipelines/6159/jobs | \
  jq '.[] | select(.status=="failed") | {id, name}'
# 假设 job ID 是 19762

glab api projects/sre%2Fdevops%2Fgo-hello/jobs/19762/trace | tail -100

# 6. 分析和修复
cd /md0/vibe/gitlab-ci-templates
bash -n scripts/*.sh
git show HEAD --stat
# ... 实施修复 ...

# 7. 推送修复
git commit -m "fix: description"
git push origin open

# 8. 等待缓存过期
sleep 300  # 5 分钟

# 9. 再次验证
cd /tmp/go-hello
git commit --allow-empty -m "chore: verify fix"
git push origin feat-test

# 10. 确认成功
glab api projects/sre%2Fdevops%2Fgo-hello/pipelines | jq '.[0] | {id, status}'
```

---

## Contact & Support

- **项目地址**：https://github.com/cdryzun/gitlab-ci-templates
- **文档**：CLAUDE.md, README.md
- **Issues**：GitHub Issues
