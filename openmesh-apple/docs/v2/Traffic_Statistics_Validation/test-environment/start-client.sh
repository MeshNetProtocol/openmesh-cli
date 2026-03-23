#!/bin/bash
# 启动 sing-box 客户端
# 用法: ./start-client.sh [node]
#   node: 可选，指定连接的节点 (node-a, node-b, node-c)，默认 node-a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/client"

NODE=${1:-node-a}

case $NODE in
    node-a)
        PORT=8001
        ;;
    node-b)
        PORT=8002
        ;;
    node-c)
        PORT=8003
        ;;
    *)
        echo "❌ 未知节点: $NODE"
        echo "用法: ./start-client.sh [node-a|node-b|node-c]"
        exit 1
        ;;
esac

echo "🚀 启动客户端，连接到 $NODE (端口 $PORT)..."
echo "   SOCKS5 代理: 127.0.0.1:1080"
echo "   用户: alice"
echo ""
echo "测试连接:"
echo "  curl -x socks5h://127.0.0.1:1080 https://www.google.com"
echo ""
echo "按 Ctrl+C 停止客户端"
echo ""

# 临时修改配置文件中的端口
sed -i.bak "s/\"server_port\": [0-9]*/\"server_port\": $PORT/" config.json

# 启动客户端（前台运行）
../sing-box run -c config.json

# 恢复配置文件
mv config.json.bak config.json
