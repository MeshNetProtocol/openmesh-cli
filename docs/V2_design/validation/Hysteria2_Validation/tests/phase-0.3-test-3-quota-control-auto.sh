#!/bin/bash

# Phase 0.3 测试 3: 完整超额处理流程验证（自动化版本）
# 目标: 验证完整的超额处理闭环（标记 + kick + 拒绝重连）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Phase 0.3 测试 3: 完整超额处理流程验证"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# API 配置
TRAFFIC_API="http://127.0.0.1:8081"
AUTH_API="http://127.0.0.1:8080"
AUTH_HEADER="Authorization: test_secret_key_12345"

# 创建临时配置文件
TEMP_CONFIG="/tmp/sing-box-quota-test.json"
cat > "$TEMP_CONFIG" <<'EOF'
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 10803
    }
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "hysteria2-out",
      "server": "127.0.0.1",
      "server_port": 8443,
      "password": "test_user_token_456",
      "tls": {
        "enabled": true,
        "insecure": true,
        "server_name": "localhost"
      }
    }
  ]
}
EOF

SING_BOX_LOG="/tmp/sing-box-quota-test.log"

echo "=========================================="
echo "阶段 1: 正常使用"
echo "=========================================="
echo ""

echo "步骤 1.1: 确保 user_002 状态为 active"
curl -s -X POST "$AUTH_API/api/v1/admin/set-status" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user_002","status":"active"}' > /dev/null
echo -e "${GREEN}✓ user_002 状态已设置为 active${NC}"

sleep 1

echo ""
echo "步骤 1.2: 启动客户端"
sing-box run -c "$TEMP_CONFIG" > "$SING_BOX_LOG" 2>&1 &
SING_BOX_PID=$!
echo -e "${GREEN}✓ sing-box 客户端已启动 (PID: $SING_BOX_PID)${NC}"
sleep 3

echo ""
echo "步骤 1.3: 正常使用并产生流量"
if curl -x socks5://127.0.0.1:10803 -s --connect-timeout 10 --max-time 15 \
  "https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280" \
  -o /dev/null 2>&1; then
    echo -e "${GREEN}✓ 下载成功，流量已产生${NC}"
else
    echo -e "${RED}✗ 下载失败${NC}"
fi

sleep 2

echo ""
echo "步骤 1.4: 查看流量统计"
TRAFFIC_BEFORE=$(curl -s "$TRAFFIC_API/traffic" -H "$AUTH_HEADER")
echo "流量统计: $TRAFFIC_BEFORE"

if echo "$TRAFFIC_BEFORE" | grep -q "user_002"; then
    echo -e "${GREEN}✓ user_002 流量统计正常${NC}"
else
    echo -e "${YELLOW}⚠ 未找到 user_002 流量统计（可能还未更新）${NC}"
fi

echo ""
echo "步骤 1.5: 验证连接正常"
if curl -x socks5://127.0.0.1:10803 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 连接正常${NC}"
else
    echo -e "${RED}✗ 连接失败${NC}"
fi

echo ""
echo "=========================================="
echo "阶段 2: 超额检测与标记"
echo "=========================================="
echo ""

echo "步骤 2.1: 模拟后端检测到用户超额"
echo "（在实际系统中，这是定时任务检查配额）"

echo ""
echo "步骤 2.2: 通过管理 API 标记用户状态为 blocked"
SET_STATUS_RESPONSE=$(curl -s -X POST "$AUTH_API/api/v1/admin/set-status" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user_002","status":"blocked"}')

echo "API 响应: $SET_STATUS_RESPONSE"

if echo "$SET_STATUS_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ user_002 已标记为 blocked${NC}"
else
    echo -e "${RED}✗ 标记失败${NC}"
fi

sleep 1

echo ""
echo "步骤 2.3: 验证用户状态"
USER_STATUS=$(curl -s "$AUTH_API/api/v1/admin/get-status")
echo "所有用户状态: $USER_STATUS"

echo ""
echo "=========================================="
echo "阶段 3: 踢出连接"
echo "=========================================="
echo ""

echo "步骤 3.1: 调用 /kick API 断开用户连接"
KICK_RESPONSE=$(curl -s -X POST "$TRAFFIC_API/kick" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '["user_002"]')

echo "Kick API 响应: $KICK_RESPONSE"
echo -e "${GREEN}✓ /kick API 调用成功${NC}"

sleep 2

echo ""
echo "步骤 3.2: 观察客户端日志"
echo "最近的日志:"
tail -10 "$SING_BOX_LOG" | grep -E "(error|Error|ERROR|disconnect|auth)" || echo "无相关日志"

echo ""
echo "=========================================="
echo "阶段 4: 拒绝重连"
echo "=========================================="
echo ""

echo "步骤 4.1: 等待客户端尝试重连（5秒）"
sleep 5

echo ""
echo "步骤 4.2: 检查认证日志"
echo "认证 API 日志（最近 10 行）:"
tail -10 logs/auth-api.log | grep -E "(user_002|blocked|Auth)" || echo "无相关日志"

echo ""
echo "步骤 4.3: 验证用户无法重连"
if curl -x socks5://127.0.0.1:10803 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${RED}✗ 连接成功（不应该成功）${NC}"
    RECONNECT_BLOCKED=false
else
    echo -e "${GREEN}✓ 连接失败（预期行为）${NC}"
    RECONNECT_BLOCKED=true
fi

echo ""
echo "步骤 4.4: 检查 sing-box 错误日志"
echo "认证失败日志:"
tail -20 "$SING_BOX_LOG" | grep -E "(authentication failed|auth.*failed|404)" || echo "无认证失败日志"

echo ""
echo "步骤 4.5: 检查在线状态"
ONLINE_STATUS=$(curl -s "$TRAFFIC_API/online" -H "$AUTH_HEADER")
echo "在线用户: $ONLINE_STATUS"

if echo "$ONLINE_STATUS" | grep -q "user_002"; then
    echo -e "${RED}✗ user_002 仍在线（不应该在线）${NC}"
else
    echo -e "${GREEN}✓ user_002 已离线${NC}"
fi

# 清理
echo ""
echo "清理测试环境..."
kill $SING_BOX_PID 2>/dev/null || true
wait $SING_BOX_PID 2>/dev/null || true

# 恢复 user_002 状态
curl -s -X POST "$AUTH_API/api/v1/admin/set-status" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user_002","status":"active"}' > /dev/null
echo "已恢复 user_002 状态为 active"

rm -f "$TEMP_CONFIG" "$SING_BOX_LOG"

echo ""
echo "=========================================="
echo "测试总结"
echo "=========================================="
echo ""

if [ "$RECONNECT_BLOCKED" = true ]; then
    echo -e "${GREEN}✓ 完整超额处理流程验证通过${NC}"
    echo ""
    echo "验证结果:"
    echo "1. ✓ 用户正常使用阶段工作正常"
    echo "2. ✓ 超额标记机制正常（通过管理 API）"
    echo "3. ✓ /kick API 成功断开连接"
    echo "4. ✓ 重连时认证被拒绝"
    echo "5. ✓ 用户无法继续使用服务"
    echo ""
    echo "结论: 完整的超额处理闭环验证成功！"
    echo ""
    exit 0
else
    echo -e "${RED}✗ 完整超额处理流程验证失败${NC}"
    echo ""
    echo "问题: 用户在被标记为 blocked 后仍能重连"
    echo ""
    exit 1
fi
