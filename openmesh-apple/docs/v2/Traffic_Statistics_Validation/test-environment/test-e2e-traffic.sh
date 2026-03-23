#!/bin/bash
# 端到端流量统计测试
# 测试完整的流量采集和上报流程

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 端到端流量统计测试"
echo "===================="
echo ""

# 检查记账服务是否运行
if ! curl -s http://127.0.0.1:9000/api/v1/stats/users > /dev/null 2>&1; then
    echo "❌ 记账服务未运行，请先启动: ./start-metering.sh"
    exit 1
fi

echo "✓ 记账服务正在运行"
echo ""

# 检查流量采集服务是否运行
COLLECTORS_RUNNING=0
for node in node-a node-b node-c; do
    if [ -f "nodes/$node/.collector.pid" ]; then
        PID=$(cat "nodes/$node/.collector.pid")
        if kill -0 $PID 2>/dev/null; then
            COLLECTORS_RUNNING=$((COLLECTORS_RUNNING + 1))
        fi
    fi
done

if [ $COLLECTORS_RUNNING -eq 0 ]; then
    echo "❌ 流量采集服务未运行，请先启动: ./start-collectors.sh"
    exit 1
fi

echo "✓ $COLLECTORS_RUNNING 个流量采集服务正在运行"
echo ""

# 查看初始状态
echo "📊 初始流量统计:"
echo "----------------------------------------"
curl -s http://127.0.0.1:9000/api/v1/stats/users | python3 -c "
import sys, json
data = json.load(sys.stdin)
for user in data['users']:
    used_mb = user['used'] / 1024 / 1024
    remaining_mb = user['remaining'] / 1024 / 1024
    print(f\"  {user['user_id']}: 已用{used_mb:.1f}MB 剩余{remaining_mb:.1f}MB ({user['usage_percent']:.1f}%)\")
"
echo ""

echo "⏳ 等待 15 秒，让采集服务上报流量..."
sleep 15

# 查看更新后的状态
echo ""
echo "📊 15秒后流量统计:"
echo "----------------------------------------"
curl -s http://127.0.0.1:9000/api/v1/stats/users | python3 -c "
import sys, json
data = json.load(sys.stdin)
for user in data['users']:
    used_mb = user['used'] / 1024 / 1024
    remaining_mb = user['remaining'] / 1024 / 1024
    print(f\"  {user['user_id']}: 已用{used_mb:.1f}MB 剩余{remaining_mb:.1f}MB ({user['usage_percent']:.1f}%)\")
"
echo ""

# 查看上报记录
echo "📈 最近的流量上报记录:"
echo "----------------------------------------"
./view-database.sh | grep -A 20 "📈 流量上报记录:"
echo ""

echo "✅ 测试完成"
echo ""
echo "查看实时日志:"
echo "  tail -f nodes/node-a/logs/collector.log"
echo "  tail -f metering-service/logs/metering.log"
