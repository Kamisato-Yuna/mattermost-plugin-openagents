# 分支管理规范

## 概述

本项目采用 Git Flow 分支管理模型，针对 AI Agent 和人类开发者协作进行了优化。

## 分支类型

### 1. 主分支 (main)

- **用途**：稳定发布分支，始终保持可发布状态
- **保护状态**：受保护，禁止直接推送，必须通过 PR 合并
- **更新来源**：仅从 `dev` 分支合并
- **版本标签**：所有正式版本标签（vX.Y.Z）都基于此分支创建
- **同步规则**：定期从上游仓库同步最新更新

### 2. 开发分支 (dev)

- **用途**：集成分支，包含所有已完成的特性
- **保护状态**：受保护，禁止直接推送，必须通过 PR 合并
- **合并来源**：
  - Feature 分支（功能完成并测试后）
  - Hotfix 分支（紧急修复）
- **状态**：可能不稳定，但应具备基本功能
- **合并到 main 的条件**：
  - 所有 CI 测试通过
  - 代码审查通过
  - 功能完整可用

### 3. 上游同步分支 (master)

- **用途**：仅用于同步上游 Mattermost 官方插件仓库的更新
- **保护状态**：受保护，禁止直接推送
- **更新来源**：仅从上游仓库拉取
- **合并规则**：
  - 定期从上游仓库 `master`/`main` 分支同步
  - 如有冲突，需要手动解决并创建 PR
  - 不直接合并到 `main` 或 `dev`，除非是安全更新

### 4. 功能分支 (Feature)

- **命名规范**：`feature/<功能名称>` 或 `feat/<功能名称>`
- **创建来源**：`dev` 分支
- **合并目标**：`dev` 分支
- **生命周期**：
  1. 从 `dev` 创建
  2. 开发完成并测试
  3. 创建 PR 合并到 `dev`
  4. 删除分支（合并后）

### 5. 修复分支 (Hotfix)

- **命名规范**：`hotfix/<问题描述>` 或 `fix/<问题描述>`
- **创建来源**：`main` 分支
- **合并目标**：`main` 和 `dev` 分支
- **生命周期**：
  1. 从 `main` 创建
  2. 修复完成并测试
  3. 合并到 `main`（紧急发布）
  4. 合并到 `dev`（同步修复）
  5. 删除分支

### 6. 发布分支 (Release)

- **命名规范**：`release/vX.Y.Z`
- **创建来源**：`main` 分支
- **用途**：准备正式发布的稳定版本
- **生命周期**：
  1. 从 `main` 创建
  2. 进行最终测试和修复
  3. 打标签并发布
  4. 合并回 `main` 和 `dev`
  5. 删除分支

## Agent 协作规则

### 适用于 AI Agent 的分支策略

#### 1. 工作分支命名

AI Agent 创建的工作分支应使用以下命名规范：

```
agent/<agent-name>/<任务描述>
```

示例：
- `agent/trae/openai-integration`
- `agent/llm/add-translation-support`
- `agent/solo/bugfix/fix-license-check`

#### 2. Agent 开发流程

**步骤 1：创建工作分支**
```bash
# 从 dev 创建工作分支
git checkout dev
git pull origin dev
git checkout -b agent/<agent-name>/<task-name>
```

**步骤 2：开发与测试**
- 在工作分支上进行开发
- 运行 `make check` 验证代码
- 修复任何问题

**步骤 3：提交变更**
```bash
git add .
git commit -m "<type>: <中文描述>

<详细说明（可选）>"
```

**步骤 4：推送并创建 PR**
```bash
git push -u origin agent/<agent-name>/<task-name>
# 然后在 GitHub 上创建 PR 到 dev 分支
```

**步骤 5：等待审查**
- 等待人工审查或 CI 测试
- 根据反馈进行修改
- 合并到 dev

#### 3. Agent 提交规范

**提交消息格式**：
```
<type>: <简短的中文描述>

<详细说明（可选）>
```

**Type 类型**：
- `feat`: 新功能
- `fix`: 错误修复
- `docs`: 文档更新
- `style`: 代码格式（不影响功能）
- `refactor`: 重构
- `perf`: 性能优化
- `test`: 测试相关
- `chore`: 构建或辅助工具变更
- `i18n`: 国际化相关
- `ui`: UI 更新

**示例**：
```
feat: 添加中文翻译支持

- 添加完整的中文语言包
- 支持简体中文界面显示
- 修复翻译键值错误
```

### 人类开发者流程

1. **创建分支**：`git checkout -b feature/xxx`
2. **开发**：进行功能开发
3. **测试**：确保所有测试通过
4. **提交**：遵循提交规范
5. **PR**：创建 PR 到 `dev` 分支
6. **审查**：等待代码审查
7. **合并**：审查通过后合并

## 合并规则

### PR 合并要求

所有合并到 `main` 和 `dev` 的 PR 必须满足：

1. **CI 测试通过**
   - `make check`（代码风格 + 单元测试）
   - `make test`（所有测试）
   - E2E 测试（如果适用）

2. **代码审查**
   - 至少 1 人审查
   - 所有讨论已解决
   - 代码变更符合项目规范

3. **分支状态**
   - 基于最新的目标分支
   - 没有冲突
   - 提交历史清晰

### 冲突解决

1. **本地解决**：
   ```bash
   git checkout dev
   git pull origin dev
   git checkout <your-branch>
   git rebase dev
   # 解决冲突
   git add .
   git rebase --continue
   git push -f
   ```

2. **测试验证**：解决冲突后，确保所有测试通过

## 版本管理

### 版本号规范

采用 Semantic Versioning (SemVer)：

```
v<MAJOR>.<MINOR>.<PATCH>
```

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的新功能
- **PATCH**: 向后兼容的错误修复

### 版本发布流程

1. **准备发布**：
   ```bash
   git checkout dev
   git pull origin dev
   ```

2. **创建发布分支**：
   ```bash
   git checkout -b release/vX.Y.Z
   ```

3. **最终测试与修复**

4. **合并到 main**：
   ```bash
   git checkout main
   git merge release/vX.Y.Z
   ```

5. **创建标签**：
   ```bash
   git tag -a vX.Y.Z -m "版本 X.Y.Z"
   ```

6. **推送**：
   ```bash
   git push origin main --tags
   ```

7. **合并回 dev**：
   ```bash
   git checkout dev
   git merge release/vX.Y.Z
   git push origin dev
   ```

8. **清理**：
   ```bash
   git branch -d release/vX.Y.Z
   ```

### 预发布版本

使用 `-rc` (release candidate) 后缀：

```
v3.0.0-rc1
v3.0.0-rc2
```

## 分支保护

### 受保护分支

- `main` - 主要发布分支
- `dev` - 开发集成分支
- `master` - 上游同步分支

### 保护规则

1. **禁止直接推送**：所有变更必须通过 PR
2. **状态检查**：合并前必须通过所有 CI 检查
3. **审查要求**：至少 1 人审查（对于 `main` 和 `dev`）
4. **强制更新**：合并前必须基于最新代码

## GitHub 设置建议

### 1. Branch Protection Rules

在 GitHub 仓库设置中配置：

**对于 `main` 分支**：
- ✅ Require pull request reviews before merging
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- ✅ Include administrators
- ❌ Allow force pushes

**对于 `dev` 分支**：
- ✅ Require pull request reviews before merging (建议 1 人)
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- ❌ Allow force pushes

**对于 `master` 分支**：
- ✅ Require pull request reviews before merging
- ✅ Require status checks to pass before merging
- ❌ Allow force pushes

### 2. Repository Settings

- ✅ Disable force pushes to protected branches
- ✅ Enable branch protection rules
- ✅ Require PR for all contributions
- ✅ Require code review

## 日常开发工作流

### 开发者日常

1. **开始工作前**：
   ```bash
   git checkout dev
   git pull origin dev
   ```

2. **创建/切换到功能分支**：
   ```bash
   git checkout -b feature/my-feature
   # 或
   git checkout agent/solo/my-task
   ```

3. **开发与提交**：
   ```bash
   # 编写代码
   git add .
   git commit -m "feat: 添加新功能"
   ```

4. **推送和创建 PR**：
   ```bash
   git push -u origin HEAD
   # 在 GitHub 创建 PR 到 dev
   ```

5. **审查后合并**：
   - 等待审查反馈
   - 根据反馈修改
   - 合并后删除分支

### Agent 协作最佳实践

1. **明确任务范围**：每个 Agent 任务应有清晰的目标
2. **小步提交**：频繁提交，便于审查和回滚
3. **清晰的提交信息**：使用中文描述，便于团队理解
4. **测试覆盖**：确保新功能有测试
5. **文档更新**：相关文档同步更新
6. **透明度**：在 PR 中详细说明变更内容和理由

## 紧急修复流程

### Hotfix 流程

1. **创建 hotfix 分支**：
   ```bash
   git checkout main
   git pull origin main
   git checkout -b hotfix/critical-bug
   ```

2. **修复并测试**

3. **合并到 main**：
   ```bash
   git checkout main
   git merge hotfix/critical-bug
   git tag vX.Y.Z
   git push origin main --tags
   ```

4. **合并到 dev**：
   ```bash
   git checkout dev
   git merge hotfix/critical-bug
   git push origin dev
   ```

5. **清理**：
   ```bash
   git branch -d hotfix/critical-bug
   ```

## 文档更新要求

每当进行以下操作时，必须同步更新相关文档：

- ✅ 新增功能：更新 `docs/features/` 相关文档
- ✅ API 变更：更新 API 文档
- ✅ 配置变更：更新 `docs/admin_guide.md`
- ✅ 用户界面变更：更新 `docs/user_guide.md`
- ✅ 版本发布：更新 CHANGELOG

## 常见问题

### Q: 如何同步上游仓库的更新？

```bash
git checkout master
git fetch upstream
git merge upstream/master
# 解决冲突（如有）
git push origin master
```

### Q: Agent 可以直接合并到 main 吗？

**不可以**。所有 Agent 的工作都必须通过 PR 审查后才能合并。

### Q: 多个 Agent 同时开发同一功能怎么办？

1. 协调任务分配，避免重复
2. 使用不同的分支
3. 定期同步进展
4. 必要时合并分支

### Q: 提交信息应该用什么语言？

**中文**。为了便于团队理解，所有提交信息和 PR 描述应使用中文。

## 总结

遵循本规范可以确保：

1. **代码质量**：所有变更都经过审查和测试
2. **协作效率**：清晰的流程减少沟通成本
3. **版本可控**：稳定的发布流程
4. **知识共享**：清晰的提交历史和文档
5. **Agent 友好**：AI Agent 可以安全有效地参与开发

---

*最后更新：2026-05-26*
*版本：1.0.0*
