#!/bin/bash
# 停止所有节点的流量采集服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 停止流量采集服务..."

for node in node-a node-b node-c; do
    PID_FILE="nodes/$node/.collector.pid"
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 $PID 2>/dev/null; then
            kill $PID
            echo "  ✓ $node 采集服务已停止 (PID: $PID)"
        else
            echo "  ⚠️  $node 采集服务未运行"
        fi
        rm "$PID_FILE"
    else
        echo "  ⚠️  $node 采集服务未运行"
    fi
done

echo ""
echo "✅ 所有采集服务已停止"
