#!/bin/bash

# 模拟 Mac 客户端生成订阅 URL 并打开浏览器
# 使用方法: ./mac_client_simulator.sh [identity_address]

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
WEB_PAGE_URL="http://localhost:8080/subscribe.html"
IDENTITY_ADDRESS="${1:-0x$(openssl rand -hex 20)}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Mac VPN 客户端 - 订阅模拟器${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}生成订阅 URL...${NC}"
echo "Identity Address: $IDENTITY_ADDRESS"
echo ""

# 生成完整的订阅 URL
SUBSCRIBE_URL="${WEB_PAGE_URL}?identity_address=${IDENTITY_ADDRESS}"

echo -e "${GREEN}订阅 URL 已生成:${NC}"
echo "$SUBSCRIBE_URL"
echo ""

echo -e "${YELLOW}正在打开浏览器...${NC}"

# 在 macOS 上打开默认浏览器
open "$SUBSCRIBE_URL"

echo -e "${GREEN}✓ 浏览器已打开${NC}"
echo ""
echo "请在浏览器中完成以下步骤:"
echo "1. 连接 MetaMask"
echo "2. 授权 Spend Permission"
echo "3. 确认首次支付"
echo ""
