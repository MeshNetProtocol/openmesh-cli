#!/bin/bash

# VPNSubscription 合约部署脚本
# 使用方法: ./deploy.sh

set -e

echo "🚀 开始部署 VPNSubscription 合约到 Base Sepolia..."
echo ""

# 检查 .env 文件
if [ ! -f .env ]; then
    echo "❌ 错误: .env 文件不存在"
    echo "请先复制 .env.example 到 .env 并填入配置"
    exit 1
fi

# 加载环境变量
source .env

# 检查必需的环境变量
if [ -z "$MNEMONIC" ] && [ -z "$PRIVATE_KEY" ]; then
    echo "❌ 错误: 必须配置 MNEMONIC 或 PRIVATE_KEY"
    exit 1
fi

if [ -z "$SERVICE_WALLET_ADDRESS" ]; then
    echo "❌ 错误: 必须配置 SERVICE_WALLET_ADDRESS"
    exit 1
fi

if [ -z "$RELAYER_ADDRESS" ]; then
    echo "❌ 错误: 必须配置 RELAYER_ADDRESS"
    exit 1
fi

echo "📋 部署配置:"
echo "  Service Wallet: $SERVICE_WALLET_ADDRESS"
echo "  Relayer: $RELAYER_ADDRESS"
echo "  Network: Base Sepolia"
echo ""

# 步骤 1: 模拟部署 (Dry Run)
echo "🔍 步骤 1/3: 模拟部署 (检查配置)..."
forge script script/DeployVPNSubscription.s.sol:DeployVPNSubscription \
    --rpc-url base_sepolia

if [ $? -ne 0 ]; then
    echo "❌ 模拟部署失败,请检查配置"
    exit 1
fi

echo ""
echo "✅ 模拟部署成功!"
echo ""

# 询问是否继续
read -p "是否继续实际部署? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 部署已取消"
    exit 0
fi

# 步骤 2: 实际部署
echo ""
echo "🚀 步骤 2/3: 部署合约到 Base Sepolia..."
forge script script/DeployVPNSubscription.s.sol:DeployVPNSubscription \
    --rpc-url base_sepolia \
    --broadcast \
    --verify

if [ $? -ne 0 ]; then
    echo "❌ 部署失败"
    exit 1
fi

echo ""
echo "✅ 合约部署成功!"
echo ""

# 步骤 3: 保存部署信息
echo "📝 步骤 3/3: 保存部署信息..."

# 从部署日志中提取合约地址
BROADCAST_DIR="broadcast/DeployVPNSubscription.s.sol/84532"
if [ -d "$BROADCAST_DIR" ]; then
    LATEST_RUN=$(ls -t $BROADCAST_DIR/run-latest.json 2>/dev/null || echo "")
    if [ -n "$LATEST_RUN" ]; then
        CONTRACT_ADDRESS=$(jq -r '.transactions[0].contractAddress' $LATEST_RUN 2>/dev/null || echo "")
        if [ -n "$CONTRACT_ADDRESS" ] && [ "$CONTRACT_ADDRESS" != "null" ]; then
            echo ""
            echo "=========================================="
            echo "🎉 部署完成!"
            echo "=========================================="
            echo ""
            echo "合约地址: $CONTRACT_ADDRESS"
            echo "网络: Base Sepolia"
            echo "BaseScan: https://sepolia.basescan.org/address/$CONTRACT_ADDRESS"
            echo ""
            echo "下一步:"
            echo "1. 在 BaseScan 上验证合约已部署"
            echo "2. 更新前端配置中的合约地址"
            echo "3. 更新后端配置中的合约地址"
            echo "4. 配置 CDP Paymaster 白名单"
            echo ""
        fi
    fi
fi

echo "✅ 部署流程完成!"
