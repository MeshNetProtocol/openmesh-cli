#!/bin/bash

# OpenMesh V2 准入控制 POC 自动化测试脚本

set -e

# 配置
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWED_IDS="$BASE_DIR/allowed_ids.json"
AUTH_SERVICE_URL="http://localhost:8080"
TEST_URL="http://httpbin.org/ip"
CLIENT_A_SOCKS="127.0.0.1:1080"
CLIENT_B_SOCKS="127.0.0.1:1081"
CLIENT_A_ADDR="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CLIENT_B_ADDR="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 统计
PASS_COUNT=0
FAIL_COUNT=0

# 工具函数
log_info() {
    echo -e "${YELLOW}▶${NC} $1"
}

log_pass() {
    echo -e "  ${GREEN}✅ PASS:${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "  ${RED}❌ FAIL:${NC} $1"
    ((FAIL_COUNT++))
}

# 测试 curl 连接
try_curl() {
    local socks="$1"
    if curl -sS --max-time 8 --socks5 "$socks" "$TEST_URL" > /dev/null 2>&1; then
        echo "ok"
    else
        echo "fail"
    fi
}

# 检查结果
check() {
    local label="$1"
    local expect_ok="$2"
    local result="$3"

    if [ "$expect_ok" = "true" ] && [ "$result" = "ok" ]; then
        log_pass "$label"
    elif [ "$expect_ok" = "false" ] && [ "$result" = "fail" ]; then
        log_pass "$label (正确被拒绝)"
    else
        log_fail "$label (期望: $expect_ok, 实际: $result)"
    fi
}

# 备份配置
backup_config() {
    cp "$ALLOWED_IDS" "$ALLOWED_IDS.backup"
}

# 恢复配置
restore_config() {
    if [ -f "$ALLOWED_IDS.backup" ]; then
        mv "$ALLOWED_IDS.backup" "$ALLOWED_IDS"
        # 同步配置
        curl -sS -X POST "$AUTH_SERVICE_URL/v1/sync" > /dev/null 2>&1 || true
    fi
}

# 添加 Client B 到允许列表
add_client_b() {
    python3 - <<PYEOF
import json

with open("$ALLOWED_IDS", "r") as f:
    data = json.load(f)

if "$CLIENT_B_ADDR" not in data["allowed_ids"]:
    data["allowed_ids"].append("$CLIENT_B_ADDR")

with open("$ALLOWED_IDS", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

# 主测试流程
main() {
    echo "================================================"
    echo "  OpenMesh V2 准入控制 POC 验证"
    echo "================================================"
    echo ""

    # 前置检查
    log_info "前置检查"

    # 检查 Auth Service
    if ! curl -sS --max-time 3 "$AUTH_SERVICE_URL/health" > /dev/null 2>&1; then
        echo -e "  ${RED}✗${NC} Auth Service 未运行 ($AUTH_SERVICE_URL)"
        echo ""
        echo "请先启动 Auth Service:"
        echo "  cd $BASE_DIR/auth-service"
        echo "  ALLOWED_IDS_PATH=../allowed_ids.json CONFIG_PATH=../singbox-server/config.json go run main.go"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Auth Service 运行正常"

    # 检查 sing-box 服务端
    if ! nc -z 127.0.0.1 10086 2>/dev/null; then
        echo -e "  ${RED}✗${NC} sing-box 服务端未运行 (端口 10086)"
        echo ""
        echo "请先启动 sing-box 服务端:"
        echo "  sing-box run -c $BASE_DIR/singbox-server/config.json"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} sing-box 服务端运行正常"

    # 检查客户端
    if ! nc -z 127.0.0.1 1080 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Client A 未运行 (SOCKS 端口 1080)"
        echo ""
        echo "请先启动 Client A:"
        echo "  sing-box run -c $BASE_DIR/singbox-client-a/config.json"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Client A 运行正常"

    if ! nc -z 127.0.0.1 1081 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Client B 未运行 (SOCKS 端口 1081)"
        echo ""
        echo "请先启动 Client B:"
        echo "  sing-box run -c $BASE_DIR/singbox-client-b/config.json"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Client B 运行正常"

    echo ""

    # 备份配置
    backup_config

    # 确保测试陷阱
    trap restore_config EXIT

    # 命题 A: Client A 可以访问
    log_info "命题 A: Client A (ID 在列表中) 可以访问"
    result_a=$(try_curl "$CLIENT_A_SOCKS")
    check "Client A 通过 SOCKS :1080 访问" "true" "$result_a"
    echo ""

    # 命题 B: Client B 被拒绝
    log_info "命题 B: Client B (ID 不在列表中) 被拒绝"
    result_b=$(try_curl "$CLIENT_B_SOCKS")
    check "Client B 通过 SOCKS :1081 访问 (期望失败)" "false" "$result_b"
    echo ""

    # 命题 C: 动态添加 Client B
    log_info "命题 C: 动态添加 Client B, reload 后立即生效"

    # 添加 Client B 到列表
    add_client_b
    echo "  → 已将 Client B 添加到 allowed_ids.json"

    # 触发 reload
    sync_response=$(curl -sS -X POST "$AUTH_SERVICE_URL/v1/sync")
    echo "  → 已触发 Auth Service sync"

    # 等待 reload 完成
    sleep 2

    # 测试 Client B
    result_b_after=$(try_curl "$CLIENT_B_SOCKS")
    check "Client B 动态加入列表后可以访问" "true" "$result_b_after"
    echo ""

    # 附加验证: Client A 在 reload 后仍然可用
    log_info "附加验证: Client A 在 reload 后仍然可以访问"
    result_a_after=$(try_curl "$CLIENT_A_SOCKS")
    check "Client A reload 后仍然正常访问" "true" "$result_a_after"
    echo ""

    # 恢复配置
    log_info "恢复初始配置"
    restore_config
    echo "  → 配置已恢复到初始状态"
    echo ""

    # 输出结果
    echo "================================================"
    echo "  验证结果: 通过 $PASS_COUNT 个, 失败 $FAIL_COUNT 个"
    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "  ${GREEN}🎉 所有命题验证通过${NC}"
    else
        echo -e "  ${RED}⚠️  存在失败的测试${NC}"
    fi
    echo "================================================"

    # 返回退出码
    if [ $FAIL_COUNT -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main
