#!/bin/bash

# 测试脚本 - 一次性订阅支付

BASE_URL="http://localhost:8080"

echo "🧪 Testing One-time Subscription Payment..."
echo ""

# 测试 1: 创建订阅请求
echo "📝 Step 1: Creating subscription request..."
RESPONSE=$(curl -s -X POST ${BASE_URL}/poc/subscriptions \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0x1234567890123456789012345678901234567890",
    "plan_id": "weekly_test"
  }')

echo "Response: $RESPONSE"
ORDER_ID=$(echo $RESPONSE | grep -o '"order_id":"[^"]*"' | cut -d'"' -f4)
echo "✅ Order ID: $ORDER_ID"
echo ""

# 等待 1 秒
sleep 1

# 测试 2: 激活订阅
echo "💳 Step 2: Activating subscription..."
curl -X POST ${BASE_URL}/poc/subscriptions/${ORDER_ID}/activate
echo ""
echo ""

echo "✅ Test completed!"
echo "📊 Check the following files for results:"
echo "  - subscription_requests.json"
echo "  - payments.json"
