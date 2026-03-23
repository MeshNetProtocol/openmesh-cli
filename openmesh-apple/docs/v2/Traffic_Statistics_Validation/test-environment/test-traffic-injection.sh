#!/bin/bash
# 流量注入测试脚本
# 通过 SOCKS5 代理下载测试文件，产生真实流量

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 配置
SOCKS5_PROXY="socks5h://127.0.0.1:1080"
TEST_FILE_SERVER="http://127.0.0.1:8888"
SIZE=${1:-1}  # 默认 1MB

echo "🧪 流量注入测试"
echo "===================="
echo ""

# 检查 SOCKS5 代理是否可用
if ! lsof -i :1080 > /dev/null 2>&1; then
    echo "❌ SOCKS5 代理未运行 (端口 1080)"
    echo "   请先启动客户端: ./start-client.sh"
    exit 1
fi

echo "✓ SOCKS5 代理正在运行"

# 检查测试文件服务器是否运行
if ! curl -s --max-time 2 "$TEST_FILE_SERVER" > /dev/null 2>&1; then
    echo "❌ 测试文件服务器未运行"
    echo "   请在另一个终端启动: cd test-files && python3 -m http.server 8888"
    exit 1
fi

echo "✓ 测试文件服务器正在运行"
echo ""

# 选择测试文件
case $SIZE in
    1)
        FILE="test-1mb.bin"
        SIZE_MB=1
        ;;
    10)
        FILE="test-10mb.bin"
        SIZE_MB=10
        ;;
    50)
        FILE="test-50mb.bin"
        SIZE_MB=50
        ;;
    *)
        echo "❌ 无效的文件大小: $SIZE"
        echo "   用法: $0 [1|10|50]"
        exit 1
        ;;
esac

echo "📥 下载测试文件: $FILE (${SIZE_MB}MB)"
echo "   代理: $SOCKS5_PROXY"
echo "   服务器: $TEST_FILE_SERVER"
echo ""

# 记录开始时间
START_TIME=$(date +%s)

# 下载文件
OUTPUT_FILE="/tmp/downloaded-$FILE"
if curl -x "$SOCKS5_PROXY" \
    --progress-bar \
    -o "$OUTPUT_FILE" \
    "$TEST_FILE_SERVER/$FILE"; then

    # 记录结束时间
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # 验证文件大小
    DOWNLOADED_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
    DOWNLOADED_MB=$(echo "scale=2; $DOWNLOADED_SIZE / 1024 / 1024" | bc)

    echo ""
    echo "✅ 下载成功"
    echo "   文件大小: ${DOWNLOADED_MB}MB"
    echo "   耗时: ${DURATION}秒"
    echo "   平均速度: $(echo "scale=2; $DOWNLOADED_MB / $DURATION" | bc)MB/s"

    # 清理下载的文件
    rm "$OUTPUT_FILE"

    echo ""
    echo "💡 提示: 等待 10-15 秒后查看流量统计"
    echo "   ./view-database.sh"
    echo "   curl http://127.0.0.1:9000/api/v1/stats/users | python3 -m json.tool"
else
    echo ""
    echo "❌ 下载失败"
    exit 1
fi
