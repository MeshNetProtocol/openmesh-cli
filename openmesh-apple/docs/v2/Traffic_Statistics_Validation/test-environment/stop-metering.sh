#!/bin/bash
# 停止记账服务
# 用法: ./stop-metering.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 停止记账服务..."

if [ -f metering-service/.pid ]; then
    PID=$(cat metering-service/.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo "  ✓ 记账服务已停止 (PID: $PID)"
    else
        echo "  ⚠️  记账服务进程不存在 (PID: $PID)"
    fi
    rm metering-service/.pid
else
    echo "  ⚠️  记账服务未运行"
fi

echo ""
echo "✅ 完成"
