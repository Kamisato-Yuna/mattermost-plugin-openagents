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
    echo "Active plugins: $(echo "$response" | jq '.active | map(.id)')"
    exit 1
fi

# 2. 检查插件版本
plugin_version=$(echo "$response" | jq -r ".active[] | select(.id==\"$PLUGIN_ID\") | .version")
echo "✓ 插件版本: $plugin_version"

# 3. 测试 API 端点
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$SERVER_URL/api/v4/plugins/$PLUGIN_ID/webapp")

if [ "$http_code" = "200" ]; then
    echo "✓ Webapp 端点可访问 (HTTP $http_code)"
else
    echo "✗ Webapp 端点不可访问 (HTTP $http_code)"
    exit 1
fi

# 4. 检查插件状态详情
plugin_state=$(echo "$response" | jq -r ".active[] | select(.id==\"$PLUGIN_ID\") | .state")
echo "✓ 插件状态: $plugin_state"

echo ""
echo "部署验证完成!"
