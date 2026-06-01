#!/bin/bash
# 启动多 Xray 服务器测试环境

echo "=========================================="
echo "启动多 Xray 服务器测试环境"
echo "=========================================="
echo ""

# 清理现有进程
echo "清理现有进程..."
./stop_all.sh > /dev/null 2>&1

# 创建日志目录
mkdir -p logs

# 1. 启动第一个 Xray 服务器 (API: 10085, VLESS: 10086)
echo "1. 启动 Xray Server 1 (API: 10085, VLESS: 10086)..."
xray -c xray_server.json > logs/xray1.log 2>&1 &
XRAY1_PID=$!
echo "   PID: $XRAY1_PID"
echo $XRAY1_PID >> logs/pids.txt
sleep 1

# 2. 启动第二个 Xray 服务器 (API: 10086, VLESS: 10087)
echo "2. 启动 Xray Server 2 (API: 10086, VLESS: 10087)..."
xray -c xray_server2.json > logs/xray2.log 2>&1 &
XRAY2_PID=$!
echo "   PID: $XRAY2_PID"
echo $XRAY2_PID >> logs/pids.txt
sleep 1

# 3. 启动 IP Query Service
echo "3. 启动 IP Query Service..."
cd ip-service
go run main.go > ../logs/ip-service.log 2>&1 &
IP_PID=$!
echo "   PID: $IP_PID"
echo $IP_PID >> ../logs/pids.txt
cd ..
sleep 1

# 4. 启动 Auth Service (使用多服务器版本)
echo "4. 启动 Auth Service (Multi-Server)..."
cd auth-service
cp main_multi_server.go main.go
go build -o auth-service
./auth-service > ../logs/auth-service.log 2>&1 &
AUTH_PID=$!
echo "   PID: $AUTH_PID"
echo $AUTH_PID >> ../logs/pids.txt
cd ..
sleep 2

# 5. 启动 Sing-box Client 1 (连接到 Server 1)
echo "5. 启动 Sing-box Client 1 (连接到 Server 1: 10086)..."
sing-box run -c singbox_client1.json > logs/singbox1.log 2>&1 &
SINGBOX1_PID=$!
echo "   PID: $SINGBOX1_PID"
echo $SINGBOX1_PID >> logs/pids.txt
sleep 1

# 6. 创建 Sing-box Client 3 配置 (连接到 Server 2)
echo "6. 创建 Sing-box Client 3 (连接到 Server 2: 10087)..."
cat > singbox_client3.json << 'SINGBOX3'
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 10803
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "127.0.0.1",
      "server_port": 10087,
      "uuid": "11111111-1111-1111-1111-111111111111"
    }
  ]
}
SINGBOX3

sing-box run -c singbox_client3.json > logs/singbox3.log 2>&1 &
SINGBOX3_PID=$!
echo "   PID: $SINGBOX3_PID"
echo $SINGBOX3_PID >> logs/pids.txt
sleep 1

echo ""
echo "=========================================="
echo "✅ 所有服务启动成功"
echo "=========================================="
echo ""
echo "服务地址："
echo "  - Auth Service:  http://localhost:8080"
echo "  - IP Service:    http://localhost:9999"
echo "  - Xray Server 1: 127.0.0.1:10086 (API: 10085)"
echo "  - Xray Server 2: 127.0.0.1:10087 (API: 10086)"
echo "  - Sing-box 1:    127.0.0.1:10801 (→ Server 1)"
echo "  - Sing-box 3:    127.0.0.1:10803 (→ Server 2)"
echo ""
echo "下一步："
echo "  1. 访问 http://localhost:8080 查看多服务器流量统计"
echo "  2. 运行 ./generate_traffic.sh -c1 生成 Server 1 流量"
echo "  3. 运行 ./generate_traffic_server2.sh 生成 Server 2 流量"
echo "  4. 运行 ./stop_all.sh 停止所有服务"
echo ""
