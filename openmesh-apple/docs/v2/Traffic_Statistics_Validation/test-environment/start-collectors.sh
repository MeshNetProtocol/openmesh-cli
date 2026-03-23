#!/bin/bash
# 启动所有节点的流量采集服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 启动流量采集服务..."

for node in node-a node-b node-c; do
    echo "启动 $node 流量采集..."
    cd "nodes/$node"
    python3 traffic-collector.py > logs/collector.log 2>&1 &
    PID=$!
    echo $PID > .collector.pid
    echo "  ✓ $node 采集服务已启动 (PID: $PID)"
    cd ../..
done

echo ""
echo "✅ 所有采集服务已启动"
echo ""
echo "查看日志:"
echo "  tail -f nodes/node-a/logs/collector.log"
echo "  tail -f nodes/node-b/logs/collector.log"
echo "  tail -f nodes/node-c/logs/collector.log"
echo ""
echo "停止所有采集服务: ./stop-collectors.sh"
