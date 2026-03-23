#!/bin/bash
# 节点切换测试脚本
# 验证用户在不同节点间切换时流量正确汇总

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 节点切换测试"
echo "===================="
echo ""

TEST_USER="alice"
DOWNLOAD_SIZE=5  # 5MB per node

echo "📊 测试场景: $TEST_USER 在 3 个节点间切换，每个节点下载 ${DOWNLOAD_SIZE}MB"
echo ""

# 查询初始状态
echo "1️⃣ 查询初始流量统计..."
INITIAL_STATS=$(curl -s http://127.0.0.1:9000/api/v1/users/$TEST_USER)
INITIAL_USED=$(echo $INITIAL_STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['used'])")
INITIAL_MB=$(echo "scale=2; $INITIAL_USED / 1024 / 1024" | bc)
echo "   初始已用流量: ${INITIAL_MB}MB"
echo ""

# 测试 node-a
echo "2️⃣ 在 node-a 下载 ${DOWNLOAD_SIZE}MB..."
./switch-user.sh alice > /dev/null 2>&1
pkill -f "sing-box run" 2>/dev/null
sleep 2
./start-client.sh node-a > /dev/null 2>&1 &
sleep 3
./test-traffic-injection.sh $DOWNLOAD_SIZE > /dev/null 2>&1
echo "   ✅ node-a 下载完成"
pkill -f "sing-box run" 2>/dev/null
sleep 2

# 测试 node-b
echo "3️⃣ 在 node-b 下载 ${DOWNLOAD_SIZE}MB..."
./start-client.sh node-b > /dev/null 2>&1 &
sleep 3
./test-traffic-injection.sh $DOWNLOAD_SIZE > /dev/null 2>&1
echo "   ✅ node-b 下载完成"
pkill -f "sing-box run" 2>/dev/null
sleep 2

# 测试 node-c
echo "4️⃣ 在 node-c 下载 ${DOWNLOAD_SIZE}MB..."
./start-client.sh node-c > /dev/null 2>&1 &
sleep 3
./test-traffic-injection.sh $DOWNLOAD_SIZE > /dev/null 2>&1
echo "   ✅ node-c 下载完成"
pkill -f "sing-box run" 2>/dev/null
echo ""

# 等待流量上报
echo "5️⃣ 等待流量上报 (20秒)..."
sleep 20
echo ""

# 查询最终状态
echo "6️⃣ 查询最终流量统计..."
FINAL_STATS=$(curl -s http://127.0.0.1:9000/api/v1/users/$TEST_USER)
FINAL_USED=$(echo $FINAL_STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['used'])")
FINAL_MB=$(echo "scale=2; $FINAL_USED / 1024 / 1024" | bc)
echo "   最终已用流量: ${FINAL_MB}MB"
echo ""

# 计算流量增量
DELTA_BYTES=$((FINAL_USED - INITIAL_USED))
DELTA_MB=$(echo "scale=2; $DELTA_BYTES / 1024 / 1024" | bc)
EXPECTED_MB=$((DOWNLOAD_SIZE * 3))

echo "7️⃣ 验证结果:"
echo "   预期增量: ${EXPECTED_MB}.00MB (3个节点 × ${DOWNLOAD_SIZE}MB)"
echo "   实际增量: ${DELTA_MB}MB"
echo ""

# 验证误差
ERROR=$(echo "scale=2; ($DELTA_MB - $EXPECTED_MB) / $EXPECTED_MB * 100" | bc)
ERROR_ABS=$(echo $ERROR | tr -d '-')

if (( $(echo "$ERROR_ABS < 10" | bc -l) )); then
    echo "✅ 测试通过: 多节点流量正确汇总 (误差: ${ERROR}%)"
else
    echo "⚠️  测试失败: 流量汇总误差较大 (误差: ${ERROR}%)"
fi
