#!/bin/bash

# Phase 0.3 测试 1: 认证拒绝机制验证
# 目标: 验证认证 API 返回 {ok: false} 时，客户端无法建立连接

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Phase 0.3 测试 1: 认证拒绝机制验证"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试结果
PASSED=0
FAILED=0

# 测试函数
test_auth_reject() {
    local test_name="$1"
    local token="$2"
    local expected_result="$3"  # "success" or "fail"

    echo "----------------------------------------"
    echo "测试: $test_name"
    echo "Token: $token"
    echo "预期结果: $expected_result"
    echo ""

    # 创建临时配置文件
    local temp_config="/tmp/sing-box-test-$$.json"
    cat > "$temp_config" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 10801
    }
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "hysteria2-out",
      "server": "127.0.0.1",
      "server_port": 8443,
      "password": "$token",
      "tls": {
        "enabled": true,
        "insecure": true,
        "server_name": "localhost"
      }
    }
  ]
}
EOF

    # 启动 sing-box 客户端
    echo "启动 sing-box 客户端..."
    sing-box run -c "$temp_config" > /tmp/sing-box-test-$$.log 2>&1 &
    local sing_box_pid=$!

    # 等待启动
    sleep 3

    # 测试连接
    echo "测试连接..."
    if curl -x socks5://127.0.0.1:10801 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
        local result="success"
        echo -e "${GREEN}✓ 连接成功${NC}"
    else
        local result="fail"
        echo -e "${RED}✗ 连接失败${NC}"
    fi

    # 停止 sing-box
    kill $sing_box_pid 2>/dev/null || true
    wait $sing_box_pid 2>/dev/null || true

    # 检查日志
    echo ""
    echo "sing-box 日志片段:"
    tail -10 /tmp/sing-box-test-$$.log | grep -E "(auth|error|failed|success)" || echo "无相关日志"

    # 验证结果
    echo ""
    if [ "$result" = "$expected_result" ]; then
        echo -e "${GREEN}✓ 测试通过${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ 测试失败 (预期: $expected_result, 实际: $result)${NC}"
        FAILED=$((FAILED + 1))
    fi

    # 清理
    rm -f "$temp_config" /tmp/sing-box-test-$$.log

    echo ""
}

# 测试 1: 正常用户应该能连接
test_auth_reject "正常用户连接测试" "test_user_token_123" "success"

# 测试 2: 被封禁用户应该无法连接
test_auth_reject "被封禁用户连接测试" "test_blocked_token" "fail"

# 测试 3: 无效 token 应该无法连接
test_auth_reject "无效 token 连接测试" "invalid_token_xyz" "fail"

# 总结
echo "=========================================="
echo "测试总结"
echo "=========================================="
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过！${NC}"
    exit 0
else
    echo -e "${RED}✗ 有测试失败${NC}"
    exit 1
fi
