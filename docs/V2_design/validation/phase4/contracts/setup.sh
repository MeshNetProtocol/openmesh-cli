#!/bin/bash

# 交互式配置脚本 - 帮助设置 .env 文件

cd "$(dirname "$0")"

echo "================================"
echo "VPNSubscription 部署配置向导"
echo "================================"
echo ""

# 检查是否已有 .env 文件
if [ -f .env ]; then
    echo "⚠️  .env 文件已存在"
    read -p "是否覆盖? (y/n): " overwrite
    if [ "$overwrite" != "y" ]; then
        echo "已取消"
        exit 0
    fi
fi

# 复制模板
cp .env.example .env

echo ""
echo "请选择配置方式:"
echo "1. 使用助记词 (推荐 - 更安全)"
echo "2. 使用私钥"
echo ""
read -p "请选择 (1 或 2): " choice

if [ "$choice" = "1" ]; then
    echo ""
    echo "请输入你的 MetaMask 助记词 (12 或 24 个单词):"
    read -p "助记词: " mnemonic

    # 更新 .env 文件
    sed -i.bak "s|MNEMONIC=.*|MNEMONIC=\"$mnemonic\"|g" .env

    # 获取钱包地址
    echo ""
    echo "正在从助记词派生钱包地址..."
    address=$(cast wallet address --mnemonic "$mnemonic" --mnemonic-index 0 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "✅ 你的钱包地址: $address"
        echo ""
        echo "建议配置 (简化方案):"
        echo "  - SERVICE_WALLET_ADDRESS: $address (接收 USDC)"
        echo "  - RELAYER_ADDRESS: $address (发送交易)"
        echo ""
        read -p "是否使用此地址作为 SERVICE_WALLET 和 RELAYER? (y/n): " use_same

        if [ "$use_same" = "y" ]; then
            sed -i.bak "s|SERVICE_WALLET_ADDRESS=.*|SERVICE_WALLET_ADDRESS=$address|g" .env
            sed -i.bak "s|RELAYER_ADDRESS=.*|RELAYER_ADDRESS=$address|g" .env
            echo "✅ 配置已更新"
        fi
    else
        echo "❌ 无法从助记词派生地址,请检查助记词是否正确"
    fi

elif [ "$choice" = "2" ]; then
    echo ""
    echo "请输入你的 MetaMask 私钥 (不要包含 0x 前缀):"
    read -p "私钥: " private_key

    # 更新 .env 文件
    sed -i.bak "s|# PRIVATE_KEY=.*|PRIVATE_KEY=$private_key|g" .env
    sed -i.bak "s|MNEMONIC=.*|# MNEMONIC=your twelve word mnemonic phrase goes here|g" .env

    # 获取钱包地址
    echo ""
    echo "正在从私钥派生钱包地址..."
    address=$(cast wallet address --private-key $private_key 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "✅ 你的钱包地址: $address"
        echo ""
        read -p "是否使用此地址作为 SERVICE_WALLET 和 RELAYER? (y/n): " use_same

        if [ "$use_same" = "y" ]; then
            sed -i.bak "s|SERVICE_WALLET_ADDRESS=.*|SERVICE_WALLET_ADDRESS=$address|g" .env
            sed -i.bak "s|RELAYER_ADDRESS=.*|RELAYER_ADDRESS=$address|g" .env
            echo "✅ 配置已更新"
        fi
    else
        echo "❌ 无法从私钥派生地址,请检查私钥是否正确"
    fi
else
    echo "无效的选择"
    exit 1
fi

# 清理备份文件
rm -f .env.bak

echo ""
echo "================================"
echo "✅ 配置完成!"
echo "================================"
echo ""
echo "下一步:"
echo "1. 确保你的钱包有 Base Sepolia 测试 ETH"
echo "   水龙头: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet"
echo ""
echo "2. 运行部署命令:"
echo "   forge script script/DeployVPNSubscription.s.sol:DeployVPNSubscription \\"
echo "     --rpc-url base-sepolia \\"
echo "     --broadcast \\"
echo "     --verify"
echo ""
