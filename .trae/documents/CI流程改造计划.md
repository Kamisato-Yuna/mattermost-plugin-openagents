# CI 流程改造计划

## 目标

为 Mattermost Open Agents 项目创建完整的 CI/CD 流程，包括：

1. **GitHub Actions CI 优化**：针对 main/dev 分支的差异化 CI 策略
2. **GitLab CI 配置**：创建 `.gitlab-ci.yml` 支持 GitLab 仓库

## 现状分析

### 现有 GitHub CI 配置
- 文件位置：`.github/workflows/ci.yml`
- 当前触发条件：
  - `push` 到 `master` 分支
  - `tags` 匹配 `v[0-9]+.[0-9]+.[0-9]+`
  - 所有 `pull_request` 事件

### 问题
1. ❌ 没有针对 dev 分支的轻量级 CI 策略
2. ❌ 没有 GitLab CI 配置文件
3. ⚠️ E2E 测试资源消耗大，dev 分支不需要完整测试

---

## 实施步骤

### 步骤 1：创建 GitHub CI 差异化配置

**创建文件**：
- `.github/workflows/ci-dev.yml` - 轻量级 dev 分支 CI
- `.github/workflows/ci-main.yml` - 完整 main 分支 CI

**ci-dev.yml 设计**（轻量级）：
```yaml
触发条件：
  - push 到 dev/*、feature/*、agent/*
  - 所有 PR（目标 main 或 dev）

执行任务：
  1. lint（代码风格检查）
  2. build（构建验证）
  3. plugin-tests（Go 单元测试）
  4. verify-no-drift（i18n 和锁文件检查）
  
跳过任务（节省资源）：
  - E2E 测试（dev 分支不稳定）
  - Real API 测试
  - 评估测试
```

**ci-main.yml 设计**（完整）：
```yaml
触发条件：
  - push 到 main 分支
  - 标签推送（版本发布）
  - PR 合并到 main

执行任务：
  1. lint
  2. build
  3. plugin-tests
  4. verify-no-drift
  5. 所有 E2E 测试（分片）
  6. Real API 测试（可选）
  7. 评估测试（PR 时）
  8. 部署（main 分支推送时）
```

### 步骤 2：创建 GitLab CI 配置

**创建文件**：`.gitlab-ci.yml`

**设计理念**：
- 保持与 GitHub CI 功能一致
- 使用 GitLab 特定的 CI 语法
- 支持 Docker 镜像构建
- 支持 GitLab Registry 推送

**主要任务**：
```yaml
stages:
  - lint
  - test
  - build
  - e2e
  - deploy

variables:
  PLUGIN_ID: mattermost-openagents
  DOCKER_IMAGE: $CI_REGISTRY_IMAGE/$PLUGIN_ID

lint:
  stage: lint
  image: golang:1.24
  script:
    - make check-style

test:
  stage: test
  image: golang:1.24
  services:
    - postgres:15
  script:
    - make test

build:
  stage: build
  image: node:24
  script:
    - make dist

e2e:
  stage: e2e
  # Playwright E2E 测试
```

### 步骤 3：在 dev 分支测试 GitHub CI

**执行**：
1. 提交 CI 配置文件到 dev 分支
2. 触发 GitHub Actions 运行
3. 监控构建结果
4. 修复任何问题

### 步骤 4：更新文档

**创建文件**：`docs/CI_CONFIGURATION.md`

**内容**：
- GitHub CI 配置说明
- GitLab CI 配置说明
- 分支策略对应的 CI 行为
- 常见问题排查

---

## 技术细节

### GitHub Actions 优化

#### 任务依赖关系
```
lint ─────┐
build ────┼──► plugin-tests ──► verify-no-drift
          │
test ─────┘

E2E jobs（仅 main）：
  e2e-build-artifact ──► e2e (shards)
                       ──► e2e-real-apis
                       ──► e2e-tool-calling
```

#### 缓存策略
```yaml
- 使用 Go 模块缓存
- 使用 npm/node_modules 缓存
- 使用 build artifacts 缓存
```

#### 资源优化
- E2E 测试使用分片（4 个并行任务）
- Real API 测试使用条件执行
- 评估测试仅在 PR 时运行

### GitLab CI 特性

#### 镜像管理
```yaml
build:image:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
```

#### 部署触发
```yaml
deploy:production:
  stage: deploy
  only:
    - tags
  environment: production
```

---

## 文件清单

| 文件路径 | 操作 | 说明 |
|---------|------|------|
| `.github/workflows/ci-dev.yml` | 创建 | dev 分支轻量级 CI |
| `.github/workflows/ci-main.yml` | 创建 | main 分支完整 CI |
| `.github/workflows/ci.yml` | 修改 | 保留 PR 触发，保持向后兼容 |
| `.gitlab-ci.yml` | 创建 | GitLab CI 配置 |
| `docs/CI_CONFIGURATION.md` | 创建 | CI 配置文档 |

---

## 测试计划

### GitHub CI 测试
1. 推送到 feature 分支 → 验证 ci-dev.yml 触发
2. 推送到 dev 分支 → 验证 ci-dev.yml 触发
3. 创建 PR 到 main → 验证 ci-main.yml 触发
4. 推送到 main 分支 → 验证完整测试运行

### 预期结果
- ✅ dev/feature 分支：2-3 分钟完成（lint + build + test）
- ✅ main 分支 PR：10-15 分钟完成（包含 E2E）
- ✅ main 分支推送：15-20 分钟完成（包含部署）

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| E2E 测试不稳定 | 使用重试机制，分片隔离 |
| CI 缓存失效 | 明确缓存键，定期清理 |
| GitLab 配置错误 | 使用 CI_LINT 本地验证 |
| 资源配额超限 | 优化任务并行度 |

---

## 时间估算

- **步骤 1**：创建 GitHub CI 配置 - 30 分钟
- **步骤 2**：创建 GitLab CI 配置 - 45 分钟
- **步骤 3**：测试和调试 - 1-2 小时
- **步骤 4**：文档编写 - 30 分钟

**总计**：约 3-4 小时

---

## 成功标准

1. ✅ dev 分支推送触发轻量级 CI（< 5 分钟）
2. ✅ main 分支推送触发完整 CI（< 20 分钟）
3. ✅ 所有测试任务按预期运行
4. ✅ GitLab CI 配置功能完整
5. ✅ 文档清晰完整

---

*计划版本：1.0*
*创建日期：2026-05-26*
*状态：待用户批准*
