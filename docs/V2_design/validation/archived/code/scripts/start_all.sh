#!/bin/bash

# OpenMesh V2 准入控制 POC - 一键启动脚本

set -e

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "================================================"
echo "  OpenMesh V2 准入控制 POC - 组件启动"
echo "================================================"
echo ""

# 检查依赖
echo "检查环境依赖..."
command -v sing-box >/dev/null 2>&1 || { echo "错误: sing-box 未安装"; exit 1; }
command -v go >/dev/null 2>&1 || { echo "错误: go 未安装"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "错误: python3 未安装"; exit 1; }
echo "✓ 所有依赖已安装"
echo ""

# 显示 UUID 映射
echo "UUID 映射信息:"
python3 "$BASE_DIR/scripts/gen_uuid.py" | grep -A 1 "client_"
echo ""

# 提示用户
echo "准备启动以下组件:"
echo "  1. Auth Service (端口 8080)"
echo "  2. sing-box 服务端 (端口 10086, Clash API 9090)"
echo "  3. sing-box Client A (SOCKS 端口 1080)"
echo "  4. sing-box Client B (SOCKS 端口 1081)"
echo ""
echo "请在不同的终端窗口中运行以下命令:"
echo ""

echo "# 终端 1 - Auth Service"
echo "cd $BASE_DIR/auth-service"
echo "ALLOWED_IDS_PATH=../allowed_ids.json CONFIG_PATH=../singbox-server/config.json go run main.go"
echo ""

echo "# 终端 2 - 初始同步 (等待 Auth Service 启动后执行)"
echo "curl -X POST http://127.0.0.1:8080/v1/sync"
echo ""

echo "# 终端 3 - sing-box 服务端"
echo "cd $BASE_DIR"
echo "sing-box run -c singbox-server/config.json"
echo ""

echo "# 终端 4 - Client A"
echo "cd $BASE_DIR"
echo "sing-box run -c singbox-client-a/config.json"
echo ""

echo "# 终端 5 - Client B"
echo "cd $BASE_DIR"
echo "sing-box run -c singbox-client-b/config.json"
echo ""

echo "# 终端 6 - 运行测试 (等待所有组件启动后执行)"
echo "cd $BASE_DIR"
echo "bash scripts/test_all.sh"
echo ""

echo "================================================"
echo "提示: 请按顺序启动组件,确保前一个组件正常运行后再启动下一个"
echo "================================================"
