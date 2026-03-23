#!/bin/bash
# 测试记账服务 API
# 用法: ./test-metering.sh

BASE_URL="http://127.0.0.1:9000"

echo "🧪 测试记账服务 API..."
echo ""

# 检查服务是否运行
echo "0. 健康检查..."
if ! curl -s $BASE_URL/health > /dev/null; then
    echo "  ❌ 记账服务未运行"
    echo "  请先启动服务: ./start-metering.sh"
    exit 1
fi
echo "  ✅ 服务正常运行"
echo ""

# 1. 添加用户 alice
echo "1. 添加用户 alice (购买 500MB 流量)..."
curl -s -X POST $BASE_URL/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"user_id":"alice","usdc_amount":5.0,"price_rate":100.0}' | python3 -m json.tool
echo ""

# 2. 查询用户
echo "2. 查询用户 alice..."
curl -s $BASE_URL/api/v1/users/alice | python3 -m json.tool
echo ""

# 3. 上报流量 (6MB)
echo "3. 上报流量 (上传 1MB, 下载 5MB)..."
curl -s -X POST $BASE_URL/api/v1/metering/report \
  -H "Content-Type: application/json" \
  -d '{"node_id":"node_a","user_id":"alice","upload_bytes":1048576,"download_bytes":5242880}' | python3 -m json.tool
echo ""

# 4. 再次查询用户
echo "4. 再次查询用户 (应该扣减了 6MB)..."
curl -s $BASE_URL/api/v1/users/alice | python3 -m json.tool
echo ""

# 5. 充值流量
echo "5. 充值 40MB..."
curl -s -X POST $BASE_URL/api/v1/users/alice/recharge \
  -H "Content-Type: application/json" \
  -d '{"amount_mb":40}' | python3 -m json.tool
echo ""

# 6. 查询统计
echo "6. 查询所有用户统计..."
curl -s $BASE_URL/api/v1/stats/users | python3 -m json.tool
echo ""

# 7. 添加更多用户
echo "7. 添加用户 bob 和 charlie..."
curl -s -X POST $BASE_URL/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"user_id":"bob","usdc_amount":3.0,"price_rate":100.0}' > /dev/null
curl -s -X POST $BASE_URL/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"user_id":"charlie","usdc_amount":2.0,"price_rate":100.0}' > /dev/null
echo "  ✅ 已添加 bob 和 charlie"
echo ""

# 8. 查询节点统计
echo "8. 查询节点统计..."
curl -s $BASE_URL/api/v1/stats/nodes | python3 -m json.tool
echo ""

echo "✅ 测试完成"
echo ""
echo "查看所有用户: curl $BASE_URL/api/v1/stats/users"
