#!/bin/bash

# 从助记词获取钱包地址的辅助脚本

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "错误: .env 文件不存在"
    echo "请先复制 .env.example 到 .env 并填入你的助记词"
    exit 1
fi

source .env

if [ -z "$MNEMONIC" ] || [ "$MNEMONIC" = "your twelve word mnemonic phrase goes here" ]; then
    echo "错误: 请在 .env 文件中配置你的助记词"
    exit 1
fi

echo "正在从助记词派生钱包地址..."
echo ""

# 获取钱包地址
ADDRESS=$(cast wallet address --mnemonic "$MNEMONIC" --mnemonic-index ${MNEMONIC_INDEX:-0})

echo "你的钱包地址: $ADDRESS"
echo ""
echo "建议配置:"
echo "  SERVICE_WALLET_ADDRESS=$ADDRESS"
echo "  RELAYER_ADDRESS=$ADDRESS"
echo ""
echo "这样你的钱包既接收 USDC 支付,也作为 Relayer 发送交易"
