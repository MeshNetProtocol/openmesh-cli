#!/bin/bash
# 快速启动 Xray 服务端并运行测试

echo "=========================================="
echo "Xray RemoveUser 测试 - 快速启动"
echo "=========================================="
echo ""

# 检查是否已有 Xray 在运行
if lsof -i :10086 > /dev/null 2>&1; then
    echo "⚠️  检测到端口 10086 已被占用"
    echo "请先停止现有的 Xray 进程，或者运行："
    echo "  lsof -ti :10086 | xargs kill"
    echo ""
    read -p "是否自动停止现有进程？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        lsof -ti :10086 | xargs kill
        sleep 2
    else
        exit 1
    fi
fi

# 启动 Xray 服务端
echo "🚀 启动 Xray 服务端..."
xray -c xray_server.json > xray_server.log 2>&1 &
XRAY_PID=$!

echo "   服务端 PID: $XRAY_PID"
echo "   日志文件: xray_server.log"
echo ""

# 等待服务端启动
echo "⏳ 等待服务端启动..."
sleep 3

# 检查服务端是否正常运行
if ! lsof -i :10086 > /dev/null 2>&1; then
    echo "❌ 服务端启动失败"
    echo "请查看日志: cat xray_server.log"
    exit 1
fi

if ! lsof -i :10085 > /dev/null 2>&1; then
    echo "❌ gRPC API 启动失败"
    echo "请查看日志: cat xray_server.log"
    kill $XRAY_PID
    exit 1
fi

echo "✅ 服务端启动成功"
echo ""

# 运行测试
echo "=========================================="
echo "运行测试"
echo "=========================================="
echo ""

./test_xray_remove_user.sh
TEST_RESULT=$?

# 停止服务端
echo ""
echo "🛑 停止 Xray 服务端..."
kill $XRAY_PID
wait $XRAY_PID 2>/dev/null

if [ $TEST_RESULT -eq 0 ]; then
    echo ""
    echo "✅ 测试完成，服务端已停止"
    exit 0
else
    echo ""
    echo "❌ 测试失败，服务端已停止"
    echo "请查看日志: cat xray_server.log"
    exit 1
fi
