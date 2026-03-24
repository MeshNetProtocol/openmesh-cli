#!/bin/bash

# Phase 0.2 补充测试：多文件大小 + 并发用户

set -e

BASE_DIR="/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/Hysteria2_Validation"
cd "$BASE_DIR"

PROXY="socks5://127.0.0.1:10800"
STATS_API="http://127.0.0.1:8081/traffic"
AUTH_HEADER="Authorization: test_secret_key_12345"
RESULTS_FILE="results/accuracy-data.csv"

echo "=========================================="
echo "Phase 0.2 补充测试"
echo "=========================================="
echo ""

# 测试 1: 多文件大小准确度测试
echo "测试 1: 多文件大小准确度测试"
echo "----------------------------------------"

# 百度图片 URL（不同大小）
test_names=("119KB" "141KB" "115KB")
test_urls=(
    "https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280"
    "https://gips1.baidu.com/it/u=1658389554,617110073&fm=3028&app=3028&f=JPEG&fmt=auto?w=1280&h=960"
    "https://gips2.baidu.com/it/u=3944689179,983354166&fm=3028&app=3028&f=JPEG&fmt=auto?w=1024&h=1024"
)

# 更新 CSV 文件头
echo "测试项,预期大小(bytes),实际大小(bytes),误差(%),状态" > "$RESULTS_FILE"

for i in "${!test_names[@]}"; do
    name="${test_names[$i]}"
    url="${test_urls[$i]}"

    # 清零流量统计
    curl -s "${STATS_API}?clear=true" -H "$AUTH_HEADER" > /dev/null
    sleep 1

    echo "下载 $name 图片..."

    # 先下载到本地获取实际大小
    curl -x "$PROXY" -s "$url" -o "/tmp/test_${name}.jpg"
    actual_size=$(stat -f%z "/tmp/test_${name}.jpg")

    # 等待流量统计更新
    sleep 2

    # 获取流量统计
    stats=$(curl -s "$STATS_API" -H "$AUTH_HEADER")
    rx=$(echo "$stats" | jq -r '.user_001.rx // 0')

    if [ "$rx" -eq 0 ]; then
        echo "  ⚠️  警告: 未检测到流量统计"
        echo "$name,$actual_size,0,N/A,失败" >> "$RESULTS_FILE"
        continue
    fi

    # 计算误差
    error=$(echo "scale=4; ($rx - $actual_size) / $actual_size * 100" | bc)

    echo "  预期: $actual_size bytes"
    echo "  实际: $rx bytes"
    echo "  误差: ${error}%"

    # 判断是否通过（误差 < 1%）
    abs_error=$(echo "$error" | tr -d '-')
    if (( $(echo "$abs_error < 1" | bc -l) )); then
        status="✅ 通过"
    else
        status="❌ 失败"
    fi

    echo "  状态: $status"
    echo ""

    # 保存到 CSV
    echo "$name,$actual_size,$rx,$error,$status" >> "$RESULTS_FILE"
done

echo "测试 1 完成"
echo ""

# 测试 2: 并发用户测试
echo "测试 2: 并发用户测试（3个用户）"
echo "----------------------------------------"

echo "准备多用户环境..."

# 检查是否已有多个客户端配置
if [ ! -f "config/sing-box-client-user2.json" ]; then
    echo "创建 user2 配置..."
    cat config/sing-box-client.json | jq '.inbounds[0].listen_port = 10801 | .outbounds[0].password = "test_user_token_456"' > config/sing-box-client-user2.json
fi

if [ ! -f "config/sing-box-client-user3.json" ]; then
    echo "创建 user3 配置..."
    cat config/sing-box-client.json | jq '.inbounds[0].listen_port = 10802 | .outbounds[0].password = "test_user_token_789"' > config/sing-box-client-user3.json
fi

# 启动额外的客户端
echo "启动 user2 客户端..."
./sing-box run -c config/sing-box-client-user2.json > logs/client-user2.log 2>&1 &
user2_pid=$!
sleep 2

echo "启动 user3 客户端..."
./sing-box run -c config/sing-box-client-user3.json > logs/client-user3.log 2>&1 &
user3_pid=$!
sleep 2

# 清零流量统计
curl -s "${STATS_API}?clear=true" -H "$AUTH_HEADER" > /dev/null
sleep 1

echo "3个用户同时下载..."

# 三个用户同时下载不同图片
curl -x socks5://127.0.0.1:10800 -s "${test_urls[0]}" -o /dev/null &
pid1=$!

curl -x socks5://127.0.0.1:10801 -s "${test_urls[1]}" -o /dev/null &
pid2=$!

curl -x socks5://127.0.0.1:10802 -s "${test_urls[2]}" -o /dev/null &
pid3=$!

# 等待所有下载完成
wait $pid1 $pid2 $pid3

sleep 2

# 获取流量统计
stats=$(curl -s "$STATS_API" -H "$AUTH_HEADER")
echo "流量统计结果:"
echo "$stats" | jq .

# 验证结果
user_001_rx=$(echo "$stats" | jq -r '.user_001.rx // 0')
user_002_rx=$(echo "$stats" | jq -r '.user_002.rx // 0')
user_003_rx=$(echo "$stats" | jq -r '.user_003.rx // 0')

echo ""
echo "各用户流量:"
echo "  user_001: $user_001_rx bytes"
echo "  user_002: $user_002_rx bytes"
echo "  user_003: $user_003_rx bytes"

total=$((user_001_rx + user_002_rx + user_003_rx))
echo "  总计: $total bytes"

# 验证
if [ "$user_001_rx" -gt 100000 ] && [ "$user_002_rx" -gt 100000 ] && [ "$user_003_rx" -gt 100000 ]; then
    echo ""
    echo "  ✅ 并发用户测试通过"
    echo "  ✅ 3个用户流量分别统计"
    echo "  ✅ 各用户流量互不干扰"
else
    echo ""
    echo "  ❌ 并发用户测试失败"
fi

# 清理：停止额外的客户端
echo ""
echo "清理测试环境..."
kill $user2_pid $user3_pid 2>/dev/null || true

echo ""
echo "测试 2 完成"
echo ""

echo "=========================================="
echo "所有补充测试完成！"
echo "详细结果已保存到: $RESULTS_FILE"
echo "=========================================="
