# CI/CD 流程设计与自动化部署方案

## 项目概述

为 Mattermost Open Agents 插件设计 GitHub 和 GitLab 的 CI 流程，实现分层测试策略和自动化部署验证。

---

## 第一部分：CI 流程设计

### 1.1 测试项可用性和必要性分析

#### 必要性测试（必须运行）

| 测试项 | 描述 | 耗时 | 依赖 | dev | main | 说明 |
|--------|------|------|------|-----|------|------|
| **Lint & Style** | 代码风格检查 | 5-10min | Go linter | ✅ | ✅ | 基础代码质量保证 |
| **Unit Tests** | Go 单元测试 + PostgreSQL | 10-15min | PostgreSQL + pgvector | ✅ | ✅ | 核心功能逻辑验证 |
| **Build** | 插件构建 | 5-10min | Go | ✅ | ✅ | 确保代码可编译 |
| **i18n Check** | 翻译文件同步检查 | 2-3min | Node.js | ✅ | ✅ | 国际化完整性 |
| **Lockfile Check** | 依赖锁定检查 | 2-3min | Node.js | ✅ | ✅ | 依赖一致性 |

#### 可选测试（分层运行）

| 测试项 | 描述 | 耗时 | 依赖 | dev | main | 说明 |
|--------|------|------|------|------|------|------|
| **E2E Shards (Mock)** | Playwright 端到端测试（4 分片） | 30-45min | Mattermost Server | ✅ | ✅ | 功能性 UI 测试 |
| **E2E Real APIs** | 真实 API 测试 | 60-90min | MM Server + LLM API Keys | ❌ | ✅ | API 集成验证 |
| **Prompt Evals** | LLM 质量评估 | 30-60min | LLM API Keys | ❌ | ✅ | AI 输出质量 |
| **Full Build + FIPS** | 生产构建 + FIPS | 10-15min | Go | ❌ | ✅ | 发布准备 |
| **S3 Upload** | PR 预览包上传 | 2-5min | AWS S3 | ❌ | ✅ | 团队预览 |

#### 不推荐测试（资源消耗大）

| 测试项 | 描述 | 耗时 | 说明 |
|--------|------|------|------|
| ~~Deploy to Production~~ | 生产部署 | N/A | 不应在 CI 中自动执行 |
| ~~Stress Testing~~ | 压力测试 | 2-4h | 需要专门环境 |

---

### 1.2 GitHub CI 流程设计

#### 方案 A：分层测试流程（推荐）

**文件**：[`.github/workflows/ci-dev.yml`](file:///workspace/.github/workflows/ci-dev.yml)

```yaml
name: CI - Dev Branch
on:
  push:
    branches:
      - dev
  pull_request:
    branches:
      - dev

jobs:
  # 1. 快速验证（必须）
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: mattermost/actions/plugin-ci/lint@main

  # 2. 单元测试（必须）
  unit-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: pgvector/pgvector:pg15
        env:
          POSTGRES_USER: mmuser
          POSTGRES_PASSWORD: mostest
          POSTGRES_DB: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - name: Run tests
        env:
          PG_ROOT_DSN: "postgres://mmuser:mostest@localhost:5432/postgres?sslmode=disable"
          MM_SERVICESETTINGS_ENABLEDEVELOPER: true
        run: |
          make test

  # 3. 构建（必须）
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - name: Build plugin
        run: |
          make dist-ci

  # 4. i18n 和依赖检查（必须）
  verify-diffs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v6
        with:
          node-version: 24.11.0
      - name: Install webapp dependencies
        run: cd webapp && npm ci
      - name: Check i18n catalog drift
        run: make check-i18n
      - name: Check package-lock.json drift
        run: make check-locks

  # 5. E2E 快速测试（Mock API）
  e2e-quick:
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 60
    strategy:
      fail-fast: false
      matrix:
        shard: [shard-1, shard-2, shard-3, shard-4]
    env:
      MM_IMAGE: mattermost/mattermost-enterprise-edition:11.5.1
      EXCLUDE_REAL_API_TESTS: 'true'
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v6
        with:
          node-version: 24.11.0
      - uses: actions/download-artifact@v4
        with:
          name: e2e-plugin-dist
          path: ./dist/
      - name: Install dependencies
        run: cd e2e && npm ci
      - name: Install Playwright Browsers
        run: npx playwright install --with-deps
      - name: Run E2E tests
        run: |
          SPEC_OUTPUT="$(node ./scripts/ci-test-groups.mjs list e2e-${{ matrix.shard }})"
          npx playwright test --project=chromium $SPEC_OUTPUT

  # 6. 开发环境部署验证（可选）
  deploy-dev:
    needs: [lint, unit-tests, build, e2e-quick]
    if: github.ref == 'refs/heads/dev'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Deploy to Dev Server
        env:
          MM_SERVER_URL: ${{ secrets.MM_DEV_SERVER_URL }}
          MM_DEV_TOKEN: ${{ secrets.MM_DEV_TOKEN }}
        run: |
          PLUGIN_FILE=$(ls dist/*.tar.gz)
          curl -H "Authorization: Bearer $MM_DEV_TOKEN" \
               -X POST \
               -F "plugin=@$PLUGIN_FILE" \
               -F "force=true" \
               "$MM_SERVER_URL/api/v4/plugins"
```

**文件**：[`.github/workflows/ci-main.yml`](file:///workspace/.github/workflows/ci-main.yml)

```yaml
name: CI - Main Branch
on:
  push:
    branches:
      - main
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+"
  pull_request:
    branches:
      - main

jobs:
  # 包含 dev 的所有测试 + 真实 API 测试
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: mattermost/actions/plugin-ci/lint@main

  unit-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: pgvector/pgvector:pg15
        env:
          POSTGRES_USER: mmuser
          POSTGRES_PASSWORD: mostest
          POSTGRES_DB: postgres
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - name: Run tests
        env:
          PG_ROOT_DSN: "postgres://mmuser:mostest@localhost:5432/postgres?sslmode=disable"
        run: make test

  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - name: Build plugin
        run: make dist-ci

  verify-diffs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v6
        with:
          node-version: 24.11.0
      - name: Install dependencies
        run: cd webapp && npm ci
      - name: Check i18n
        run: make check-i18n
      - name: Check locks
        run: make check-locks

  e2e-quick:
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 60
    strategy:
      matrix:
        shard: [shard-1, shard-2, shard-3, shard-4]
    env:
      MM_IMAGE: mattermost/mattermost-enterprise-edition:11.5.1
      EXCLUDE_REAL_API_TESTS: 'true'
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v6
        with:
          node-version: 24.11.0
      - uses: actions/download-artifact@v4
        with:
          name: e2e-plugin-dist
          path: ./dist/
      - name: Install dependencies
        run: cd e2e && npm ci
      - name: Install Playwright
        run: npx playwright install --with-deps
      - name: Run E2E tests
        run: |
          SPEC_OUTPUT="$(node ./scripts/ci-test-groups.mjs list e2e-${{ matrix.shard }})"
          npx playwright test --project=chromium $SPEC_OUTPUT

  # 真实 API 测试（main 分支独有）
  e2e-real-apis:
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 180
    strategy:
      fail-fast: false
      matrix:
        test_group:
          - llmbot-real-citations
          - llmbot-real-reasoning
          - llmbot-real-edge-cases
          - channel-analysis-real
          - system-console-real
          - tool-config-real
          - tool-calling-anthropic
          - tool-calling-openai
    env:
      MM_IMAGE: mattermost/mattermost-enterprise-edition:11.5.1
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v6
        with:
          node-version: 24.11.0
      - uses: actions/download-artifact@v4
        with:
          name: e2e-plugin-dist
          path: ./dist/
      - name: Install dependencies
        run: cd e2e && npm ci
      - name: Install Playwright
        run: npx playwright install --with-deps
      - name: Run real API tests
        run: |
          SPEC_OUTPUT="$(node ./scripts/ci-test-groups.mjs list ${{ matrix.test_group }})"
          npx playwright test --project=chromium $SPEC_OUTPUT

  # Prompt 评估（main 分支独有）
  evals:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    strategy:
      matrix:
        provider: [openai, anthropic, azure, mistral, bedrock]
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - name: Run evaluations
        env:
          LLM_PROVIDER: ${{ matrix.provider }}
          # 各 provider 的 API keys
        run: make evals-comment

  # 完整构建 + FIPS
  build-full:
    needs: [lint, unit-tests, build, e2e-quick, e2e-real-apis]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: mattermost/actions/plugin-ci/setup@main
      - uses: mattermost/actions/plugin-ci/build@main
      - uses: mattermost/actions/plugin-ci/build-fips@c7a06bc642f72fc227deb2cae3af03cff72c0f0d
        with:
          chainguard-identity: ${{ secrets.CHAINGUARD_IDENTITY }}
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: all-plugin-artifacts
          path: |
            dist/*.tar.gz
            dist/release-notes.md
            dist-fips/*.tar.gz

  # PR 预览包上传
  upload-s3-pr:
    needs: [lint]
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Build plugin
        run: make dist-ci
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Upload to S3
        run: |
          aws s3 cp dist/mattermost-openagents-*.tar.gz \
            s3://${{ secrets.AWS_S3_BUCKET }}/mattermost-plugin-openagents/

  # Staging 环境部署
  deploy-staging:
    needs: [build-full]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Deploy to Staging
        env:
          MM_STAGING_SERVERS: ${{ secrets.MM_STAGING_SERVERS }}
        run: |
          # 解析 JSON 配置并部署到多个 staging 服务器
          echo "$MM_STAGING_SERVERS" | jq -c '.[]' | while read server; do
            url=$(echo "$server" | jq -r '.url')
            token=$(echo "$server" | jq -r '.token')
            PLUGIN_FILE=$(ls dist/*.tar.gz)
            curl -H "Authorization: Bearer $token" \
                 -X POST \
                 -F "plugin=@$PLUGIN_FILE" \
                 -F "force=true" \
                 "$url/api/v4/plugins"
          done

  # 发布（仅标签触发）
  release:
    needs: [build-full]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v5
      - name: Create Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          PLUGIN_FILE=$(ls dist/*.tar.gz)
          gh release create ${{ github.ref_name }} \
            --title "${{ github.ref_name }}" \
            --notes "Release ${{ github.ref_name }}" \
            $PLUGIN_FILE
```

---

### 1.3 GitLab CI 流程设计

**文件**：[`.gitlab-ci.yml`](file:///workspace/.gitlab-ci.yml)

```yaml
stages:
  - lint
  - test
  - build
  - e2e
  - deploy
  - release

# ========================================
# Variables
# ========================================
variables:
  NODE_VERSION: "24.11.0"
  MM_IMAGE: "mattermost/mattermost-enterprise-edition:11.5.1"
  POSTGRES_IMAGE: "pgvector/pgvector:pg15"
  EXCLUDE_REAL_API_TESTS: "true"

# ========================================
# Cache
# ========================================
cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - .go/pkg/mod
    - webapp/node_modules
    - e2e/node_modules

# ========================================
# Stage: Lint
# ========================================
lint:
  stage: lint
  image: golang:1.24
  script:
    - make check-style
  rules:
    - if: $CI_COMMIT_BRANCH == "dev" || $CI_COMMIT_BRANCH == "main"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

# ========================================
# Stage: Test
# ========================================
unit-tests:
  stage: test
  image: golang:1.24
  services:
    - name: ${POSTGRES_IMAGE}
      alias: postgres
      variables:
        POSTGRES_USER: mmuser
        POSTGRES_PASSWORD: mostest
        POSTGRES_DB: postgres
  script:
    - export PG_ROOT_DSN="postgres://mmuser:mostest@postgres:5432/postgres?sslmode=disable"
    - make test
  rules:
    - if: $CI_COMMIT_BRANCH == "dev" || $CI_COMMIT_BRANCH == "main"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

verify-i18n:
  stage: test
  image: node:${NODE_VERSION}
  script:
    - cd webapp && npm ci
    - make check-i18n
    - make check-locks
  rules:
    - if: $CI_COMMIT_BRANCH == "dev" || $CI_COMMIT_BRANCH == "main"

# ========================================
# Stage: Build
# ========================================
build:
  stage: build
  image: golang:1.24
  script:
    - make dist-ci
  artifacts:
    paths:
      - dist/*.tar.gz
    expire_in: 1 day
  rules:
    - if: $CI_COMMIT_BRANCH == "dev" || $CI_COMMIT_BRANCH == "main"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

# ========================================
# Stage: E2E (分层测试)
# ========================================
.e2e-template: &e2e-template
  image: node:${NODE_VERSION}
  services:
    - name: ${MM_IMAGE}
      alias: mattermost
  before_script:
    - cd e2e && npm ci
    - npx playwright install --with-deps
  script:
    - node ./scripts/ci-test-groups.mjs validate
    - |
      SPEC_OUTPUT="$(node ./scripts/ci-test-groups.mjs list $TEST_GROUP)"
      npx playwright test --project=chromium $SPEC_OUTPUT
  artifacts:
    when: always
    paths:
      - e2e/playwright-report/
      - e2e/logs/
    expire_in: 7 days
  variables:
    MM_SITEURL: "http://mattermost:8065"
    DB_CONNECTION_STRING: "postgres://mmuser:mostest@postgres:5432/postgres?sslmode=disable"

# Dev 分支：仅 Mock API 测试
e2e-shard-1:
  <<: *e2e-template
  variables:
    TEST_GROUP: "e2e-shard-1"
    EXCLUDE_REAL_API_TESTS: "true"
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"

e2e-shard-2:
  <<: *e2e-template
  variables:
    TEST_GROUP: "e2e-shard-2"
    EXCLUDE_REAL_API_TESTS: "true"
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"

e2e-shard-3:
  <<: *e2e-template
  variables:
    TEST_GROUP: "e2e-shard-3"
    EXCLUDE_REAL_API_TESTS: "true"
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"

e2e-shard-4:
  <<: *e2e-template
  variables:
    TEST_GROUP: "e2e-shard-4"
    EXCLUDE_REAL_API_TESTS: "true"
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"

# Main 分支：完整 E2E 测试
e2e-real-apis:
  <<: *e2e-template
  parallel:
    matrix:
      - TEST_GROUP:
          - llmbot-real-citations
          - llmbot-real-reasoning
          - llmbot-real-edge-cases
          - channel-analysis-real
          - system-console-real
  variables:
    EXCLUDE_REAL_API_TESTS: "false"
    ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    OPENAI_API_KEY: ${OPENAI_API_KEY}
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

# ========================================
# Stage: Deploy (分层)
# ========================================
deploy-dev:
  stage: deploy
  image: curlimages/curl:latest
  script:
    - |
      for server in $DEV_SERVERS; do
        url=$(echo "$server" | jq -r '.url')
        token=$(echo "$server" | jq -r '.token')
        curl -H "Authorization: Bearer $token" \
             -X POST \
             -F "plugin=@dist/mattermost-openagents-*.tar.gz" \
             -F "force=true" \
             "$url/api/v4/plugins"
      done
  environment:
    name: development
    url: ${DEV_SERVER_URL}
  variables:
    DEV_SERVERS: ${CI_MM_DEV_SERVERS}
  rules:
    - if: $CI_COMMIT_BRANCH == "dev"
  only:
    variables:
      - $CI_MM_DEV_SERVERS

deploy-staging:
  stage: deploy
  image: curlimages/curl:latest
  script:
    - |
      for server in $STAGING_SERVERS; do
        url=$(echo "$server" | jq -r '.url')
        token=$(echo "$server" | jq -r '.token')
        curl -H "Authorization: Bearer $token" \
             -X POST \
             -F "plugin=@dist/mattermost-openagents-*.tar.gz" \
             -F "force=true" \
             "$url/api/v4/plugins"
      done
  environment:
    name: staging
  variables:
    STAGING_SERVERS: ${CI_MM_STAGING_SERVERS}
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  only:
    variables:
      - $CI_MM_STAGING_SERVERS

# ========================================
# Stage: Release
# ========================================
release:
  stage: release
  image: node:${NODE_VERSION}
  script:
    - npm install -g github-release-cli
    - |
      github-release upload \
        --user ${CI_PROJECT_NAMESPACE} \
        --repo ${CI_PROJECT_NAME} \
        --tag ${CI_COMMIT_TAG} \
        --file dist/*.tar.gz \
        --file dist-fips/*.tar.gz \
        --name "${CI_COMMIT_TAG}" \
        --body "Release ${CI_COMMIT_TAG}"
  environment:
    name: production
  rules:
    - if: $CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/
  only:
    - tags
```

---

## 第二部分：自动化部署到 Mattermost 测试服务器

### 2.1 部署架构概述

```
┌─────────────────────────────────────────────────────────┐
│                    CI/CD Pipeline                        │
├─────────────────────────────────────────────────────────┤
│  Build → Test (dev) → Deploy to Dev Server              │
│                          ↓                               │
│                    Test (main) → Deploy to Staging       │
│                          ↓                               │
│                      Release Build → Deploy to Prod       │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│              Mattermost Server Infrastructure            │
├─────────────────────────────────────────────────────────┤
│  Dev Server(s) ←─ 快速反馈验证                          │
│  Staging Server(s) ←─ 集成测试 + QA                     │
│  Production Server(s) ←─ 最终发布                        │
└─────────────────────────────────────────────────────────┘
```

---

### 2.2 部署准备清单

#### 硬件/基础设施准备

| 组件 | 最低配置 | 推荐配置 | 数量 | 说明 |
|------|---------|---------|------|------|
| **Dev Server** | 4 CPU, 8GB RAM, 50GB SSD | 8 CPU, 16GB RAM, 100GB SSD | 1-2 台 | 开发测试，快速反馈 |
| **Staging Server** | 8 CPU, 16GB RAM, 100GB SSD | 16 CPU, 32GB RAM, 200GB SSD | 2-3 台 | 预发布测试 |
| **Production Server** | 取决于实际用户量 | 负载均衡 + 多节点 | 按需 | 生产环境 |

#### 软件环境准备

| 软件 | 版本要求 | 说明 |
|------|---------|------|
| **Mattermost Server** | 6.2.1+ | 插件支持的最低版本 |
| **PostgreSQL** | 15+ with pgvector | 向量数据库支持 |
| **Docker** | Latest | 容器化部署 |
| **Kubernetes** (可选) | 1.24+ | 大规模部署 |

#### 网络配置

| 配置项 | 要求 | 说明 |
|--------|------|------|
| **HTTPS** | ✅ 必须 | Mattermost 要求 HTTPS |
| **防火墙** | 开放 443/8065 | Web + API 端口 |
| **API Token** | 长期访问令牌 | 用于 CI 部署 |
| **网络隔离** | 建议 | Dev/Staging 与生产分离 |

---

### 2.3 Mattermost 服务器配置

#### 3.1 创建 API 访问令牌

1. **登录 Mattermost**
   ```
   https://your-mattermost-server.com/login
   ```

2. **生成个人访问令牌**
   - 进入 **Account Settings** → **Security** → **Personal Access Tokens**
   - 点击 **Create New Token**
   - 填写描述：`CI/CD Deployment Token`
   - 复制生成的令牌（仅显示一次）

3. **令牌权限**
   - 需要 `api_v4` 权限
   - 推荐创建系统管理员账户的令牌

#### 3.2 配置 Mattermost

```bash
# Mattermost 配置文件 (config.json)
{
  "ServiceSettings": {
    "SiteURL": "https://your-mattermost-server.com",
    "EnableAPIv4": true,
    "EnableDeveloper": true
  },
  "PluginSettings": {
    "EnableUploads": true,
    "AllowInsecureDownloadURL": false
  }
}
```

#### 3.3 Docker Compose 部署示例

**文件**：[`deploy/docker-compose.mattermost.yml`](file:///workspace/deploy/docker-compose.mattermost.yml)

```yaml
version: '3.8'

services:
  mattermost:
    image: mattermost/mattermost-enterprise-edition:11.5.1
    container_name: mattermost-dev
    ports:
      - "8065:8065"
      - "8080:8080"
      - "8443:8443"
    environment:
      - MM_SQLSETTINGS_DRIVERNAME=postgres
      - MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:mostest@postgres:5432/mattermost?sslmode=disable&connect_timeout=10
      - MM_TEAMSETTINGS_SITENAME=MattermostDev
      - MM_SERVICE_SETTINGS_ENABLEDEVELOPER=true
      - MM_SERVICE_SETTINGS_ALLOWINSECUREDOWNLOADURL=false
    volumes:
      - ./mattermost-data:/mattermost/data
      - ./mattermost-logs:/mattermost/logs
      - ./mattermost-config:/mattermost/config
    depends_on:
      - postgres
    restart: unless-stopped

  postgres:
    image: pgvector/pgvector:pg15
    container_name: mattermost-postgres
    environment:
      - POSTGRES_USER=mmuser
      - POSTGRES_PASSWORD=mostest
      - POSTGRES_DB=mattermost
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  mattermost-data:
  mattermost-logs:
  mattermost-config:
  postgres-data:
```

**启动命令**：
```bash
# 创建部署目录
mkdir -p ~/mattermost-dev
cd ~/mattermost-dev

# 复制配置文件
cp /path/to/docker-compose.mattermost.yml docker-compose.yml

# 启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f mattermost
```

---

### 2.4 CI 部署脚本

**文件**：[`deploy/scripts/deploy-to-mattermost.sh`](file:///workspace/deploy/scripts/deploy-to-mattermost.sh)

```bash
#!/bin/bash
# deploy-to-mattermost.sh - Mattermost 插件自动化部署脚本

set -e

# ========================================
# 配置
# ========================================
PLUGIN_FILE=${1:-dist/mattermost-openagents-*.tar.gz}
FORCE=${2:-true}
TIMEOUT=60

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ========================================
# 函数
# ========================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "检查依赖..."
    command -v curl >/dev/null 2>&1 || { log_error "curl 未安装"; exit 1; }
    command -v jq >/dev/null 2>&1 || { log_error "jq 未安装"; exit 1; }
}

upload_plugin() {
    local server_url=$1
    local token=$2
    local plugin_path=$3
    local force=$4

    log_info "部署插件到: $server_url"

    local curl_cmd="curl -s -w '\n%{http_code}'"
    curl_cmd+=" -H 'Authorization: Bearer $token'"
    curl_cmd+=" -X POST"
    curl_cmd+=" -F 'plugin=@$plugin_path'"
    curl_cmd+=" -F 'force=$force'"
    curl_cmd+=" '$server_url/api/v4/plugins'"

    local response
    response=$(eval $curl_cmd)
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log_info "✓ 部署成功 (HTTP $http_code)"
        return 0
    else
        log_error "✗ 部署失败 (HTTP $http_code)"
        log_error "响应: $body"
        return 1
    fi
}

deploy_from_config() {
    local config_json=$1
    local plugin_path=$2
    local force=$3

    local server_count
    server_count=$(echo "$config_json" | jq 'length')

    log_info "发现 $server_count 个服务器"

    for i in $(seq 0 $((server_count - 1))); do
        local server
        server=$(echo "$config_json" | jq ".[$i]")

        local url=$(echo "$server" | jq -r '.url')
        local token=$(echo "$server" | jq -r '.token')
        local name=$(echo "$server" | jq -r '.name // "Server"')

        log_info "部署到: $name ($url)"

        if ! upload_plugin "$url" "$token" "$plugin_path" "$force"; then
            log_error "部署到 $name 失败"
            return 1
        fi
    done
}

# ========================================
# 主逻辑
# ========================================
main() {
    log_info "Mattermost 插件部署脚本"
    log_info "插件文件: $PLUGIN_FILE"
    log_info "强制部署: $FORCE"
    echo ""

    check_dependencies

    # 检查插件文件
    if [ ! -f "$PLUGIN_FILE" ]; then
        # 尝试查找匹配的文件
        shopt -s nullglob
        local matched_files=($PLUGIN_FILE)
        shopt -u nullglob

        if [ ${#matched_files[@]} -eq 0 ]; then
            log_error "插件文件不存在: $PLUGIN_FILE"
            exit 1
        fi
        PLUGIN_FILE="${matched_files[0]}"
        log_info "找到插件文件: $PLUGIN_FILE"
    fi

    # 从环境变量部署
    if [ -n "$MM_SERVERS_CONFIG" ]; then
        log_info "从环境变量 MM_SERVERS_CONFIG 读取服务器配置"
        deploy_from_config "$MM_SERVERS_CONFIG" "$PLUGIN_FILE" "$FORCE"
    elif [ -n "$CI_MM_DEV_SERVERS" ]; then
        log_info "从环境变量 CI_MM_DEV_SERVERS 读取服务器配置"
        deploy_from_config "$CI_MM_DEV_SERVERS" "$PLUGIN_FILE" "$FORCE"
    elif [ -n "$CI_MM_STAGING_SERVERS" ]; then
        log_info "从环境变量 CI_MM_STAGING_SERVERS 读取服务器配置"
        deploy_from_config "$CI_MM_STAGING_SERVERS" "$PLUGIN_FILE" "$FORCE"
    else
        # 单服务器部署（从环境变量）
        if [ -n "$MM_SERVER_URL" ] && [ -n "$MM_TOKEN" ]; then
            upload_plugin "$MM_SERVER_URL" "$MM_TOKEN" "$PLUGIN_FILE" "$FORCE"
        else
            log_error "未找到服务器配置"
            log_error "请设置以下环境变量之一："
            log_error "  - MM_SERVERS_CONFIG (JSON 数组)"
            log_error "  - MM_SERVER_URL + MM_TOKEN (单服务器)"
            log_error "  - CI_MM_DEV_SERVERS / CI_MM_STAGING_SERVERS (GitLab CI)"
            exit 1
        fi
    fi

    log_info "部署完成!"
}

main "$@"
```

---

### 2.5 服务器配置示例

#### 格式 1：GitHub Secrets / GitLab CI Variables

**JSON 格式**：
```json
[
  {
    "name": "Dev Server 1",
    "url": "https://mattermost-dev.example.com",
    "token": "your-api-token-here"
  },
  {
    "name": "Dev Server 2",
    "url": "https://mattermost-dev2.example.com",
    "token": "your-api-token-here"
  }
]
```

**环境变量名称**：
- `MM_SERVERS_CONFIG` - 通用 JSON 配置
- `CI_MM_DEV_SERVERS` - GitLab CI 开发服务器
- `CI_MM_STAGING_SERVERS` - GitLab CI 预发布服务器
- `MM_DEV_SERVER_URL` - 单个开发服务器 URL
- `MM_DEV_TOKEN` - 单个开发服务器 Token

#### 格式 2：多环境配置

```bash
# .env 文件（本地测试）
MM_SERVERS_CONFIG='[{"name":"Local Dev","url":"http://localhost:8065","token":"your-token"}]'
```

---

### 2.6 部署验证

#### 自动化验证脚本

**文件**：[`deploy/scripts/verify-deployment.sh`](file:///workspace/deploy/scripts/verify-deployment.sh)

```bash
#!/bin/bash
# verify-deployment.sh - 部署后验证脚本

set -e

PLUGIN_ID="mattermost-openagents"
SERVER_URL=${1:-${MM_SERVER_URL}}
TOKEN=${2:-${MM_TOKEN}}

echo "验证插件部署..."
echo "服务器: $SERVER_URL"
echo "插件 ID: $PLUGIN_ID"

# 1. 检查插件状态
response=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$SERVER_URL/api/v4/plugins")

plugin_status=$(echo "$response" | jq -r ".active[] | select(.id==\"$PLUGIN_ID\") | .id")

if [ "$plugin_status" = "$PLUGIN_ID" ]; then
    echo "✓ 插件已激活"
else
    echo "✗ 插件未找到或未激活"
    exit 1
fi

# 2. 检查插件版本
plugin_version=$(echo "$response" | jq -r ".active[] | select(.id==\"$PLUGIN_ID\") | .version")
echo "✓ 插件版本: $plugin_version"

# 3. 测试 API 端点
if curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$SERVER_URL/api/v4/plugins/$PLUGIN_ID/webapp"; then
    echo "✓ Webapp 端点可访问"
else
    echo "✗ Webapp 端点不可访问"
    exit 1
fi

echo ""
echo "部署验证完成!"
```

---

### 2.7 完整部署流程图

```
┌──────────────────────────────────────────────────────────────┐
│                    部署准备阶段                               │
├──────────────────────────────────────────────────────────────┤
│ 1. 准备 Mattermost 服务器（Docker/K8s）                     │
│ 2. 配置 HTTPS 和域名                                           │
│ 3. 创建 API 访问令牌                                          │
│ 4. 配置 CI Secrets/Variables                                  │
│ 5. 测试手动部署验证                                           │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                    CI/CD 部署阶段                             │
├──────────────────────────────────────────────────────────────┤
│ 1. 构建插件                                                   │
│ 2. 运行测试（根据分支）                                        │
│ 3. 上传插件到 S3（可选）                                      │
│ 4. 调用部署脚本                                               │
│ 5. 轮询部署结果                                               │
│ 6. 验证部署状态                                               │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                    部署后验证阶段                             │
├──────────────────────────────────────────────────────────────┤
│ 1. 检查插件激活状态                                            │
│ 2. 验证 API 端点                                               │
│ 3. 运行冒烟测试                                               │
│ 4. 发送通知（Slack/Email）                                   │
└──────────────────────────────────────────────────────────────┘
```

---

## 第三部分：实施步骤

### 步骤 1：基础设施准备（1-2天）

- [ ] 准备 Dev/Staging 服务器
- [ ] 安装 Mattermost + PostgreSQL
- [ ] 配置 HTTPS
- [ ] 创建 API 令牌
- [ ] 测试手动部署

### 步骤 2：CI 配置（1天）

- [ ] 创建 `.github/workflows/ci-dev.yml`
- [ ] 创建 `.github/workflows/ci-main.yml`
- [ ] 创建 `.gitlab-ci.yml`
- [ ] 配置 GitHub Secrets
- [ ] 配置 GitLab CI Variables

### 步骤 3：部署脚本（0.5天）

- [ ] 创建 `deploy/scripts/deploy-to-mattermost.sh`
- [ ] 创建 `deploy/scripts/verify-deployment.sh`
- [ ] 创建 Docker Compose 示例
- [ ] 测试部署脚本

### 步骤 4：测试验证（0.5天）

- [ ] 触发 dev 分支 CI
- [ ] 验证 dev 部署
- [ ] 触发 main 分支 CI
- [ ] 验证 staging 部署

### 步骤 5：文档和培训（0.5天）

- [ ] 更新部署文档
- [ ] 创建故障排查指南
- [ ] 团队培训

---

## 总结

| 项目 | 预估时间 | 复杂度 | 说明 |
|------|---------|--------|------|
| 分层 CI 配置 | 1 天 | 中 | GitHub + GitLab |
| 自动化部署 | 1-2 天 | 中 | 脚本 + 验证 |
| 服务器准备 | 1-2 天 | 高 | 取决于现有环境 |
| 测试验证 | 0.5 天 | 低 | CI 流程测试 |
| **总计** | **3.5-5.5 天** | - | - |

**核心收益**：
- ✅ 开发迭代加速（dev 分支 30-45 分钟）
- ✅ 质量保证（main 分支完整测试）
- ✅ 自动化部署（减少人工操作）
- ✅ 快速反馈（真实环境验证）
