#!/bin/bash
# 启动所有 sing-box 节点
# 用法: ./start-nodes.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 启动 sing-box 节点..."

# 启动 node-a
echo "启动 node-a (端口 8001)..."
cd nodes/node-a
../../sing-box run -c config.json > logs/sing-box.log 2>&1 &
echo $! > .pid
echo "  ✓ node-a 已启动 (PID: $(cat .pid))"
cd ../..

# 启动 node-b
echo "启动 node-b (端口 8002)..."
cd nodes/node-b
../../sing-box run -c config.json > logs/sing-box.log 2>&1 &
echo $! > .pid
echo "  ✓ node-b 已启动 (PID: $(cat .pid))"
cd ../..

# 启动 node-c
echo "启动 node-c (端口 8003)..."
cd nodes/node-c
../../sing-box run -c config.json > logs/sing-box.log 2>&1 &
echo $! > .pid
echo "  ✓ node-c 已启动 (PID: $(cat .pid))"
cd ../..

echo ""
echo "✅ 所有节点已启动"
echo ""
echo "检查节点状态:"
ps aux | grep "[s]ing-box run" | grep -v grep

echo ""
echo "查看日志:"
echo "  tail -f nodes/node-a/logs/sing-box.log"
echo "  tail -f nodes/node-b/logs/sing-box.log"
echo "  tail -f nodes/node-c/logs/sing-box.log"
echo ""
echo "停止所有节点: ./stop-nodes.sh"
