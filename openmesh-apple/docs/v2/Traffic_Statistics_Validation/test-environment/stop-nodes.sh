#!/bin/bash
# 停止所有 sing-box 节点
# 用法: ./stop-nodes.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 停止 sing-box 节点..."

# 停止 node-a
if [ -f nodes/node-a/.pid ]; then
    PID=$(cat nodes/node-a/.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo "  ✓ node-a 已停止 (PID: $PID)"
    else
        echo "  ⚠ node-a 进程不存在 (PID: $PID)"
    fi
    rm nodes/node-a/.pid
else
    echo "  ⚠ node-a 未运行"
fi

# 停止 node-b
if [ -f nodes/node-b/.pid ]; then
    PID=$(cat nodes/node-b/.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo "  ✓ node-b 已停止 (PID: $PID)"
    else
        echo "  ⚠ node-b 进程不存在 (PID: $PID)"
    fi
    rm nodes/node-b/.pid
else
    echo "  ⚠ node-b 未运行"
fi

# 停止 node-c
if [ -f nodes/node-c/.pid ]; then
    PID=$(cat nodes/node-c/.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo "  ✓ node-c 已停止 (PID: $PID)"
    else
        echo "  ⚠ node-c 进程不存在 (PID: $PID)"
    fi
    rm nodes/node-c/.pid
else
    echo "  ⚠ node-c 未运行"
fi

echo ""
echo "✅ 所有节点已停止"
