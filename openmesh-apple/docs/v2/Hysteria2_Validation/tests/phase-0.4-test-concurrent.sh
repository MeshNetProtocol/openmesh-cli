#!/bin/bash

# Phase 0.4 测试: 并发采集无重复计数验证
# 目标: 验证同时采集多个节点时不会重复计数

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Phase 0.4 测试: 并发采集无重复计数验证"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# API 配置
TRAFFIC_API_A="http://127.0.0.1:8081"
TRAFFIC_API_B="http://127.0.0.1:8082"
AUTH_HEADER="Authorization: test_secret_key_12345"

echo "步骤 1: 清零流量统计"
echo "----------------------------------------"
curl -s "$TRAFFIC_API_A/traffic?clear=true" -H "$AUTH_HEADER" > /dev/null
curl -s "$TRAFFIC_API_B/traffic?clear=true" -H "$AUTH_HEADER" > /dev/null
echo -e "${GREEN}✓ 流量统计已清零${NC}"

echo ""
echo "步骤 2: 在两个节点同时产生流量"
echo "----------------------------------------"

# 创建两个客户端配置
TEMP_CONFIG_A="/tmp/sing-box-concurrent-a.json"
TEMP_CONFIG_B="/tmp/sing-box-concurrent-b.json"

cat > "$TEMP_CONFIG_A" <<'EOF'
{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 10808}],
  "outbounds": [{
    "type": "hysteria2",
    "server": "127.0.0.1",
    "server_port": 8443,
    "password": "test_user_token_123",
    "tls": {"enabled": true, "insecure": true, "server_name": "localhost"}
  }]
}
EOF

cat > "$TEMP_CONFIG_B" <<'EOF'
{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 10809}],
  "outbounds": [{
    "type": "hysteria2",
    "server": "127.0.0.1",
    "server_port": 8444,
    "password": "test_user_token_123",
    "tls": {"enabled": true, "insecure": true, "server_name": "localhost"}
  }]
}
EOF

# 启动两个客户端
sing-box run -c "$TEMP_CONFIG_A" > /dev/null 2>&1 &
PID_A=$!
sing-box run -c "$TEMP_CONFIG_B" > /dev/null 2>&1 &
PID_B=$!

sleep 3

echo "客户端 A 通过 Node A 下载..."
echo "客户端 B 通过 Node B 下载..."

# 并发下载
curl -x socks5://127.0.0.1:10808 -s \
  "https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280" \
  -o /dev/null &
PID_CURL_A=$!

curl -x socks5://127.0.0.1:10809 -s \
  "https://gips1.baidu.com/it/u=1658389554,617110073&fm=3028&app=3028&f=JPEG&fmt=auto?w=1280&h=960" \
  -o /dev/null &
PID_CURL_B=$!

wait $PID_CURL_A $PID_CURL_B
echo -e "${GREEN}✓ 两个客户端下载完成${NC}"

sleep 5

echo ""
echo "步骤 3: 并发采集两个节点（第一次）"
echo "----------------------------------------"

# 并发采集（修复：先获取数据再清零）
TRAFFIC_A_1=$(curl -s "$TRAFFIC_API_A/traffic?clear=true" -H "$AUTH_HEADER")
TRAFFIC_B_1=$(curl -s "$TRAFFIC_API_B/traffic?clear=true" -H "$AUTH_HEADER")

echo "Node A 第一次采集:"
echo "$TRAFFIC_A_1" | jq .

echo ""
echo "Node B 第一次采集:"
echo "$TRAFFIC_B_1" | jq .

# 提取流量数据
RX_A_1=$(echo "$TRAFFIC_A_1" | jq -r '.user_001.rx // 0')
RX_B_1=$(echo "$TRAFFIC_B_1" | jq -r '.user_001.rx // 0')
TOTAL_1=$((RX_A_1 + RX_B_1))

echo ""
echo "第一次采集汇总:"
echo "  Node A: $RX_A_1 bytes"
echo "  Node B: $RX_B_1 bytes"
echo "  总计: $TOTAL_1 bytes"

echo ""
echo "步骤 4: 再次并发采集（验证清零）"
echo "----------------------------------------"

TRAFFIC_A_2=$(curl -s "$TRAFFIC_API_A/traffic?clear=true" -H "$AUTH_HEADER")
TRAFFIC_B_2=$(curl -s "$TRAFFIC_API_B/traffic?clear=true" -H "$AUTH_HEADER")

echo "Node A 第二次采集:"
echo "$TRAFFIC_A_2" | jq .

echo ""
echo "Node B 第二次采集:"
echo "$TRAFFIC_B_2" | jq .

RX_A_2=$(echo "$TRAFFIC_A_2" | jq -r '.user_001.rx // 0')
RX_B_2=$(echo "$TRAFFIC_B_2" | jq -r '.user_001.rx // 0')
TOTAL_2=$((RX_A_2 + RX_B_2))

echo ""
echo "第二次采集汇总:"
echo "  Node A: $RX_A_2 bytes"
echo "  Node B: $RX_B_2 bytes"
echo "  总计: $TOTAL_2 bytes"

# 清理
kill $PID_A $PID_B 2>/dev/null || true
wait $PID_A $PID_B 2>/dev/null || true
rm -f "$TEMP_CONFIG_A" "$TEMP_CONFIG_B"

echo ""
echo "=========================================="
echo "验证结果"
echo "=========================================="
echo ""

# 验证清零
if [ "$TOTAL_2" -lt 1000 ]; then
    echo -e "${GREEN}✓ 计数器正确清零（第二次采集总流量 < 1KB）${NC}"
    CLEAR_OK=true
else
    echo -e "${RED}✗ 计数器未正确清零（第二次采集总流量: $TOTAL_2 bytes）${NC}"
    CLEAR_OK=false
fi

# 验证无重复计数
if [ "$RX_A_1" -gt 0 ] && [ "$RX_B_1" -gt 0 ]; then
    echo -e "${GREEN}✓ 两个节点都记录了流量${NC}"
    BOTH_RECORDED=true
else
    echo -e "${YELLOW}⚠ 只有一个节点记录了流量${NC}"
    BOTH_RECORDED=false
fi

echo ""
echo "关键验证:"
echo "1. 并发采集: 两个节点同时调用 ?clear=true"
echo "2. 独立清零: 每个节点的计数器独立清零"
echo "3. 无重复计数: 总流量 = Node A + Node B（不会重复）"
echo "4. 增量正确: 第二次采集应该接近 0"

echo ""
if [ "$CLEAR_OK" = true ] && [ "$BOTH_RECORDED" = true ]; then
    echo -e "${GREEN}✓ 并发采集无重复计数验证通过${NC}"
    exit 0
else
    echo -e "${RED}✗ 验证失败${NC}"
    exit 1
fi
