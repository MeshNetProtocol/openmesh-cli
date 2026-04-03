#!/bin/bash
# 自动化测试脚本：验证 RemoveUser 后新连接是否会被拒绝

set -e

# 配置
TEST_EMAIL="test-user@validation.com"
TEST_UUID="d3507f8a-d4eb-541a-a231-929c6237eee5"
XRAY_API_SCRIPT="./xray_api.py"
CLIENT_CONFIG="/tmp/xray_client_test.json"
SERVER_TAG="vmess-in"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    if ! command -v python3 &> /dev/null; then
        log_error "python3 未安装"
        exit 1
    fi

    if ! python3 -c "import xray_rpc" 2>/dev/null; then
        log_error "xray-rpc 包未安装，请运行: pip3 install xray-rpc"
        exit 1
    fi

    if [ ! -f "$XRAY_API_SCRIPT" ]; then
        log_error "找不到 xray_api.py 脚本"
        exit 1
    fi

    log_info "依赖检查通过"
}

# 生成客户端配置
generate_client_config() {
    log_info "生成客户端配置..."

    cat > "$CLIENT_CONFIG" <<EOF
{
  "log": {
    "loglevel": "debug"
  },
  "inbounds": [{
    "port": 1080,
    "protocol": "socks",
    "settings": {
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "vmess",
    "settings": {
      "vnext": [{
        "address": "127.0.0.1",
        "port": 10086,
        "users": [{
          "id": "$TEST_UUID",
          "email": "$TEST_EMAIL"
        }]
      }]
    }
  }]
}
EOF

    log_info "客户端配置已生成: $CLIENT_CONFIG"
}

# 测试连接
test_connection() {
    local description="$1"
    log_info "测试连接: $description"

    # 启动 Xray 客户端
    xray -c "$CLIENT_CONFIG" > /tmp/xray_client.log 2>&1 &
    local client_pid=$!

    # 等待客户端启动
    sleep 2

    # 测试连接（通过 SOCKS5 代理访问一个网站）
    local result=0
    if curl -x socks5://127.0.0.1:1080 -m 5 http://www.google.com > /dev/null 2>&1; then
        log_info "连接成功 ✅"
        result=0
    else
        log_warn "连接失败 ❌"
        result=1
    fi

    # 停止客户端
    kill $client_pid 2>/dev/null || true
    wait $client_pid 2>/dev/null || true

    return $result
}

# 主测试流程
main() {
    log_info "=========================================="
    log_info "开始 RemoveUser 验证测试"
    log_info "=========================================="

    check_dependencies
    generate_client_config

    # 步骤 1: 添加用户
    log_info ""
    log_info "步骤 1: 添加测试用户"
    python3 "$XRAY_API_SCRIPT" add "$TEST_EMAIL" "$TEST_UUID"
    sleep 1

    # 步骤 2: 测试连接（应该成功）
    log_info ""
    log_info "步骤 2: 测试初始连接（预期：成功）"
    if test_connection "用户添加后的连接"; then
        log_info "✅ 初始连接测试通过"
    else
        log_error "❌ 初始连接失败，测试中止"
        exit 1
    fi

    # 步骤 3: 删除用户
    log_info ""
    log_info "步骤 3: 删除测试用户"
    python3 "$XRAY_API_SCRIPT" remove "$TEST_EMAIL"
    sleep 1

    # 步骤 4: 完全停止客户端，等待一段时间
    log_info ""
    log_info "步骤 4: 等待 5 秒，确保所有连接关闭..."
    sleep 5

    # 步骤 5: 重新启动客户端并测试新连接（应该失败）
    log_info ""
    log_info "步骤 5: 测试新连接（预期：失败）"
    if test_connection "用户删除后的新连接"; then
        log_error "❌ 测试失败：RemoveUser 后新连接仍然成功！"
        log_error "这意味着 RemoveUser 没有阻止新连接"
        exit 1
    else
        log_info "✅ 测试通过：RemoveUser 成功阻止了新连接"
    fi

    # 清理
    log_info ""
    log_info "清理测试环境..."
    rm -f "$CLIENT_CONFIG"
    rm -f /tmp/xray_client.log

    log_info ""
    log_info "=========================================="
    log_info "✅ 所有测试通过！"
    log_info "=========================================="
    log_info ""
    log_info "结论："
    log_info "RemoveUser 操作能够成功阻止新连接"
    log_info "这满足了我们的需求"
}

# 运行测试
main
