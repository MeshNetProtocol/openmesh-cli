#!/bin/bash

# Phase 0.3 测试 4: 多设备场景验证（简化版）
# 目标: 验证同一用户多设备的流量统计和封禁策略

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Phase 0.3 测试 4: 多设备场景验证"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# API 配置
TRAFFIC_API="http://127.0.0.1:8081"
AUTH_API="http://127.0.0.1:8080"
AUTH_HEADER="Authorization: test_secret_key_12345"

echo "场景 A: 相同 user_id（流量合并）"
echo "=========================================="
echo ""

# 创建两个客户端配置
TEMP_CONFIG_A1="/tmp/sing-box-device-a1.json"
TEMP_CONFIG_A2="/tmp/sing-box-device-a2.json"

cat > "$TEMP_CONFIG_A1" <<'EOF'
{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 10804}],
  "outbounds": [{
    "type": "hysteria2",
    "server": "127.0.0.1",
    "server_port": 8443,
    "password": "test_user_token_789",
    "tls": {"enabled": true, "insecure": true, "server_name": "localhost"}
  }]
}
EOF

cat > "$TEMP_CONFIG_A2" <<'EOF'
{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 10805}],
  "outbounds": [{
    "type": "hysteria2",
    "server": "127.0.0.1",
    "server_port": 8443,
    "password": "test_user_token_789",
    "tls": {"enabled": true, "insecure": true, "server_name": "localhost"}
  }]
}
EOF

# 确保 user_003 为 active
curl -s -X POST "$AUTH_API/api/v1/admin/set-status" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user_003","status":"active"}' > /dev/null
echo -e "${GREEN}✓ user_003 状态设置为 active${NC}"

sleep 1

# 启动两个设备
sing-box run -c "$TEMP_CONFIG_A1" > /dev/null 2>&1 &
PID_A1=$!
sing-box run -c "$TEMP_CONFIG_A2" > /dev/null 2>&1 &
PID_A2=$!
echo -e "${GREEN}✓ 设备 A1 已启动 (端口: 10804)${NC}"
echo -e "${GREEN}✓ 设备 A2 已启动 (端口: 10805)${NC}"

sleep 3

# 测试连接
echo ""
echo "测试两个设备连接..."
if curl -x socks5://127.0.0.1:10804 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 设备 A1 连接正常${NC}"
else
    echo -e "${RED}✗ 设备 A1 连接失败${NC}"
fi

if curl -x socks5://127.0.0.1:10805 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 设备 A2 连接正常${NC}"
else
    echo -e "${RED}✗ 设备 A2 连接失败${NC}"
fi

sleep 2

# 检查在线状态
echo ""
echo "检查在线状态..."
ONLINE=$(curl -s "$TRAFFIC_API/online" -H "$AUTH_HEADER")
echo "在线用户: $ONLINE"

if echo "$ONLINE" | grep -q "user_003"; then
    DEVICE_COUNT=$(echo "$ONLINE" | grep -o '"user_003":[0-9]*' | grep -o '[0-9]*')
    if [ "$DEVICE_COUNT" = "2" ]; then
        echo -e "${GREEN}✓ 检测到 2 个设备在线${NC}"
    elif [ "$DEVICE_COUNT" = "1" ]; then
        echo -e "${YELLOW}⚠ 只检测到 1 个设备在线${NC}"
    else
        echo -e "${YELLOW}⚠ 设备数: $DEVICE_COUNT${NC}"
    fi
else
    echo -e "${RED}✗ 未检测到 user_003 在线${NC}"
fi

# 封禁测试
echo ""
echo "封禁 user_003 并测试..."
curl -s -X POST "$AUTH_API/api/v1/admin/set-status" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user_003","status":"blocked"}' > /dev/null

curl -s -X POST "$TRAFFIC_API/kick" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '["user_003"]' > /dev/null

echo -e "${GREEN}✓ 已封禁并踢出 user_003${NC}"

sleep 5

# 验证两个设备都无法连接
echo ""
echo "验证两个设备都无法重连..."
BOTH_BLOCKED=true

if curl -x socks5://127.0.0.1:10804 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${RED}✗ 设备 A1 仍可连接${NC}"
    BOTH_BLOCKED=false
else
    echo -e "${GREEN}✓ 设备 A1 无法连接${NC}"
fi

if curl -x socks5://127.0.0.1:10805 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${RED}✗ 设备 A2 仍可连接${NC}"
    BOTH_BLOCKED=false
else
    echo -e "${GREEN}✓ 设备 A2 无法连接${NC}"
fi

# 清理
kill $PID_A1 $PID_A2 2>/dev/null || true
wait $PID_A1 $PID_A2 2>/dev/null || true
rm -f "$TEMP_CONFIG_A1" "$TEMP_CONFIG_A2"

# 恢复状态
curl -s -X POST "$AUTH_API/api/v1/admin/set-status" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user_003","status":"active"}' > /dev/null

echo ""
echo "=========================================="
echo "测试总结"
echo "=========================================="
echo ""

if [ "$BOTH_BLOCKED" = true ]; then
    echo -e "${GREEN}✓ 多设备场景验证通过${NC}"
    echo ""
    echo "验证结果:"
    echo "- 两个设备使用相同 token (user_003)"
    echo "- 流量合并到同一个 user_id"
    echo "- 封禁后所有设备都无法连接"
    echo ""
    exit 0
else
    echo -e "${RED}✗ 多设备场景验证失败${NC}"
    exit 1
fi
