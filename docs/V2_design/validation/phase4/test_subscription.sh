#!/bin/bash

# 测试订阅和续订流程
# 使用方法: ./test_subscription.sh [transaction_hash]

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 配置
AUTH_SERVICE_URL="http://localhost:8080"
IDENTITY_ADDRESS="${TEST_IDENTITY_ADDRESS:-0x1234567890123456789012345678901234567890}"
TRANSACTION_HASH="${1:-}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CDP 订阅支付测试流程${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 步骤 1: 创建订阅请求
echo -e "${YELLOW}步骤 1: 创建订阅请求${NC}"
echo "Identity Address: $IDENTITY_ADDRESS"
echo "Plan: weekly_test"
echo ""

SUBSCRIPTION_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions" \
  -H "Content-Type: application/json" \
  -d "{
    \"identity_address\": \"$IDENTITY_ADDRESS\",
    \"plan_id\": \"weekly_test\"
  }")

echo "Response:"
echo "$SUBSCRIPTION_RESPONSE" | jq '.'
echo ""

# 提取 order_id
ORDER_ID=$(echo "$SUBSCRIPTION_RESPONSE" | jq -r '.order_id')

if [ "$ORDER_ID" == "null" ] || [ -z "$ORDER_ID" ]; then
  echo -e "${RED}❌ 创建订阅失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 订阅请求创建成功: $ORDER_ID${NC}"
echo ""

# 步骤 2: x402 支付并激活订阅
echo -e "${YELLOW}步骤 2: x402 支付激活订阅${NC}"
echo "Order ID: $ORDER_ID"

if [ -z "$TRANSACTION_HASH" ]; then
  echo ""
  echo -e "${BLUE}请完成以下步骤:${NC}"
  echo "1. 使用你的钱包向服务地址发送 1 USDC"
  echo "   服务地址: ${SERVICE_WALLET_ADDRESS}"
  echo "   金额: 1.00 USDC"
  echo "   网络: base-sepolia"
  echo ""
  echo "2. 获取交易哈希后，运行:"
  echo "   ./test_subscription.sh 0xYourTransactionHash"
  echo ""
  exit 0
fi

echo "Transaction Hash: $TRANSACTION_HASH"
echo ""

ACTIVATE_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions/$ORDER_ID/activate" \
  -H "Content-Type: application/json" \
  -d "{
    \"transaction_hash\": \"$TRANSACTION_HASH\"
  }")

echo "Response:"
echo "$ACTIVATE_RESPONSE" | jq '.'
echo ""

SUCCESS=$(echo "$ACTIVATE_RESPONSE" | jq -r '.success')
if [ "$SUCCESS" != "true" ]; then
  echo -e "${RED}❌ 激活订阅失败${NC}"
  ERROR=$(echo "$ACTIVATE_RESPONSE" | jq -r '.error // .message // "Unknown error"')
  echo "错误: $ERROR"
  exit 1
fi

echo -e "${GREEN}✅ 订阅激活成功${NC}"
echo ""

# 步骤 3: 配置自动续费
echo -e "${YELLOW}步骤 3: 配置自动续费 (Spend Permission)${NC}"
echo "Identity Address: $IDENTITY_ADDRESS"
echo "Period: 7 天 (604800 秒)"
echo ""

BILLING_ACCOUNT="${TEST_BILLING_ACCOUNT:-0xBillingSmartAccount123456789012345678901234}"
SPENDER_ADDRESS="${SERVICE_WALLET_ADDRESS:-0xAuthSpender123456789012345678901234567890}"
PERMISSION_HASH="${TEST_PERMISSION_HASH:-0xpermission_$(date +%s)}"

echo -e "${BLUE}注意: 在配置自动续费之前，请确保:${NC}"
echo "1. 你已经在钱包中创建了 Spend Permission"
echo "2. 授权服务地址: $SPENDER_ADDRESS"
echo "3. 授权金额: 1.00 USDC"
echo "4. 授权周期: 604800 秒 (7 天)"
echo ""
read -p "按 Enter 继续，或 Ctrl+C 取消..."
echo ""

AUTO_RENEW_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/auto-renew/setup" \
  -H "Content-Type: application/json" \
  -d "{
    \"identity_address\": \"$IDENTITY_ADDRESS\",
    \"billing_account\": \"$BILLING_ACCOUNT\",
    \"spender_address\": \"$SPENDER_ADDRESS\",
    \"permission_hash\": \"$PERMISSION_HASH\",
    \"period_seconds\": 604800
  }")

echo "Response:"
echo "$AUTO_RENEW_RESPONSE" | jq '.'
echo ""

PROFILE_STATUS=$(echo "$AUTO_RENEW_RESPONSE" | jq -r '.status')
if [ "$PROFILE_STATUS" != "active" ]; then
  echo -e "${RED}❌ 配置自动续费失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 自动续费配置成功${NC}"
echo ""

# 步骤 4: 手动触发续费测试
echo -e "${YELLOW}步骤 4: 手动触发续费测试${NC}"
echo "Identity Address: $IDENTITY_ADDRESS"
echo ""
echo -e "${BLUE}注意: 这将执行真实的 Spend Permission 扣费${NC}"
read -p "按 Enter 继续，或 Ctrl+C 取消..."
echo ""

RENEW_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/auto-renew/$IDENTITY_ADDRESS/trigger" \
  -H "Content-Type: application/json")

echo "Response:"
echo "$RENEW_RESPONSE" | jq '.'
echo ""

RENEW_SUCCESS=$(echo "$RENEW_RESPONSE" | jq -r '.success')
if [ "$RENEW_SUCCESS" != "true" ]; then
  echo -e "${RED}❌ 触发续费失败${NC}"
  ERROR=$(echo "$RENEW_RESPONSE" | jq -r '.error // .message // "Unknown error"')
  echo "错误: $ERROR"
  exit 1
fi

RENEW_TX=$(echo "$RENEW_RESPONSE" | jq -r '.transaction_hash')
echo -e "${GREEN}✅ 续费触发成功${NC}"
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 所有测试通过!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "测试摘要:"
echo "  - 订单 ID: $ORDER_ID"
echo "  - Identity: $IDENTITY_ADDRESS"
echo "  - 订阅状态: active"
echo "  - 自动续费: enabled"
echo "  - 支付交易: $TRANSACTION_HASH"
echo "  - 续费交易: $RENEW_TX"
echo ""
echo "验证链上交易:"
echo "  - 支付: https://sepolia.basescan.org/tx/$TRANSACTION_HASH"
echo "  - 续费: https://sepolia.basescan.org/tx/$RENEW_TX"
echo ""
echo "查看数据文件:"
echo "  - subscription_requests.json"
echo "  - payments.json"
echo "  - auto_renew_profiles.json"
echo ""

