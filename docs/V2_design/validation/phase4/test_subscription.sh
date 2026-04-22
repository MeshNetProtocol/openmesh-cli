#!/bin/bash
set -e

source .env

VAULT_CONTRACT="0x92879A3a144b7894332ee2648E3BcB0616De6040"
USDC_CONTRACT="0x036CbD53842c5426634e7929541eC2318f3dCF7e"
RPC_URL="https://sepolia.base.org"
USER_ADDRESS=$(cast wallet address --private-key $OWNER_PRIVATE_KEY)
IDENTITY_ADDRESS="0x1234567890123456789012345678901234567890"

echo "=========================================="
echo "测试智能合约订阅和取消订阅"
echo "=========================================="
echo "用户地址: $USER_ADDRESS"
echo "Identity: $IDENTITY_ADDRESS"
echo ""

# 1. 查询当前 USDC allowance
echo "1. 查询当前 USDC allowance..."
CURRENT_ALLOWANCE=$(cast call $USDC_CONTRACT "allowance(address,address)(uint256)" $USER_ADDRESS $VAULT_CONTRACT --rpc-url $RPC_URL | awk '{print $1}')
echo "   当前 allowance: $CURRENT_ALLOWANCE"

# 2. 查询 Vault authorizedAllowance
echo "2. 查询 Vault authorizedAllowance..."
VAULT_ALLOWANCE=$(cast call $VAULT_CONTRACT "authorizedAllowance(address,address)(uint256)" $USER_ADDRESS $IDENTITY_ADDRESS --rpc-url $RPC_URL | awk '{print $1}')
echo "   Vault authorizedAllowance: $VAULT_ALLOWANCE"

# 3. 计算 targetAllowance (增加 1 USDC = 1000000)
TARGET_ALLOWANCE=$((CURRENT_ALLOWANCE + 1000000))
echo "3. 计算 targetAllowance: $TARGET_ALLOWANCE (增加 1 USDC)"

# 4. 查询 USDC nonce
echo "4. 查询 USDC nonce..."
NONCE=$(cast call $USDC_CONTRACT "nonces(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL | awk '{print $1}')
echo "   USDC nonce: $NONCE"

# 5. 计算 deadline (24小时后)
DEADLINE=$(($(date +%s) + 86400))
echo "5. Deadline: $DEADLINE"

# 6. 使用 cast wallet sign-typed-data 生成 EIP-712 签名
echo "6. 生成 permit 签名..."
PERMIT_JSON=$(cat <<PERMIT_EOF
{
  "domain": {
    "name": "USDC",
    "version": "2",
    "chainId": 84532,
    "verifyingContract": "$USDC_CONTRACT"
  },
  "types": {
    "EIP712Domain": [
      {"name": "name", "type": "string"},
      {"name": "version", "type": "string"},
      {"name": "chainId", "type": "uint256"},
      {"name": "verifyingContract", "type": "address"}
    ],
    "Permit": [
      {"name": "owner", "type": "address"},
      {"name": "spender", "type": "address"},
      {"name": "value", "type": "uint256"},
      {"name": "nonce", "type": "uint256"},
      {"name": "deadline", "type": "uint256"}
    ]
  },
  "primaryType": "Permit",
  "message": {
    "owner": "$USER_ADDRESS",
    "spender": "$VAULT_CONTRACT",
    "value": "$TARGET_ALLOWANCE",
    "nonce": "$NONCE",
    "deadline": $DEADLINE
  }
}
PERMIT_EOF
)

echo "$PERMIT_JSON" > /tmp/permit.json
SIGNATURE=$(cast wallet sign-typed-data --private-key $OWNER_PRIVATE_KEY --data /tmp/permit.json)
echo "   signature: $SIGNATURE"

# 分离 v, r, s
R="0x${SIGNATURE:2:64}"
S="0x${SIGNATURE:66:64}"
V_HEX="${SIGNATURE:130:2}"
V=$((16#$V_HEX))
if [ $V -lt 27 ]; then
  V=$((V + 27))
fi

echo "   v: $V"
echo "   r: $R"
echo "   s: $S"
echo ""

# 7. 调用 authorizeChargeWithPermit (订阅)
echo "7. 调用 authorizeChargeWithPermit (订阅)..."
echo "   参数:"
echo "     user: $USER_ADDRESS"
echo "     identityAddress: $IDENTITY_ADDRESS"
echo "     expectedAllowance: $CURRENT_ALLOWANCE"
echo "     targetAllowance: $TARGET_ALLOWANCE"
echo "     deadline: $DEADLINE"
echo "     v: $V"
echo "     r: $R"
echo "     s: $S"

# 注意：这里需要 relayer 调用，所以我们先打印命令，不实际执行
echo ""
echo "=========================================="
echo "订阅测试准备完成！"
echo "=========================================="
echo ""
echo "下一步需要使用 relayer 私钥调用合约"
echo "（因为 authorizeChargeWithPermit 有 onlyRelayer 修饰符）"

