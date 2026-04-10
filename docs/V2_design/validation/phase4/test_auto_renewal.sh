#!/bin/bash

# 测试脚本 - 自动续费

BASE_URL="http://localhost:8080"

echo "🧪 Testing Auto-Renewal..."
echo ""

IDENTITY_ADDRESS="0x1234567890123456789012345678901234567890"

# 测试 1: 配置自动续费
echo "⚙️  Step 1: Setting up auto-renewal profile..."
curl -s -X POST ${BASE_URL}/poc/auto-renew/setup \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "'${IDENTITY_ADDRESS}'",
    "billing_account": "0xBillingSmartAccount1234567890123456789012",
    "spender_address": "0xAuthSpender1234567890123456789012345678",
    "permission_hash": "0xPermissionHash123456789012345678901234567890",
    "period_seconds": 604800
  }'
echo ""
echo ""

# 等待 1 秒
sleep 1

# 测试 2: 触发续费
echo "🔄 Step 2: Triggering renewal..."
curl -s -X POST ${BASE_URL}/poc/auto-renew/${IDENTITY_ADDRESS}/trigger
echo ""
echo ""

echo "✅ Test completed!"
echo "📊 Check the following file for results:"
echo "  - auto_renew_profiles.json"
