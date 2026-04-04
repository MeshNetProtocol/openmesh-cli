#!/bin/bash
# 测试客户端连接

echo "=========================================="
echo "测试客户端连接"
echo "=========================================="
echo ""

# 测试函数
test_client() {
    local client_name=$1
    local proxy_port=$2
    local user_email=$3

    echo "测试 $client_name ($user_email)..."

    # 测试 1: 访问本地 IP 服务（验证代理连接）
    echo "  [本地测试]"
    response=$(curl -x http://127.0.0.1:$proxy_port \
        --silent \
        --max-time 5 \
        http://localhost:9999/ip 2>&1)

    if [ $? -eq 0 ]; then
        echo "    ✅ 本地连接成功: $response"
    else
        echo "    ❌ 本地连接失败: $response"
        return 1
    fi

    # 测试 2: 访问外部 IP 查询服务（获取真实出口 IP）
    echo "  [外网测试]"
    real_ip=$(curl -x http://127.0.0.1:$proxy_port \
        --silent \
        --max-time 10 \
        https://api.ipify.org 2>&1)

    if [ $? -eq 0 ]; then
        echo "    ✅ 外网连接成功"
        echo "    真实出口 IP: $real_ip"
        return 0
    else
        echo "    ❌ 外网连接失败: $real_ip"
        return 1
    fi
}

# 测试 Client 1
echo "1. 测试 Sing-box Client 1"
test_client "Client 1" 10801 "user1@test.com"
echo ""

# 测试 Client 2
echo "2. 测试 Sing-box Client 2"
test_client "Client 2" 10802 "user2@test.com"
echo ""

echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""
echo "提示："
echo "  - 访问 http://localhost:8080 管理用户"
echo "  - 在界面中禁用用户后，再次运行此脚本测试"
