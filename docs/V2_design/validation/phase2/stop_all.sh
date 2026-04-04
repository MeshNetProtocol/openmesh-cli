#!/bin/bash
# 停止所有服务

echo "=========================================="
echo "停止所有服务"
echo "=========================================="
echo ""

# 从 PID 文件读取并停止
if [ -f logs/pids.txt ]; then
    source logs/pids.txt

    echo "停止服务..."
    kill $XRAY_PID 2>/dev/null && echo "  ✓ Xray 已停止" || true
    kill $IP_SERVICE_PID 2>/dev/null && echo "  ✓ IP Service 已停止" || true
    kill $AUTH_SERVICE_PID 2>/dev/null && echo "  ✓ Auth Service 已停止" || true
    kill $SINGBOX1_PID 2>/dev/null && echo "  ✓ Sing-box Client 1 已停止" || true
    kill $SINGBOX2_PID 2>/dev/null && echo "  ✓ Sing-box Client 2 已停止" || true

    rm logs/pids.txt
fi

# 强制清理端口
echo ""
echo "清理端口..."
lsof -ti :10086 | xargs kill 2>/dev/null && echo "  ✓ 端口 10086 已清理" || true
lsof -ti :10085 | xargs kill 2>/dev/null && echo "  ✓ 端口 10085 已清理" || true
lsof -ti :10801 | xargs kill 2>/dev/null && echo "  ✓ 端口 10801 已清理" || true
lsof -ti :10802 | xargs kill 2>/dev/null && echo "  ✓ 端口 10802 已清理" || true
lsof -ti :8080 | xargs kill 2>/dev/null && echo "  ✓ 端口 8080 已清理" || true
lsof -ti :9999 | xargs kill 2>/dev/null && echo "  ✓ 端口 9999 已清理" || true

echo ""
echo "✅ 所有服务已停止"
