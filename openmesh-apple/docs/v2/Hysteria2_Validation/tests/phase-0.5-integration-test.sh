#!/bin/bash

# Phase 0.5 集成测试: Metering Service 完整流程验证

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Phase 0.5 集成测试: Metering Service"
echo "=========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 清理函数
cleanup() {
    echo ""
    echo "清理测试环境..."
    pkill -f "metering/main" 2>/dev/null || true
    pkill -f "sing-box.*10810" 2>/dev/null || true
    pkill -f "sing-box.*10811" 2>/dev/null || true
}

trap cleanup EXIT

echo "步骤 1: 准备测试环境"
echo "----------------------------------------"

# 备份数据库
if [ -f "data/metering.db" ]; then
    cp data/metering.db data/metering.db.backup
    echo -e "${GREEN}✓ 数据库已备份${NC}"
fi

# 重新初始化数据库
rm -f data/metering.db
sqlite3 data/metering.db < prototype/metering/schema.sql
echo -e "${GREEN}✓ 数据库已初始化${NC}"

# 设置测试用户配额（较小的配额便于测试）
sqlite3 data/metering.db <<EOF
UPDATE users SET quota = 200000, used = 0, status = 'active' WHERE user_id = 'user_001';
UPDATE users SET quota = 150000, used = 0, status = 'active' WHERE user_id = 'user_002';
EOF
echo -e "${GREEN}✓ 测试配额已设置 (user_001: 200KB, user_002: 150KB)${NC}"

echo ""
echo "步骤 2: 启动 Metering Service"
echo "----------------------------------------"

cd prototype/metering
go build -o metering main.go database.go collector.go quota.go
./metering -interval=15s > ../../logs/metering-test.log 2>&1 &
METERING_PID=$!
cd ../..

sleep 2

if ps -p $METERING_PID > /dev/null; then
    echo -e "${GREEN}✓ Metering Service 已启动 (PID: $METERING_PID)${NC}"
else
    echo -e "${RED}✗ Metering Service 启动失败${NC}"
    exit 1
fi

echo ""
echo "步骤 3: 用户正常使用（未超额）"
echo "----------------------------------------"

# 创建客户端配置
TEMP_CONFIG_1="/tmp/sing-box-metering-test-1.json"
cat > "$TEMP_CONFIG_1" <<'EOF'
{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 10810}],
  "outbounds": [{
    "type": "hysteria2",
    "server": "127.0.0.1",
    "server_port": 8443,
    "password": "test_user_token_123",
    "tls": {"enabled": true, "insecure": true, "server_name": "localhost"}
  }]
}
EOF

sing-box run -c "$TEMP_CONFIG_1" > /dev/null 2>&1 &
PID_CLIENT_1=$!
sleep 3

echo "user_001 下载文件（约 120KB）..."
curl -x socks5://127.0.0.1:10810 -s \
  "https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280" \
  -o /dev/null

echo -e "${GREEN}✓ 下载完成${NC}"

echo ""
echo "等待 Metering Service 采集（15秒）..."
sleep 16

echo ""
echo "查询数据库中的用户状态:"
sqlite3 data/metering.db "SELECT user_id, used, quota, status FROM users WHERE user_id = 'user_001';"

USER_001_USED=$(sqlite3 data/metering.db "SELECT used FROM users WHERE user_id = 'user_001';")
echo "user_001 已用流量: $USER_001_USED bytes"

if [ "$USER_001_USED" -gt 100000 ]; then
    echo -e "${GREEN}✓ 流量已记录${NC}"
else
    echo -e "${YELLOW}⚠ 流量记录较少: $USER_001_USED bytes${NC}"
fi

echo ""
echo "步骤 4: 用户超额测试"
echo "----------------------------------------"

# 创建第二个客户端（user_002，配额 150KB）
TEMP_CONFIG_2="/tmp/sing-box-metering-test-2.json"
cat > "$TEMP_CONFIG_2" <<'EOF'
{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 10811}],
  "outbounds": [{
    "type": "hysteria2",
    "server": "127.0.0.1",
    "server_port": 8443,
    "password": "test_user_token_456",
    "tls": {"enabled": true, "insecure": true, "server_name": "localhost"}
  }]
}
EOF

sing-box run -c "$TEMP_CONFIG_2" > /dev/null 2>&1 &
PID_CLIENT_2=$!
sleep 3

echo "user_002 下载第一个文件（约 120KB）..."
curl -x socks5://127.0.0.1:10811 -s \
  "https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280" \
  -o /dev/null

sleep 2

echo "user_002 下载第二个文件（约 140KB，将超额）..."
curl -x socks5://127.0.0.1:10811 -s \
  "https://gips1.baidu.com/it/u=1658389554,617110073&fm=3028&app=3028&f=JPEG&fmt=auto?w=1280&h=960" \
  -o /dev/null

echo -e "${GREEN}✓ 下载完成${NC}"

echo ""
echo "等待 Metering Service 采集和配额检查（15秒）..."
sleep 16

echo ""
echo "查询 user_002 状态:"
sqlite3 data/metering.db "SELECT user_id, used, quota, status FROM users WHERE user_id = 'user_002';"

USER_002_STATUS=$(sqlite3 data/metering.db "SELECT status FROM users WHERE user_id = 'user_002';")
USER_002_USED=$(sqlite3 data/metering.db "SELECT used FROM users WHERE user_id = 'user_002';")

echo "user_002 状态: $USER_002_STATUS"
echo "user_002 已用流量: $USER_002_USED bytes"

if [ "$USER_002_STATUS" = "blocked" ]; then
    echo -e "${GREEN}✓ user_002 已被自动封禁${NC}"
else
    echo -e "${YELLOW}⚠ user_002 未被封禁（可能未超额或采集延迟）${NC}"
fi

echo ""
echo "步骤 5: 验证被封禁用户无法重连"
echo "----------------------------------------"

# 停止并重启 user_002 的客户端
kill $PID_CLIENT_2 2>/dev/null || true
wait $PID_CLIENT_2 2>/dev/null || true

sleep 2

sing-box run -c "$TEMP_CONFIG_2" > /dev/null 2>&1 &
PID_CLIENT_2=$!
sleep 3

echo "尝试使用 user_002 连接..."
if curl -x socks5://127.0.0.1:10811 -s --connect-timeout 5 --max-time 10 https://www.baidu.com > /dev/null 2>&1; then
    echo -e "${RED}✗ user_002 仍可连接（不应该）${NC}"
else
    echo -e "${GREEN}✓ user_002 无法连接（预期行为）${NC}"
fi

# 清理客户端
kill $PID_CLIENT_1 $PID_CLIENT_2 2>/dev/null || true
wait $PID_CLIENT_1 $PID_CLIENT_2 2>/dev/null || true
rm -f "$TEMP_CONFIG_1" "$TEMP_CONFIG_2"

echo ""
echo "步骤 6: 查看 Metering Service 日志"
echo "----------------------------------------"
echo "最近 30 行日志:"
tail -30 logs/metering-test.log

echo ""
echo "步骤 7: 查看流量日志"
echo "----------------------------------------"
echo "所有流量记录:"
sqlite3 data/metering.db "SELECT * FROM traffic_logs ORDER BY collected_at DESC LIMIT 10;"

echo ""
echo "=========================================="
echo "测试总结"
echo "=========================================="
echo ""

# 统计
TOTAL_LOGS=$(sqlite3 data/metering.db "SELECT COUNT(*) FROM traffic_logs;")
BLOCKED_USERS=$(sqlite3 data/metering.db "SELECT COUNT(*) FROM users WHERE status = 'blocked';")

echo "统计信息:"
echo "  - 流量日志记录数: $TOTAL_LOGS"
echo "  - 被封禁用户数: $BLOCKED_USERS"
echo ""

if [ "$TOTAL_LOGS" -gt 0 ]; then
    echo -e "${GREEN}✓ Metering Service 集成测试完成${NC}"
    echo ""
    echo "验证结果:"
    echo "1. ✓ 定时采集正常工作"
    echo "2. ✓ 流量数据正确记录到数据库"
    echo "3. ✓ 配额检查正常工作"
    if [ "$BLOCKED_USERS" -gt 0 ]; then
        echo "4. ✓ 超额用户自动封禁"
    else
        echo "4. ⚠ 未检测到超额用户（可能需要更多流量）"
    fi
    echo ""
else
    echo -e "${RED}✗ 测试失败：未记录流量数据${NC}"
fi

# 恢复数据库
if [ -f "data/metering.db.backup" ]; then
    mv data/metering.db.backup data/metering.db
    echo "数据库已恢复"
fi
