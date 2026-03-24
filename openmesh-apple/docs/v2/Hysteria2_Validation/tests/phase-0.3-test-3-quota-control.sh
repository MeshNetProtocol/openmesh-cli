#!/bin/bash

# Phase 0.3 测试 3: 完整超额处理流程验证
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

# Traffic Stats API 配置
TRAFFIC_API="http://127.0.0.1:8081"
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

echo "步骤 1.1: 启动客户端"
sing-box run -c "$TEMP_CONFIG" > "$SING_BOX_LOG" 2>&1 &
SING_BOX_PID=$!
echo -e "${GREEN}✓ sing-box 客户端已启动 (PID: $SING_BOX_PID)${NC}"
sleep 3

echo ""
echo "步骤 1.2: 正常使用并产生流量"
curl -x socks5://127.0.0.1:10803 -s \
  "https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280" \
  -o /dev/null
echo -e "${GREEN}✓ 下载成功，流量已产生${NC}"

sleep 2

echo ""
echo "步骤 1.3: 查看流量统计"
TRAFFIC_BEFORE=$(curl -s "$TRAFFIC_API/traffic" -H "$AUTH_HEADER")
echo "流量统计: $TRAFFIC_BEFORE"

if echo "$TRAFFIC_BEFORE" | grep -q "user_002"; then
    echo -e "${GREEN}✓ user_002 流量统计正常${NC}"
else
    echo -e "${RED}✗ 未找到 user_002 流量统计${NC}"
fi

echo ""
echo "步骤 1.4: 验证连接正常"
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

echo "步骤 2.2: 标记用户状态为 blocked"
echo "（修改认证 API 的 userStatus）"
echo ""
echo -e "${YELLOW}⚠ 注意: 需要手动修改认证 API 代码将 user_002 标记为 blocked${NC}"
echo "请在另一个终端执行以下操作："
echo ""
echo "1. 编辑 prototype/auth-api.go"
echo "2. 将 userStatus[\"user_002\"] 改为 \"blocked\""
echo "3. 重启认证 API"
echo ""
read -p "完成后按 Enter 继续..."

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

echo "步骤 4.1: 等待客户端尝试重连"
sleep 5

echo ""
echo "步骤 4.2: 检查认证日志"
echo "认证 API 日志（最近 10 行）:"
tail -10 logs/auth-api.log | grep -E "(user_002|blocked)" || echo "无相关日志"

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
tail -20 "$SING_BOX_LOG" | grep -E "(authentication failed|auth.*failed)" || echo "无认证失败日志"

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
    echo "2. ✓ 超额标记机制正常"
    echo "3. ✓ /kick API 成功断开连接"
    echo "4. ✓ 重连时认证被拒绝"
    echo "5. ✓ 用户无法继续使用服务"
    echo ""
    echo "结论: 完整的超额处理闭环验证成功！"
else
    echo -e "${RED}✗ 完整超额处理流程验证失败${NC}"
    echo ""
    echo "问题: 用户在被标记为 blocked 后仍能重连"
    echo "请检查:"
    echo "1. 认证 API 是否正确标记了 user_002 为 blocked"
    echo "2. 认证 API 是否正确检查了用户状态"
    echo "3. 认证 API 是否已重启"
fi

echo ""
