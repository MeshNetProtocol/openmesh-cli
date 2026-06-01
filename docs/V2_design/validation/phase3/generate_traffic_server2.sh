#!/bin/bash
# 为 Server 2 生成流量测试脚本

echo "=========================================="
echo "为 Server 2 生成流量测试"
echo "=========================================="
echo ""

# 测试 URL
TEST_URLS=(
    "http://httpbin.org/bytes/102400"
    "http://httpbin.org/image/jpeg"
    "http://httpbin.org/html"
)

CLIENT_PORT=10803
DOWNLOAD_COUNT=${1:-10}

echo "使用 Client 3 (HTTP 代理端口 $CLIENT_PORT) 连接到 Server 2..."
echo "  下载文件 $DOWNLOAD_COUNT 次..."
echo ""

success=0
failed=0
total_bytes=0

for i in $(seq 1 $DOWNLOAD_COUNT); do
    url_index=$((($i - 1) % ${#TEST_URLS[@]}))
    url="${TEST_URLS[$url_index]}"
    
    echo -n "  [$i/$DOWNLOAD_COUNT] "
    
    output=$(curl -x http://127.0.0.1:$CLIENT_PORT \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out "%{http_code}|%{size_download}" \
        --max-time 10 \
        "$url" 2>&1)
    
    if [ $? -eq 0 ]; then
        http_code=$(echo "$output" | cut -d'|' -f1)
        size=$(echo "$output" | cut -d'|' -f2)
        
        if [ "$http_code" = "200" ]; then
            echo "✅ 下载成功 (HTTP $http_code, $size bytes)"
            ((success++))
            total_bytes=$((total_bytes + size))
        else
            echo "⚠️  HTTP $http_code"
            ((failed++))
        fi
    else
        echo "❌ 下载失败: $output"
        ((failed++))
    fi
    
    sleep 0.5
done

# 格式化总流量
if [ $total_bytes -gt 1048576 ]; then
    total_mb=$(echo "scale=2; $total_bytes / 1048576" | bc)
    total_str="${total_mb} MB"
elif [ $total_bytes -gt 1024 ]; then
    total_kb=$(echo "scale=2; $total_bytes / 1024" | bc)
    total_str="${total_kb} KB"
else
    total_str="${total_bytes} bytes"
fi

echo ""
echo "  统计: 成功 $success, 失败 $failed, 总流量 $total_str"
echo ""

echo "=========================================="
echo "流量生成完成"
echo "=========================================="
echo ""
echo "提示："
echo "  - 访问 http://localhost:8080 查看流量统计"
echo "  - Server-2 列应该显示新增的流量"
echo "  - Total Traffic 列应该显示所有服务器的总流量"
