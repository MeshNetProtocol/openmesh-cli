#!/bin/bash

# 验证 VPNSubscription 合约部署
# 使用方法: ./verify_deployment.sh

set -e

# 加载环境变量
source ../.env

echo "🔍 验证 VPNSubscription 合约部署"
echo "=================================="
echo ""

echo "📋 合约信息:"
echo "  合约地址: $VPN_SUBSCRIPTION_CONTRACT"
echo "  USDC 地址: $USDC_CONTRACT"
echo "  Service Wallet: $SERVICE_WALLET_ADDRESS"
echo "  Relayer: $RELAYER_ADDRESS"
echo ""

echo "🔎 验证合约配置..."
echo ""

# 验证 USDC 地址
echo "1. 验证 USDC 地址:"
USDC_RESULT=$(cast call $VPN_SUBSCRIPTION_CONTRACT "usdc()" --rpc-url https://sepolia.base.org)
echo "   合约中的 USDC: $USDC_RESULT"
echo "   预期 USDC: $USDC_CONTRACT"
USDC_RESULT_LOWER=$(echo "$USDC_RESULT" | tr '[:upper:]' '[:lower:]')
USDC_CONTRACT_LOWER=$(echo "$USDC_CONTRACT" | tr '[:upper:]' '[:lower:]')
if [ "$USDC_RESULT_LOWER" = "$USDC_CONTRACT_LOWER" ]; then
    echo "   ✅ USDC 地址正确"
else
    echo "   ❌ USDC 地址不匹配"
fi
echo ""

# 验证 Service Wallet
echo "2. 验证 Service Wallet:"
SERVICE_RESULT=$(cast call $VPN_SUBSCRIPTION_CONTRACT "serviceWallet()" --rpc-url https://sepolia.base.org)
echo "   合约中的 Service Wallet: $SERVICE_RESULT"
echo "   预期 Service Wallet: $SERVICE_WALLET_ADDRESS"
SERVICE_RESULT_LOWER=$(echo "$SERVICE_RESULT" | tr '[:upper:]' '[:lower:]')
SERVICE_WALLET_LOWER=$(echo "$SERVICE_WALLET_ADDRESS" | tr '[:upper:]' '[:lower:]')
if [ "$SERVICE_RESULT_LOWER" = "$SERVICE_WALLET_LOWER" ]; then
    echo "   ✅ Service Wallet 正确"
else
    echo "   ❌ Service Wallet 不匹配"
fi
echo ""

# 验证 Relayer
echo "3. 验证 Relayer:"
RELAYER_RESULT=$(cast call $VPN_SUBSCRIPTION_CONTRACT "relayer()" --rpc-url https://sepolia.base.org)
echo "   合约中的 Relayer: $RELAYER_RESULT"
echo "   预期 Relayer: $RELAYER_ADDRESS"
RELAYER_RESULT_LOWER=$(echo "$RELAYER_RESULT" | tr '[:upper:]' '[:lower:]')
RELAYER_ADDRESS_LOWER=$(echo "$RELAYER_ADDRESS" | tr '[:upper:]' '[:lower:]')
if [ "$RELAYER_RESULT_LOWER" = "$RELAYER_ADDRESS_LOWER" ]; then
    echo "   ✅ Relayer 正确"
else
    echo "   ❌ Relayer 不匹配"
fi
echo ""

# 验证合约 owner
echo "4. 验证合约 Owner:"
OWNER_RESULT=$(cast call $VPN_SUBSCRIPTION_CONTRACT "owner()" --rpc-url https://sepolia.base.org)
echo "   合约 Owner: $OWNER_RESULT"
echo ""

# 检查 Relayer 余额
echo "5. 检查 Relayer ETH 余额:"
RELAYER_BALANCE=$(cast balance $RELAYER_ADDRESS --rpc-url https://sepolia.base.org)
RELAYER_BALANCE_ETH=$(echo "scale=6; $RELAYER_BALANCE / 1000000000000000000" | bc)
echo "   Relayer 余额: $RELAYER_BALANCE_ETH ETH"
if [ $(echo "$RELAYER_BALANCE > 0" | bc) -eq 1 ]; then
    echo "   ✅ Relayer 有 ETH 余额"
else
    echo "   ⚠️  Relayer 没有 ETH,需要充值才能执行自动续费"
    echo "   请从水龙头获取测试 ETH:"
    echo "   - https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet"
    echo "   - https://sepolia-faucet.base.org/"
fi
echo ""

echo "=================================="
echo "✅ 验证完成!"
echo ""
echo "📝 下一步:"
echo "1. 如果 Relayer 没有 ETH,请从水龙头获取测试币"
echo "2. 添加订阅计划: cast send \$VPN_SUBSCRIPTION_CONTRACT \"addPlan(string,uint256,uint256)\" \"weekly_test\" \"1000000\" \"604800\" --private-key \$PRIVATE_KEY --rpc-url https://sepolia.base.org"
echo "3. 启动后端服务: cd ../service && npm install && npm run dev"
echo ""
echo "🔗 在区块浏览器查看合约:"
echo "   https://sepolia.basescan.org/address/$VPN_SUBSCRIPTION_CONTRACT"
