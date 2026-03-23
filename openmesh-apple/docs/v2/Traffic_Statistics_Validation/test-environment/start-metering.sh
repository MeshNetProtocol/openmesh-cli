#!/bin/bash
# 启动记账服务
# 用法: ./start-metering.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/metering-service"

echo "🚀 启动记账服务..."

# 检查 Python 依赖
if ! python3 -c "import flask" 2>/dev/null; then
    echo "⚠️  Flask 未安装，正在安装依赖..."
    pip3 install -r requirements.txt
fi

# 启动服务
python3 app.py > logs/metering.log 2>&1 &
echo $! > .pid

echo "  ✓ 记账服务已启动 (PID: $(cat .pid))"
echo ""
echo "服务地址: http://127.0.0.1:9000"
echo "健康检查: curl http://127.0.0.1:9000/health"
echo ""
echo "查看日志: tail -f metering-service/logs/metering.log"
echo "停止服务: ./stop-metering.sh"
