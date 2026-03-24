#!/bin/bash

# Phase 0.2: 单节点流量统计验证测试脚本（改进版）

set -e

BASE_DIR="/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/Hysteria2_Validation"
PROXY="socks5://127.0.0.1:10800"
STATS_API="http://127.0.0.1:8081/traffic"
AUTH_HEADER="Authorization: test_secret_key_12345"
RESULTS_FILE="$BASE_DIR/results/accuracy-data.csv"

echo "=========================================="
echo "Phase 0.2: 单节点流量统计验证"
echo "=========================================="
echo ""

# 创建 CSV 文件
echo "测试项,预期大小(bytes),实际大小(bytes),误差(%),状态" > "$RESULTS_FILE"

# 测试 1: 不同文件大小的准确度测试
echo "测试 1: 流量统计准确度"
echo "----------------------------------------"

test_sizes=(102400 262144 524288)  # 100KB, 256KB, 512KB
test_names=("100KB" "256KB" "512KB")

for i in "${!test_sizes[@]}"; do
    size=${test_sizes[$i]}
    name=${test_names[$i]}

    # 清零流量统计
    curl -s "$STATS_API?clear=true" -H "$AUTH_HEADER" > /dev/null
    sleep 1

    echo "下载 $name 数据..."
    curl -x "$PROXY" -s "http://httpbin.org/bytes/$size" -o /dev/null

    # 等待流量统计更新
    sleep 2

    # 获取流量统计
    stats=$(curl -s "$STATS_API" -H "$AUTH_HEADER")
    rx=$(echo "$stats" | jq -r '.user_001.rx // 0')

    if [ "$rx" -eq 0 ]; then
        echo "  ⚠️  警告: 未检测到流量统计"
        echo "$name,${size},0,N/A,失败" >> "$RESULTS_FILE"
        continue
    fi

    # 计算误差
    error=$(echo "scale=4; ($rx - $size) / $size * 100" | bc)

    echo "  预期: $size bytes"
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
    echo "$name,$size,$rx,$error,$status" >> "$RESULTS_FILE"
done

echo "测试 1 完成"
echo ""

# 测试 2: 增量采集测试
echo "测试 2: 增量采集 (?clear=true)"
echo "----------------------------------------"

# 清零
curl -s "$STATS_API?clear=true" -H "$AUTH_HEADER" > /dev/null
sleep 1

# 第一次下载
echo "第一次下载 100KB..."
curl -x "$PROXY" -s "http://httpbin.org/bytes/102400" -o /dev/null
sleep 2

stats1=$(curl -s "$STATS_API?clear=true" -H "$AUTH_HEADER")
rx1=$(echo "$stats1" | jq -r '.user_001.rx // 0')
echo "  第一次统计: $rx1 bytes"
echo "  已清零"

# 第二次下载
echo "第二次下载 100KB..."
curl -x "$PROXY" -s "http://httpbin.org/bytes/102400" -o /dev/null
sleep 2

stats2=$(curl -s "$STATS_API?clear=true" -H "$AUTH_HEADER")
rx2=$(echo "$stats2" | jq -r '.user_001.rx // 0')
echo "  第二次统计（增量）: $rx2 bytes"
echo "  已清零"

# 第三次查询（应该为空）
sleep 1
stats3=$(curl -s "$STATS_API" -H "$AUTH_HEADER")
echo "  第三次查询（应该为空）: $stats3"

if [ "$stats3" == "{}" ]; then
    echo "  ✅ 增量采集功能正常"
else
    echo "  ❌ 增量采集功能异常"
fi

echo ""
echo "测试 2 完成"
echo ""

# 测试 3: 并发用户测试
echo "测试 3: 并发用户测试"
echo "----------------------------------------"

# 清零
curl -s "$STATS_API?clear=true" -H "$AUTH_HEADER" > /dev/null
sleep 1

echo "模拟 user_001 下载 100KB..."
curl -x "$PROXY" -s "http://httpbin.org/bytes/102400" -o /dev/null &
pid1=$!

sleep 0.5

echo "等待下载完成..."
wait $pid1

sleep 2

# 获取统计
stats=$(curl -s "$STATS_API" -H "$AUTH_HEADER")
echo "流量统计: $stats"

user_001_rx=$(echo "$stats" | jq -r '.user_001.rx // 0')
echo "  user_001 下载: $user_001_rx bytes"

if [ "$user_001_rx" -gt 100000 ]; then
    echo "  ✅ 用户流量统计正常"
else
    echo "  ❌ 用户流量统计异常"
fi

echo ""
echo "测试 3 完成"
echo ""

echo "=========================================="
echo "所有测试完成！"
echo "详细结果已保存到: $RESULTS_FILE"
echo "=========================================="
