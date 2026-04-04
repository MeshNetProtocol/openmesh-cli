#!/bin/bash
# 生成流量测试脚本 - 通过下载文件生成流量

echo "=========================================="
echo "生成流量测试"
echo "=========================================="
echo ""

# 测试 URL（使用 HTTP 避免 TLS 问题）
TEST_URLS=(
    "http://httpbin.org/bytes/102400"  # 100KB 随机数据
    "http://httpbin.org/image/jpeg"    # JPEG 图片
    "http://httpbin.org/html"          # HTML 页面
)

# 测试函数
generate_traffic() {
    local client_name=$1
    local proxy_port=$2
    local count=$3

    echo "使用 $client_name (HTTP 代理端口 $proxy_port) 生成流量..."
    echo "  下载文件 $count 次..."
    echo ""

    local success=0
    local failed=0
    local total_bytes=0

    for i in $(seq 1 $count); do
        # 轮流使用不同的 URL
        url_index=$((($i - 1) % ${#TEST_URLS[@]}))
        url="${TEST_URLS[$url_index]}"
        
        echo -n "  [$i/$count] "
        
        # 使用 HTTP 代理下载（Sing-box mixed 模式支持 HTTP 和 SOCKS5）
        output=$(curl -x http://127.0.0.1:$proxy_port \
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
}

# 正确的端口配置
CLIENT1_PORT=10801  # Sing-box Client 1
CLIENT2_PORT=10802  # Sing-box Client 2
DOWNLOAD_COUNT=10

# 解析命令行参数
if [ $# -eq 0 ]; then
    # 默认为 Client 1 生成流量
    echo "为 Client 1 生成流量 (默认)..."
    echo "使用 -h 查看更多选项"
    echo ""
    generate_traffic "Client 1" $CLIENT1_PORT $DOWNLOAD_COUNT
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c1|--client1)
                echo "为 Client 1 生成流量..."
                generate_traffic "Client 1" $CLIENT1_PORT $DOWNLOAD_COUNT
                shift
                ;;
            -c2|--client2)
                echo "为 Client 2 生成流量..."
                generate_traffic "Client 2" $CLIENT2_PORT $DOWNLOAD_COUNT
                shift
                ;;
            -n|--count)
                DOWNLOAD_COUNT="$2"
                shift 2
                ;;
            -h|--help)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  -c1, --client1       为 Client 1 生成流量"
                echo "  -c2, --client2       为 Client 2 生成流量"
                echo "  -n, --count NUM      下载次数 (默认: 10)"
                echo "  -h, --help           显示帮助信息"
                echo ""
                echo "示例:"
                echo "  $0                   # 为 Client 1 生成流量 (默认)"
                echo "  $0 -c1               # 为 Client 1 生成流量"
                echo "  $0 -c1 -c2           # 为两个客户端生成流量"
                echo "  $0 -c1 -n 20         # 为 Client 1 下载 20 次"
                echo ""
                echo "注意: Client 1 使用端口 10801, Client 2 使用端口 10802"
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                echo "使用 -h 或 --help 查看帮助"
                exit 1
                ;;
        esac
    done
fi

echo "=========================================="
echo "流量生成完成"
echo "=========================================="
echo ""
echo "提示："
echo "  - 访问 http://localhost:8080 查看流量统计"
echo "  - 流量统计每 3 秒自动刷新"
echo "  - 每次下载约 30-100 KB"
echo ""
echo "如果下载失败，请检查："
echo "  1. Xray 服务是否正常运行: ps aux | grep xray"
echo "  2. Sing-box 客户端是否已启动: ps aux | grep sing-box"
echo "  3. 用户是否已在 Web 界面启用"
echo "  4. 测试连接: curl -x http://127.0.0.1:10801 http://httpbin.org/ip"
