#!/bin/bash
# 一键测试脚本 - RemoveUser 验证

set -e

echo "=========================================="
echo "Xray RemoveUser 验证测试"
echo "=========================================="
echo ""

# 停止现有进程
echo "清理现有进程..."
lsof -ti :10086 | xargs kill 2>/dev/null || true
lsof -ti :10085 | xargs kill 2>/dev/null || true
lsof -ti :1081 | xargs kill 2>/dev/null || true
sleep 2

# 启动服务端（带用户）
echo "启动 Xray 服务端（带测试用户）..."
xray -c xray_server_vless.json > xray_test.log 2>&1 &
SERVER_PID=$!
sleep 3

if ! lsof -i :10086 > /dev/null 2>&1; then
    echo "❌ 服务端启动失败"
    cat xray_test.log
    exit 1
fi
echo "✅ 服务端启动成功 (PID: $SERVER_PID)"
echo ""

# 测试 1: 用户存在时的连接
echo "=========================================="
echo "测试 1: 用户存在时的连接（预期：成功）"
echo "=========================================="
xray -c vless_client.json > /tmp/client.log 2>&1 &
CLIENT_PID=$!
sleep 3

if curl -x socks5://127.0.0.1:1081 -m 10 --silent --head http://www.baidu.com > /dev/null 2>&1; then
    echo "✅ 连接成功"
    TEST1_PASS=1
else
    echo "❌ 连接失败"
    TEST1_PASS=0
fi

kill $CLIENT_PID 2>/dev/null || true
sleep 2
echo ""

# 删除用户
echo "=========================================="
echo "删除用户"
echo "=========================================="
xray api rmu --server=127.0.0.1:10085 -tag=vless-in "test-validation@example.com"
echo "✅ 用户已删除"
sleep 2
echo ""

# 测试 2: 用户删除后的连接
echo "=========================================="
echo "测试 2: 用户删除后的连接（预期：失败）"
echo "=========================================="
xray -c vless_client.json > /tmp/client.log 2>&1 &
CLIENT_PID=$!
sleep 3

if curl -x socks5://127.0.0.1:1081 -m 10 --silent --head http://www.baidu.com > /dev/null 2>&1; then
    echo "❌ 连接成功（不符合预期）"
    TEST2_PASS=0
else
    echo "✅ 连接失败（符合预期）"
    TEST2_PASS=1
fi

kill $CLIENT_PID 2>/dev/null || true
kill $SERVER_PID 2>/dev/null || true
echo ""

# 结果
echo "=========================================="
echo "测试结果"
echo "=========================================="
if [ $TEST1_PASS -eq 1 ] && [ $TEST2_PASS -eq 1 ]; then
    echo "✅ 测试通过"
    echo ""
    echo "结论："
    echo "  RemoveUser 能够成功阻止新连接"
    echo "  验证完成"
    exit 0
else
    echo "❌ 测试失败"
    [ $TEST1_PASS -eq 0 ] && echo "  - 初始连接失败（应该成功）"
    [ $TEST2_PASS -eq 0 ] && echo "  - 删除后连接成功（应该失败）"
    echo ""
    echo "查看日志: cat xray_test.log"
    exit 1
fi
