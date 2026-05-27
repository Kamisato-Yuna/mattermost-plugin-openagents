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
