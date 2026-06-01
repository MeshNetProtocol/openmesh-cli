#!/bin/bash
# 启动所有服务

set -e

echo "=========================================="
echo "Phase 2: 启动所有服务"
echo "=========================================="
echo ""

# 停止现有进程
echo "清理现有进程..."
lsof -ti :10086 | xargs kill 2>/dev/null || true
lsof -ti :10085 | xargs kill 2>/dev/null || true
lsof -ti :10801 | xargs kill 2>/dev/null || true
lsof -ti :10802 | xargs kill 2>/dev/null || true
lsof -ti :8080 | xargs kill 2>/dev/null || true
lsof -ti :9999 | xargs kill 2>/dev/null || true
sleep 2

# 检查依赖
echo "检查依赖..."
command -v xray >/dev/null 2>&1 || { echo "❌ xray 未安装"; exit 1; }
command -v sing-box >/dev/null 2>&1 || { echo "❌ sing-box 未安装"; exit 1; }
command -v go >/dev/null 2>&1 || { echo "❌ go 未安装"; exit 1; }
echo "✅ 依赖检查通过"
echo ""

# 1. 启动 Xray 服务端
echo "1. 启动 Xray 服务端..."
xray -c xray_server.json > logs/xray.log 2>&1 &
XRAY_PID=$!
echo "   PID: $XRAY_PID"
sleep 2

if ! lsof -i :10086 > /dev/null 2>&1; then
    echo "❌ Xray 启动失败"
    cat logs/xray.log
    exit 1
fi
echo "✅ Xray 服务端启动成功"
echo ""

# 2. 启动 IP Query Service
echo "2. 启动 IP Query Service..."
cd ip-service
go run main.go > ../logs/ip-service.log 2>&1 &
IP_SERVICE_PID=$!
cd ..
echo "   PID: $IP_SERVICE_PID"
sleep 3

if ! lsof -i :9999 > /dev/null 2>&1; then
    echo "❌ IP Service 启动失败"
    cat logs/ip-service.log
    exit 1
fi
echo "✅ IP Query Service 启动成功"
echo ""

# 3. 启动 Auth Service
echo "3. 启动 Auth Service..."
cd auth-service
go run main.go > ../logs/auth-service.log 2>&1 &
AUTH_SERVICE_PID=$!
cd ..
echo "   PID: $AUTH_SERVICE_PID"
sleep 2

if ! lsof -i :8080 > /dev/null 2>&1; then
    echo "❌ Auth Service 启动失败"
    cat logs/auth-service.log
    exit 1
fi
echo "✅ Auth Service 启动成功"
echo ""

# 4. 启动 Sing-box Client 1
echo "4. 启动 Sing-box Client 1..."
sing-box run -c singbox_client1.json > logs/singbox1.log 2>&1 &
SINGBOX1_PID=$!
echo "   PID: $SINGBOX1_PID"
sleep 2

if ! lsof -i :10801 > /dev/null 2>&1; then
    echo "❌ Sing-box Client 1 启动失败"
    cat logs/singbox1.log
    exit 1
fi
echo "✅ Sing-box Client 1 启动成功"
echo ""

# 5. 启动 Sing-box Client 2
echo "5. 启动 Sing-box Client 2..."
sing-box run -c singbox_client2.json > logs/singbox2.log 2>&1 &
SINGBOX2_PID=$!
echo "   PID: $SINGBOX2_PID"
sleep 2

if ! lsof -i :10802 > /dev/null 2>&1; then
    echo "❌ Sing-box Client 2 启动失败"
    cat logs/singbox2.log
    exit 1
fi
echo "✅ Sing-box Client 2 启动成功"
echo ""

# 保存 PID
cat > logs/pids.txt <<EOF
XRAY_PID=$XRAY_PID
IP_SERVICE_PID=$IP_SERVICE_PID
AUTH_SERVICE_PID=$AUTH_SERVICE_PID
SINGBOX1_PID=$SINGBOX1_PID
SINGBOX2_PID=$SINGBOX2_PID
EOF

echo "=========================================="
echo "✅ 所有服务启动成功"
echo "=========================================="
echo ""
echo "服务地址："
echo "  - Auth Service:  http://localhost:8080"
echo "  - IP Service:    http://localhost:9999"
echo "  - Xray Server:   127.0.0.1:10086"
echo "  - Sing-box 1:    127.0.0.1:10801 (user1@test.com)"
echo "  - Sing-box 2:    127.0.0.1:10802 (user2@test.com)"
echo ""
echo "下一步："
echo "  1. 访问 http://localhost:8080 管理用户"
echo "  2. 运行 ./test_clients.sh 测试连接"
echo "  3. 运行 ./stop_all.sh 停止所有服务"
