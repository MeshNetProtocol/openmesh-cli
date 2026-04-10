#!/bin/bash

# 测试订阅管理 API
# 使用方法: ./test_subscription_management.sh [identity_address]

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 配置
AUTH_SERVICE_URL="http://localhost:8080"
IDENTITY_ADDRESS="${1:-0x1234567890123456789012345678901234567890}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}订阅管理 API 测试${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 测试 1: 创建订阅
echo -e "${YELLOW}测试 1: 创建订阅${NC}"
echo "Identity Address: $IDENTITY_ADDRESS"
echo ""

CREATE_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions" \
  -H "Content-Type: application/json" \
  -d "{\"identity_address\": \"$IDENTITY_ADDRESS\", \"plan_id\": \"monthly\"}")

echo "响应:"
echo "$CREATE_RESPONSE" | jq '.'
echo ""

ORDER_ID=$(echo "$CREATE_RESPONSE" | jq -r '.order_id')
if [ "$ORDER_ID" == "null" ] || [ -z "$ORDER_ID" ]; then
  echo -e "${RED}❌ 创建订阅失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 订阅创建成功: $ORDER_ID${NC}"
echo ""

# 测试 2: 查询订阅信息
echo -e "${YELLOW}测试 2: 查询订阅信息${NC}"
echo ""

QUERY_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions/query" \
  -H "Content-Type: application/json" \
  -d "{\"identity_address\": \"$IDENTITY_ADDRESS\"}")

echo "响应:"
echo "$QUERY_RESPONSE" | jq '.'
echo ""

SUBSCRIPTION_STATUS=$(echo "$QUERY_RESPONSE" | jq -r '.subscription.status')
if [ "$SUBSCRIPTION_STATUS" == "null" ]; then
  echo -e "${RED}❌ 查询订阅失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 订阅查询成功，状态: $SUBSCRIPTION_STATUS${NC}"
echo ""

# 测试 3: 配置自动续费
echo -e "${YELLOW}测试 3: 配置自动续费${NC}"
echo ""

BILLING_ACCOUNT="0xBillingAccount$(date +%s)"
SPENDER_ADDRESS="0xServiceWallet123456789012345678901234567890"
PERMISSION_HASH="0xpermission_$(date +%s)"

SETUP_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/auto-renew/setup" \
  -H "Content-Type: application/json" \
  -d "{
    \"identity_address\": \"$IDENTITY_ADDRESS\",
    \"billing_account\": \"$BILLING_ACCOUNT\",
    \"spender_address\": \"$SPENDER_ADDRESS\",
    \"permission_hash\": \"$PERMISSION_HASH\",
    \"period_seconds\": 2592000
  }")

echo "响应:"
echo "$SETUP_RESPONSE" | jq '.'
echo ""

PROFILE_STATUS=$(echo "$SETUP_RESPONSE" | jq -r '.status')
if [ "$PROFILE_STATUS" != "active" ]; then
  echo -e "${RED}❌ 配置自动续费失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 自动续费配置成功${NC}"
echo ""

# 测试 4: 再次查询订阅（应该包含自动续费信息）
echo -e "${YELLOW}测试 4: 查询订阅（包含自动续费）${NC}"
echo ""

QUERY_RESPONSE2=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions/query" \
  -H "Content-Type: application/json" \
  -d "{\"identity_address\": \"$IDENTITY_ADDRESS\"}")

echo "响应:"
echo "$QUERY_RESPONSE2" | jq '.'
echo ""

HAS_AUTO_RENEW=$(echo "$QUERY_RESPONSE2" | jq 'has("auto_renew")')
if [ "$HAS_AUTO_RENEW" != "true" ]; then
  echo -e "${RED}❌ 自动续费信息未找到${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 订阅信息包含自动续费配置${NC}"
echo ""

# 测试 5: 取消订阅
echo -e "${YELLOW}测试 5: 取消订阅${NC}"
echo ""

CANCEL_RESPONSE=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions/cancel" \
  -H "Content-Type: application/json" \
  -d "{\"identity_address\": \"$IDENTITY_ADDRESS\"}")

echo "响应:"
echo "$CANCEL_RESPONSE" | jq '.'
echo ""

CANCEL_SUCCESS=$(echo "$CANCEL_RESPONSE" | jq -r '.success')
if [ "$CANCEL_SUCCESS" != "true" ]; then
  echo -e "${RED}❌ 取消订阅失败${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 订阅取消成功${NC}"
echo ""

# 测试 6: 查询已取消的订阅
echo -e "${YELLOW}测试 6: 查询已取消的订阅${NC}"
echo ""

QUERY_RESPONSE3=$(curl -s -X POST "$AUTH_SERVICE_URL/poc/subscriptions/query" \
  -H "Content-Type: application/json" \
  -d "{\"identity_address\": \"$IDENTITY_ADDRESS\"}")

echo "响应:"
echo "$QUERY_RESPONSE3" | jq '.'
echo ""

FINAL_STATUS=$(echo "$QUERY_RESPONSE3" | jq -r '.subscription.status')
if [ "$FINAL_STATUS" != "cancelled" ]; then
  echo -e "${RED}❌ 订阅状态未更新为 cancelled${NC}"
  exit 1
fi

HAS_AUTO_RENEW_AFTER=$(echo "$QUERY_RESPONSE3" | jq 'has("auto_renew")')
if [ "$HAS_AUTO_RENEW_AFTER" == "true" ]; then
  echo -e "${RED}❌ 自动续费配置未删除${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 订阅状态已更新为 cancelled，自动续费已删除${NC}"
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 所有测试通过!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "测试摘要:"
echo "  - 创建订阅: ✓"
echo "  - 查询订阅: ✓"
echo "  - 配置自动续费: ✓"
echo "  - 查询包含自动续费: ✓"
echo "  - 取消订阅: ✓"
echo "  - 验证取消状态: ✓"
echo ""
