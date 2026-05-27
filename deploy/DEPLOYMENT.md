# Mattermost 插件部署指南

## 概述

本文档介绍如何配置和使用自动化部署脚本将 Mattermost Open Agents 插件部署到不同的服务器环境。

## 快速开始

### 1. 配置服务器

创建 JSON 格式的服务器配置文件：

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

### 2. 配置 CI Secrets

#### GitHub Secrets

在 GitHub 仓库设置中添加以下 secrets：

| Secret 名称 | 描述 | 示例值 |
|-------------|------|--------|
| `MM_DEV_SERVER_URL` | 开发服务器 URL | `https://mattermost-dev.example.com` |
| `MM_DEV_TOKEN` | 开发服务器 API Token | `your-token-here` |
| `MM_STAGING_SERVERS` | Staging 服务器配置（JSON） | `[{"name":"Staging","url":"...","token":"..."}]` |
| `MM_PROD_SERVERS` | 生产服务器配置（JSON） | `[{"name":"Prod","url":"...","token":"..."}]` |
| `ANTHROPIC_API_KEY` | Anthropic API Key | `sk-ant-...` |
| `OPENAI_API_KEY` | OpenAI API Key | `sk-...` |
| `AWS_ACCESS_KEY_ID` | AWS 访问密钥 | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS 密钥 | `...` |
| `AWS_S3_BUCKET` | S3 存储桶名称 | `my-bucket` |

#### GitLab CI Variables

在 GitLab 仓库设置中添加以下 variables：

| Variable 名称 | 描述 | 保护 |
|--------------|------|------|
| `CI_MM_DEV_SERVERS` | 开发服务器配置（JSON） | Yes |
| `CI_MM_STAGING_SERVERS` | Staging 服务器配置（JSON） | Yes |
| `ANTHROPIC_API_KEY` | Anthropic API Key | Yes |
| `OPENAI_API_KEY` | OpenAI API Key | Yes |

### 3. 创建 API Token

1. 登录 Mattermost 服务器
2. 进入 **Account Settings** → **Security** → **Personal Access Tokens**
3. 点击 **Create New Token**
4. 复制生成的令牌（仅显示一次）
5. 将令牌添加到 CI secrets/variables

## 使用部署脚本

### 本地部署

```bash
# 安装依赖
chmod +x deploy/scripts/deploy-to-mattermost.sh

# 单服务器部署
MM_SERVER_URL=https://your-server.com \
MM_TOKEN=your-token \
./deploy/scripts/deploy-to-mattermost.sh dist/mattermost-openagents-*.tar.gz

# 多服务器部署
MM_SERVERS_CONFIG='[{"name":"Server1","url":"https://server1.com","token":"token1"},{"name":"Server2","url":"https://server2.com","token":"token2"}]' \
./deploy/scripts/deploy-to-mattermost.sh dist/mattermost-openagents-*.tar.gz
```

### CI/CD 自动部署

脚本会在 CI 流程中自动检测环境变量并执行部署：

```bash
# GitHub Actions
# 自动使用 MM_DEV_SERVER_URL 和 MM_DEV_TOKEN

# GitLab CI
# 自动使用 CI_MM_DEV_SERVERS 或 CI_MM_STAGING_SERVERS
```

## 部署流程

```
┌──────────────────────────────────────────────────────────────┐
│                    部署流程                                    │
├──────────────────────────────────────────────────────────────┤
│ 1. 构建插件 (make dist)                                      │
│ 2. 运行测试 (lint, unit-tests, e2e)                        │
│ 3. 上传插件到服务器                                          │
│ 4. 验证部署状态                                              │
│ 5. 发送通知（可选）                                          │
└──────────────────────────────────────────────────────────────┘
```

## 服务器配置示例

### Docker Compose 部署

```yaml
version: '3.8'

services:
  mattermost:
    image: mattermost/mattermost-enterprise-edition:11.5.1
    container_name: mattermost-dev
    ports:
      - "8065:8065"
      - "8080:8080"
    environment:
      - MM_SQLSETTINGS_DRIVERNAME=postgres
      - MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:mostest@postgres:5432/mattermost?sslmode=disable
      - MM_TEAMSETTINGS_SITENAME=MattermostDev
      - MM_SERVICE_SETTINGS_ENABLEDEVELOPER=true
    volumes:
      - ./mattermost-data:/mattermost/data
    depends_on:
      - postgres

  postgres:
    image: pgvector/pgvector:pg15
    environment:
      - POSTGRES_USER=mmuser
      - POSTGRES_PASSWORD=mostest
      - POSTGRES_DB=mattermost
    volumes:
      - ./postgres-data:/var/lib/postgresql/data

volumes:
  mattermost-data:
  postgres-data:
```

## 故障排查

### 常见问题

#### 1. 部署失败 (HTTP 401/403)

**原因**: API Token 无效或权限不足

**解决方案**:
- 检查 token 是否正确
- 确保 token 具有 `api_v4` 权限
- 验证 token 未过期

#### 2. 插件上传超时

**原因**: 网络问题或插件文件过大

**解决方案**:
- 检查网络连接
- 减小插件大小（移除不必要的文件）
- 增加超时时间

#### 3. 插件激活失败

**原因**: 插件与服务器版本不兼容

**解决方案**:
- 检查 `min_server_version` 配置
- 确认 Mattermost 版本 >= 6.2.1
- 查看服务器日志获取详细信息

### 调试模式

启用详细输出：

```bash
curl -v \
  -H "Authorization: Bearer $TOKEN" \
  -X POST \
  -F "plugin=@plugin.tar.gz" \
  -F "force=true" \
  "https://your-server.com/api/v4/plugins"
```

## 环境说明

| 环境 | 用途 | 自动部署 | 需要审批 |
|------|------|---------|---------|
| **Dev** | 开发测试 | ✅ dev 分支 push | ❌ |
| **Staging** | 预发布测试 | ✅ main 分支 push | ✅ 建议 |
| **Production** | 生产环境 | ✅ 标签发布 | ✅ 必须 |

## 安全建议

1. **Token 安全**
   - 使用环境变量而非硬编码
   - 定期轮换 token
   - 使用最小权限原则

2. **网络隔离**
   - 使用 HTTPS
   - 配置防火墙规则
   - 限制 API 访问来源

3. **审计日志**
   - 启用 Mattermost 审计日志
   - 记录部署历史
   - 监控异常访问

## 参考链接

- [Mattermost Plugin API](https://developers.mattermost.com/integrate/reference/plugins/)
- [Mattermost API Documentation](https://api.mattermost.com/)
- [Playwright E2E Testing](https://playwright.dev/)
