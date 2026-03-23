#!/bin/bash
# 流量验证测试脚本
# 产生已知大小的流量，验证统计准确性

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 流量验证测试"
echo "===================="
echo ""

# 检查服务状态
if ! curl -s http://127.0.0.1:9000/api/v1/stats/users > /dev/null 2>&1; then
    echo "❌ 记账服务未运行"
    exit 1
fi

if ! lsof -i :1080 > /dev/null 2>&1; then
    echo "❌ SOCKS5 代理未运行"
    exit 1
fi

echo "✓ 所有服务正在运行"
echo ""

# 获取当前用户（从客户端配置中提取）
CURRENT_USER=$(grep -A 5 "shadowsocks" client/config.json | grep "password" | head -1 | cut -d'"' -f4)
if [[ $CURRENT_USER == *"7TLKGXbFjuAYJsPTwNF/8A=="* ]]; then
    USER="alice"
elif [[ $CURRENT_USER == *"INFHA0S+FeS7DctzqnlP8w=="* ]]; then
    USER="bob"
elif [[ $CURRENT_USER == *"NasrqPMv9lR5YiSXvcpl0A=="* ]]; then
    USER="charlie"
else
    USER="alice"  # 默认
fi

echo "📊 当前用户: $USER"
echo ""

# 查询初始流量统计
echo "1️⃣ 查询初始流量统计..."
INITIAL_STATS=$(curl -s http://127.0.0.1:9000/api/v1/users/$USER)
INITIAL_USED=$(echo $INITIAL_STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['used'])")
INITIAL_MB=$(echo "scale=2; $INITIAL_USED / 1024 / 1024" | bc)
echo "   初始已用流量: ${INITIAL_MB}MB"
echo ""

# 下载测试文件
echo "2️⃣ 下载 10MB 测试文件..."
./test-traffic-injection.sh 10 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "   ❌ 下载失败"
    exit 1
fi
echo "   ✅ 下载完成"
echo ""

# 等待流量上报
echo "3️⃣ 等待流量上报 (15秒)..."
sleep 15
echo ""

# 查询更新后的流量统计
echo "4️⃣ 查询更新后的流量统计..."
FINAL_STATS=$(curl -s http://127.0.0.1:9000/api/v1/users/$USER)
FINAL_USED=$(echo $FINAL_STATS | python3 -c "import sys, json; print(json.load(sys.stdin)['used'])")
FINAL_MB=$(echo "scale=2; $FINAL_USED / 1024 / 1024" | bc)
echo "   最终已用流量: ${FINAL_MB}MB"
echo ""

# 计算流量增量
DELTA_BYTES=$((FINAL_USED - INITIAL_USED))
DELTA_MB=$(echo "scale=2; $DELTA_BYTES / 1024 / 1024" | bc)
echo "5️⃣ 流量增量分析:"
echo "   实际下载: 10.00MB"
echo "   统计增量: ${DELTA_MB}MB"
echo ""

# 计算误差
ERROR=$(echo "scale=2; ($DELTA_MB - 10) / 10 * 100" | bc)
ERROR_ABS=$(echo $ERROR | tr -d '-')

echo "6️⃣ 验证结果:"
if (( $(echo "$ERROR_ABS < 5" | bc -l) )); then
    echo "   ✅ 流量统计准确 (误差: ${ERROR}%)"
    echo ""
    echo "✅ 验证通过"
else
    echo "   ⚠️  流量统计误差较大 (误差: ${ERROR}%)"
    echo ""
    echo "⚠️  验证失败"
    exit 1
fi
