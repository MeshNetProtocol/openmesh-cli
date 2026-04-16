#!/bin/bash

# EIP-3009 订阅系统自动测试脚本
# 测试环境：Base Sepolia
# 测试范围：环境配置、合约部署、API 端点、EIP-3009 功能

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 打印函数
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    echo -e "${YELLOW}[TEST $((TOTAL_TESTS + 1))]${NC} $1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC} $1\n"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC} $1\n"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# 检查环境变量一致性
check_env_consistency() {
    print_header "1. 环境变量一致性检查"

    # 读取后端 .env
    source .env
    BACKEND_CONTRACT=$VPN_SUBSCRIPTION_CONTRACT
    BACKEND_USDC=$USDC_CONTRACT
    BACKEND_SERVICE=$SERVICE_WALLET_ADDRESS
    BACKEND_RELAYER=$RELAYER_ADDRESS

    # 读取合约 .env
    source contracts/.env
    CONTRACTS_CONTRACT=$VPN_SUBSCRIPTION_CONTRACT
    CONTRACTS_USDC=$USDC_CONTRACT
    CONTRACTS_SERVICE=$SERVICE_WALLET_ADDRESS
    CONTRACTS_RELAYER=$RELAYER_ADDRESS

    # 检查前端配置
    FRONTEND_CONTRACT=$(grep "CONTRACT_ADDRESS:" frontend/app.js | grep -o "0x[a-fA-F0-9]*" | head -1)
    FRONTEND_USDC=$(grep "USDC_ADDRESS:" frontend/app.js | grep -o "0x[a-fA-F0-9]*" | head -1)

    print_test "合约地址一致性"
    if [[ "$BACKEND_CONTRACT" == "$CONTRACTS_CONTRACT" ]] && [[ "$BACKEND_CONTRACT" == "$FRONTEND_CONTRACT" ]]; then
        print_pass "合约地址一致: $BACKEND_CONTRACT"
    else
        print_fail "合约地址不一致: Backend=$BACKEND_CONTRACT, Contracts=$CONTRACTS_CONTRACT, Frontend=$FRONTEND_CONTRACT"
    fi

    print_test "USDC 地址一致性"
    if [[ "$BACKEND_USDC" == "$CONTRACTS_USDC" ]] && [[ "$BACKEND_USDC" == "$FRONTEND_USDC" ]]; then
        print_pass "USDC 地址一致: $BACKEND_USDC"
    else
        print_fail "USDC 地址不一致: Backend=$BACKEND_USDC, Contracts=$CONTRACTS_USDC, Frontend=$FRONTEND_USDC"
    fi

    print_test "服务钱包地址一致性"
    if [[ "$BACKEND_SERVICE" == "$CONTRACTS_SERVICE" ]]; then
        print_pass "服务钱包地址一致: $BACKEND_SERVICE"
    else
        print_fail "服务钱包地址不一致: Backend=$BACKEND_SERVICE, Contracts=$CONTRACTS_SERVICE"
    fi

    print_test "Relayer 地址一致性"
    if [[ "$BACKEND_RELAYER" == "$CONTRACTS_RELAYER" ]]; then
        print_pass "Relayer 地址一致: $BACKEND_RELAYER"
    else
        print_fail "Relayer 地址不一致: Backend=$BACKEND_RELAYER, Contracts=$CONTRACTS_RELAYER"
    fi
}

# 检查合约代码
check_contract_code() {
    print_header "2. 合约代码检查"

    print_test "检查 renewWithAuthorization 函数"
    if grep -q "function renewWithAuthorization" contracts/src/VPNSubscriptionV2.sol; then
        print_pass "renewWithAuthorization 函数存在"
    else
        print_fail "renewWithAuthorization 函数不存在"
    fi

    print_test "检查 IUSDC3009 接口"
    if grep -q "interface IUSDC3009" contracts/src/VPNSubscriptionV2.sol; then
        print_pass "IUSDC3009 接口存在"
    else
        print_fail "IUSDC3009 接口不存在"
    fi

    print_test "检查 transferWithAuthorization 调用"
    if grep -q "transferWithAuthorization" contracts/src/VPNSubscriptionV2.sol; then
        print_pass "transferWithAuthorization 调用存在"
    else
        print_fail "transferWithAuthorization 调用不存在"
    fi
}

# 检查后端代码
check_backend_code() {
    print_header "3. 后端代码检查"

    print_test "检查 POST /api/subscription/prepare 端点"
    if grep -q "app.post('/api/subscription/prepare'" subscription-service/index.js; then
        print_pass "POST /api/subscription/prepare 端点存在"
    else
        print_fail "POST /api/subscription/prepare 端点不存在"
    fi

    print_test "检查 POST /api/subscription/subscribe 端点"
    if grep -q "app.post('/api/subscription/subscribe'" subscription-service/index.js; then
        print_pass "POST /api/subscription/subscribe 端点存在"
    else
        print_fail "POST /api/subscription/subscribe 端点不存在"
    fi

    print_test "检查 POST /api/subscription/cancel 端点"
    if grep -q "app.post('/api/subscription/cancel'" subscription-service/index.js; then
        print_pass "POST /api/subscription/cancel 端点存在"
    else
        print_fail "POST /api/subscription/cancel 端点不存在"
    fi

    print_test "检查 GET /api/subscription/:address 查询端点"
    if grep -q "app.get('/api/subscription/:address'" subscription-service/index.js; then
        print_pass "GET /api/subscription/:address 端点存在"
    else
        print_fail "GET /api/subscription/:address 端点不存在"
    fi

    print_test "检查 V2.2 状态判定（expiresAt + isSuspended）"
    if grep -q "const isActive = expiresAt > now && !isSuspended" subscription-service/index.js; then
        print_pass "后端已使用 V2.2 状态判定"
    else
        print_fail "后端未使用 V2.2 状态判定"
    fi
}

# 检查前端代码
check_frontend_code() {
    print_header "4. 前端代码检查"

    print_test "检查订阅准备接口调用"
    if grep -q "subscription/prepare" frontend/app.js; then
        print_pass "前端调用 /subscription/prepare"
    else
        print_fail "前端未调用 /subscription/prepare"
    fi

    print_test "检查订阅提交接口调用"
    if grep -q "subscription/subscribe" frontend/app.js; then
        print_pass "前端调用 /subscription/subscribe"
    else
        print_fail "前端未调用 /subscription/subscribe"
    fi

    print_test "检查取消订阅接口调用"
    if grep -q "subscription/cancel" frontend/app.js; then
        print_pass "前端调用 /subscription/cancel"
    else
        print_fail "前端未调用 /subscription/cancel"
    fi

    print_test "检查前端活跃状态过滤逻辑（V2.2）"
    if grep -q "Number(sub.expiresAt) > now && !sub.isSuspended" frontend/app.js; then
        print_pass "前端已使用 expiresAt + isSuspended 过滤活跃订阅"
    else
        print_fail "前端未使用 V2.2 活跃过滤逻辑"
    fi
}

# 检查 API 端点（如果服务正在运行）
check_api_endpoints() {
    print_header "5. API 端点检查（可选）"

    # 检查服务是否运行
    if ! curl -s http://localhost:3000/api/config > /dev/null 2>&1; then
        print_info "后端服务未运行，跳过 API 测试"
        print_info "启动服务: cd subscription-service && npm start"
        return
    fi

    print_test "GET /api/config"
    RESPONSE=$(curl -s http://localhost:3000/api/config)
    if echo "$RESPONSE" | grep -q "contractAddress"; then
        print_pass "GET /api/config 响应正常"
    else
        print_fail "GET /api/config 响应异常"
    fi

    print_test "GET /api/plans"
    RESPONSE=$(curl -s http://localhost:3000/api/plans)
    if echo "$RESPONSE" | grep -q "plans"; then
        print_pass "GET /api/plans 响应正常"
    else
        print_fail "GET /api/plans 响应异常"
    fi

    print_test "GET /api/subscription/:address"
    RESPONSE=$(curl -s http://localhost:3000/api/subscription/0x0000000000000000000000000000000000000000)
    if echo "$RESPONSE" | grep -q "subscriptions"; then
        print_pass "GET /api/subscription/:address 响应正常"
    else
        print_fail "GET /api/subscription/:address 响应异常"
    fi
}

# 检查文档
check_documentation() {
    print_header "6. 文档检查"

    print_test "检查 CRITICAL_ISSUES.md"
    if [[ -f "CRITICAL_ISSUES.md" ]]; then
        print_pass "CRITICAL_ISSUES.md 存在"
    else
        print_fail "CRITICAL_ISSUES.md 不存在"
    fi

    print_test "检查 IMPLEMENTATION_PLAN_V2.md"
    if [[ -f "IMPLEMENTATION_PLAN_V2.md" ]]; then
        print_pass "IMPLEMENTATION_PLAN_V2.md 存在"
    else
        print_fail "IMPLEMENTATION_PLAN_V2.md 不存在"
    fi

    print_test "检查 QUICKSTART.md"
    if [[ -f "QUICKSTART.md" ]]; then
        print_pass "QUICKSTART.md 存在"
    else
        print_fail "QUICKSTART.md 不存在"
    fi
}

# 生成测试报告
generate_report() {
    print_header "测试报告"

    echo -e "总测试数: ${BLUE}$TOTAL_TESTS${NC}"
    echo -e "通过: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "失败: ${RED}$FAILED_TESTS${NC}"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}✓ 所有测试通过！系统已准备好进行端到端测试。${NC}\n"
        exit 0
    else
        echo -e "\n${RED}✗ 有 $FAILED_TESTS 个测试失败，请检查上述错误。${NC}\n"
        exit 1
    fi
}

# 主测试流程
main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   EIP-3009 订阅系统自动测试                            ║"
    echo "║   Base Sepolia 测试网                                  ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_env_consistency
    check_contract_code
    check_backend_code
    check_frontend_code
    check_api_endpoints
    check_documentation
    generate_report
}

# 运行测试
main
