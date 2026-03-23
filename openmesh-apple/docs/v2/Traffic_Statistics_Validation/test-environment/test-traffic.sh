#!/bin/bash
# 测试流量代理
# 用法: ./test-traffic.sh

echo "🧪 测试 sing-box 代理连接..."
echo ""

# 检查客户端是否运行
if ! lsof -i :1080 > /dev/null 2>&1; then
    echo "❌ SOCKS5 代理未运行 (端口 1080)"
    echo "请先启动客户端: ./start-client.sh"
    exit 1
fi

echo "✓ SOCKS5 代理正在运行"
echo ""

# 测试 1: 访问 Google
echo "测试 1: 访问 Google..."
if curl -x socks5h://127.0.0.1:1080 -s -o /dev/null -w "%{http_code}" https://www.google.com | grep -q "200"; then
    echo "  ✅ 成功"
else
    echo "  ❌ 失败"
fi
echo ""

# 测试 2: 下载小文件
echo "测试 2: 下载 1MB 测试文件..."
START_TIME=$(date +%s)
if curl -x socks5h://127.0.0.1:1080 -s -o /dev/null https://speed.cloudflare.com/1mb; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    echo "  ✅ 成功 (耗时: ${DURATION}s)"
else
    echo "  ❌ 失败"
fi
echo ""

# 测试 3: 获取 IP 地址
echo "测试 3: 获取出口 IP..."
IP=$(curl -x socks5h://127.0.0.1:1080 -s https://api.ipify.org)
if [ -n "$IP" ]; then
    echo "  ✅ 出口 IP: $IP"
else
    echo "  ❌ 获取失败"
fi
echo ""

echo "✅ 测试完成"
echo ""
echo "查看节点日志:"
echo "  tail -f nodes/node-a/logs/sing-box.log"
