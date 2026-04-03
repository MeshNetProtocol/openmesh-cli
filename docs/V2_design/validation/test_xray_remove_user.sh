#!/bin/bash
# Xray RemoveUser 验证测试
# 测试 RemoveUser 后新连接是否会被拒绝

set -e

# 配置
TEST_EMAIL="test-validation@example.com"
TEST_UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
XRAY_API_ADDR="127.0.0.1:10085"
VMESS_PORT=10086
SOCKS_PORT=1080
TEST_URL="http://www.google.com"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 检查 Xray 是否运行
check_xray_running() {
    log_info "检查 Xray 服务端是否运行..."
    if ! lsof -i :$VMESS_PORT > /dev/null 2>&1; then
        log_error "Xray 服务端未在端口 $VMESS_PORT 运行"
        log_error "请先启动 Xray 服务端"
        exit 1
    fi

    if ! lsof -i :10085 > /dev/null 2>&1; then
        log_error "Xray gRPC API 未在端口 10085 运行"
        log_error "请确保 Xray 配置中启用了 API"
        exit 1
    fi

    log_info "Xray 服务端运行正常"
}

# 生成客户端配置
create_client_config() {
    cat > /tmp/xray_test_client.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": $SOCKS_PORT,
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
        "port": $VMESS_PORT,
        "users": [{
          "id": "$TEST_UUID",
          "email": "$TEST_EMAIL",
          "security": "auto"
        }]
      }]
    }
  }]
}
EOF
    log_info "客户端配置已生成"
}

# 添加用户（使用 xray api）
add_user() {
    log_info "添加测试用户: $TEST_EMAIL"

    # 创建用户配置 JSON（VMess 格式）
    cat > /tmp/add_user.json <<EOF
{
  "email": "$TEST_EMAIL",
  "level": 0,
  "id": "$TEST_UUID",
  "alterId": 0
}
EOF

    # 使用 xray api 命令添加用户
    local output=$(xray api adu --server="$XRAY_API_ADDR" vmess-in /tmp/add_user.json 2>&1)

    if echo "$output" | grep -q "Added 1 user"; then
        log_info "用户添加成功"
        rm -f /tmp/add_user.json
    else
        log_error "用户添加失败: $output"
        rm -f /tmp/add_user.json
        exit 1
    fi
}

# 删除用户
remove_user() {
    log_info "删除测试用户: $TEST_EMAIL"

    # 使用 xray api 命令删除用户
    if xray api rmu --server="$XRAY_API_ADDR" -tag=vmess-in "$TEST_EMAIL" > /dev/null 2>&1; then
        log_info "用户删除成功"
    else
        log_error "用户删除失败"
        exit 1
    fi
}

# 测试连接
test_connection() {
    local description="$1"
    local expect_success="$2"

    log_info "测试: $description"

    # 启动客户端
    xray -c /tmp/xray_test_client.json > /tmp/xray_client.log 2>&1 &
    local client_pid=$!

    # 等待客户端启动
    sleep 3

    # 测试连接
    local result=0
    if curl -x socks5://127.0.0.1:$SOCKS_PORT -m 10 --silent --head "$TEST_URL" > /dev/null 2>&1; then
        result=0
        log_info "  连接成功"
    else
        result=1
        log_warn "  连接失败"
    fi

    # 停止客户端
    kill $client_pid 2>/dev/null || true
    wait $client_pid 2>/dev/null || true
    sleep 2

    # 验证结果
    if [ "$expect_success" = "true" ]; then
        if [ $result -eq 0 ]; then
            log_info "  ✅ 符合预期（连接成功）"
            return 0
        else
            log_error "  ❌ 不符合预期（应该成功但失败了）"
            return 1
        fi
    else
        if [ $result -eq 0 ]; then
            log_error "  ❌ 不符合预期（应该失败但成功了）"
            return 1
        else
            log_info "  ✅ 符合预期（连接被拒绝）"
            return 0
        fi
    fi
}

# 清理
cleanup() {
    log_info "清理测试环境..."
    rm -f /tmp/xray_test_client.json
    rm -f /tmp/xray_client.log

    # 尝试删除测试用户（如果还存在）
    xray api rmi --server="$XRAY_API_ADDR" vmess-in "$TEST_EMAIL" > /dev/null 2>&1 || true
}

# 主测试流程
main() {
    echo "=========================================="
    echo "Xray RemoveUser 验证测试"
    echo "=========================================="
    echo ""

    # 设置清理陷阱
    trap cleanup EXIT

    # 检查环境
    check_xray_running
    create_client_config

    # 步骤 1: 添加用户
    echo ""
    echo "=========================================="
    echo "步骤 1: 添加测试用户"
    echo "=========================================="
    add_user
    sleep 2

    # 步骤 2: 测试初始连接（应该成功）
    echo ""
    echo "=========================================="
    echo "步骤 2: 测试初始连接（预期：成功）"
    echo "=========================================="
    if ! test_connection "用户添加后的连接" "true"; then
        log_error "初始连接测试失败，中止测试"
        exit 1
    fi

    # 步骤 3: 删除用户
    echo ""
    echo "=========================================="
    echo "步骤 3: 删除测试用户"
    echo "=========================================="
    remove_user
    sleep 2

    # 步骤 4: 等待连接关闭
    echo ""
    echo "=========================================="
    echo "步骤 4: 等待所有连接关闭"
    echo "=========================================="
    log_info "等待 5 秒..."
    sleep 5

    # 步骤 5: 测试新连接（应该失败）
    echo ""
    echo "=========================================="
    echo "步骤 5: 测试新连接（预期：失败）"
    echo "=========================================="
    if ! test_connection "用户删除后的新连接" "false"; then
        log_error ""
        log_error "=========================================="
        log_error "测试失败"
        log_error "=========================================="
        log_error "RemoveUser 后新连接仍然成功"
        log_error "这意味着 RemoveUser 没有阻止新连接"
        exit 1
    fi

    # 测试通过
    echo ""
    echo "=========================================="
    echo "✅ 测试通过"
    echo "=========================================="
    echo ""
    log_info "结论："
    log_info "  RemoveUser 操作能够成功阻止新连接"
    log_info "  已有连接不会被断开（这是预期行为）"
    log_info "  满足需求：无需重启服务端即可禁用用户"
}

main
