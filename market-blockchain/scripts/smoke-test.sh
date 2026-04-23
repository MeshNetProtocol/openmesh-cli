#!/bin/bash
# 快速冒烟测试脚本

set -e

echo "=== Phase 2 服务冒烟测试 ==="

# 1. 检查编译
echo "1. 检查编译..."
cd market-blockchain
go build -o bin/server cmd/server/main.go
echo "✓ 编译成功"

# 2. 检查环境变量配置
echo ""
echo "2. 检查环境变量..."
if [ ! -f .env ]; then
    echo "⚠️  .env 文件不存在，请从 .env.example 复制并配置"
    exit 1
fi
echo "✓ .env 文件存在"

# 3. 启动服务（后台）
echo ""
echo "3. 启动服务..."
./bin/server &
SERVER_PID=$!
sleep 2

# 4. 健康检查
echo ""
echo "4. 测试健康检查 API..."
curl -s http://localhost:8080/health | jq .
if [ $? -eq 0 ]; then
    echo "✓ 健康检查通过"
else
    echo "✗ 健康检查失败"
    kill $SERVER_PID
    exit 1
fi

# 5. 测试套餐列表 API
echo ""
echo "5. 测试套餐列表 API..."
curl -s http://localhost:8080/api/v1/plans | jq .
if [ $? -eq 0 ]; then
    echo "✓ 套餐列表 API 响应正常"
else
    echo "✗ 套餐列表 API 失败"
fi

# 6. 停止服务
echo ""
echo "6. 停止服务..."
kill $SERVER_PID
echo "✓ 服务已停止"

echo ""
echo "=== 冒烟测试完成 ==="
