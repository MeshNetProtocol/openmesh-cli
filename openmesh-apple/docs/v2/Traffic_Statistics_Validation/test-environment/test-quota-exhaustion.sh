#!/bin/bash
# 流量桶耗尽测试脚本
# 创建小配额用户，测试流量耗尽场景

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 流量桶耗尽测试"
echo "===================="
echo ""

# 测试用户配置
TEST_USER="quota_test_user"
QUOTA_MB=5  # 5MB 配额

echo "1️⃣ 创建测试用户 ($TEST_USER, ${QUOTA_MB}MB 配额)..."
RESULT=$(curl -s -X POST http://127.0.0.1:9000/api/v1/users \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"$TEST_USER\",\"usdc_amount\":0.05,\"price_rate\":100.0}")

if echo $RESULT | grep -q "user_id"; then
    echo "   ✅ 用户创建成功"
else
    echo "   ⚠️  用户可能已存在，继续测试"
fi
echo ""

# 查询初始状态
echo "2️⃣ 查询初始流量桶状态..."
STATS=$(curl -s http://127.0.0.1:9000/api/v1/users/$TEST_USER)
REMAINING=$(echo $STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['remaining'])")
REMAINING_MB=$(echo "scale=2; $REMAINING / 1024 / 1024" | bc)
echo "   剩余流量: ${REMAINING_MB}MB"
echo ""

# 模拟流量上报直到耗尽
echo "3️⃣ 模拟流量上报 (每次 2MB)..."
REPORT_COUNT=0
while true; do
    REPORT_COUNT=$((REPORT_COUNT + 1))

    # 上报 2MB 流量
    RESULT=$(curl -s -X POST http://127.0.0.1:9000/api/v1/metering/report \
        -H "Content-Type: application/json" \
        -d "{\"node_id\":\"test_node\",\"user_id\":\"$TEST_USER\",\"upload_bytes\":1048576,\"download_bytes\":1048576}")

    STATUS=$(echo $RESULT | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'unknown'))")
    ACTION=$(echo $RESULT | python3 -c "import sys, json; print(json.load(sys.stdin).get('action', 'unknown'))")
    REMAINING=$(echo $RESULT | python3 -c "import sys, json; print(json.load(sys.stdin).get('remaining', 0))")
    REMAINING_MB=$(echo "scale=2; $REMAINING / 1024 / 1024" | bc)

    echo "   上报 #$REPORT_COUNT: 状态=$STATUS, 动作=$ACTION, 剩余=${REMAINING_MB}MB"

    if [ "$STATUS" = "insufficient" ] || [ "$ACTION" = "block" ]; then
        echo ""
        echo "   ✅ 流量桶已耗尽，服务返回阻断指令"
        break
    fi

    if [ $REPORT_COUNT -ge 10 ]; then
        echo ""
        echo "   ⚠️  上报次数过多，测试终止"
        break
    fi

    sleep 1
done
echo ""

# 验证最终状态
echo "4️⃣ 验证最终状态..."
FINAL_STATS=$(curl -s http://127.0.0.1:9000/api/v1/users/$TEST_USER)
FINAL_REMAINING=$(echo $FINAL_STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['remaining'])")
FINAL_REMAINING_MB=$(echo "scale=2; $FINAL_REMAINING / 1024 / 1024" | bc)
USAGE_PERCENT=$(echo $FINAL_STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['usage_percent'])")

echo "   最终剩余: ${FINAL_REMAINING_MB}MB"
echo "   使用率: ${USAGE_PERCENT}%"
echo ""

if (( $(echo "$FINAL_REMAINING < 1048576" | bc -l) )); then
    echo "✅ 测试通过: 流量桶耗尽机制正常工作"
else
    echo "⚠️  测试失败: 流量桶未正确耗尽"
fi
