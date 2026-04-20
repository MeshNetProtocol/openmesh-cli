# 智能合约修改检查清单

当修改智能合约时，必须按顺序执行以下步骤：

## 1. 合约层面
- [ ] 修改 Solidity 合约源码 (`VPNCreditVaultV4.sol`)
- [ ] 编译合约：`cd contracts && forge build`
- [ ] 运行测试：`forge test`
- [ ] 部署新合约到测试网：`forge script script/DeployVPNCreditVaultV4.s.sol:DeployVPNCreditVaultV4 --rpc-url https://sepolia.base.org --broadcast`
- [ ] 记录新的合约地址（从部署日志中获取）
- [ ] **关键**：更新合约的 relayer 地址为 CDP Smart Account
  ```bash
  # 从服务日志获取 Smart Account 地址（通常是 0x10AB796695843043CF303Cc8C7a58E9498023768）
  source .env && cast send <NEW_CONTRACT_ADDRESS> "setRelayer(address)" <SMART_ACCOUNT_ADDRESS> --rpc-url https://sepolia.base.org --private-key $OWNER_PRIVATE_KEY
  ```
- [ ] 验证 relayer 已更新：`cast call <CONTRACT_ADDRESS> "relayer()(address)" --rpc-url https://sepolia.base.org`

## 2. CDP 配置
- [ ] 在 CDP Portal 中将新合约地址添加到 Paymaster 白名单
- [ ] 验证白名单配置生效

## 3. 配置文件更新
- [ ] 更新 `.env` 中的 `VPN_SUBSCRIPTION_CONTRACT` 为新合约地址
- [ ] 获取当前区块号：`curl -s https://sepolia.base.org -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf "%d\n"`
- [ ] 更新 `.env` 中的 `EVENT_SYNC_START_BLOCK` 为当前区块号

## 4. ABI 同步
- [ ] 重新生成 ABI：`cd contracts && cat out/VPNCreditVaultV4.sol/VPNCreditVaultV4.json | jq '.abi' > ../subscription-service/contract-abi.json`
- [ ] 验证 ABI 包含所有需要的函数：`grep -o '"name":"functionName"' contract-abi.json`

## 5. 数据迁移
- [ ] **重要**：清空 `permits.json` 中的旧合约数据
  ```bash
  cat > permits.json << 'EOF'
  {
    "permits": {},
    "authorizedAllowances": {},
    "subscriptionHistory": {}
  }
  EOF
  ```
- [ ] 备份旧数据（如果需要）：`cp permits.json permits.json.backup`

## 6. 后端服务
- [ ] 检查 `index.js` 中所有合约调用是否兼容新 ABI
- [ ] 更新事件监听逻辑（如果事件签名改变）
- [ ] 重启服务：`pkill -9 node && node index.js > /tmp/subscription-service.log 2>&1 &`
- [ ] 验证服务初始化成功：`tail -f /tmp/subscription-service.log`

## 7. 前端更新
- [ ] **关键**：更新前端的合约地址
  ```javascript
  // 在 frontend/index.html 中更新（约第112行）
  const VAULT_ADDRESS = '<NEW_CONTRACT_ADDRESS>';
  ```
- [ ] **必须硬刷新浏览器**清除缓存的 JavaScript
  - Mac: Cmd+Shift+R
  - Windows: Ctrl+Shift+R
- [ ] 刷新前端页面
- [ ] 验证订阅列表为空（因为新合约没有数据）
- [ ] 测试完整订阅流程
- [ ] 测试自动续费
- [ ] 测试取消订阅
- [ ] 验证链上授权额度正确

## 8. 链上验证
- [ ] 验证新合约的 relayer 地址正确
- [ ] 验证事件日志同步正常
- [ ] 在区块浏览器查看合约部署交易

## 常见错误

### 错误：`VPN: not relayer`
**原因**：部署脚本设置的 relayer 地址与后端实际使用的 CDP Smart Account 地址不一致  
**解决**：部署后必须调用 `setRelayer` 更新为 CDP Smart Account 地址（见步骤 1）

### 错误：`VPN: allowance changed`
**原因**：前端的 `VAULT_ADDRESS` 还是旧合约地址，读取的 allowance 不匹配  
**解决**：更新前端的 `VAULT_ADDRESS` 为新合约地址（见步骤 7）

### 错误：前端仍显示旧订阅
**原因**：`permits.json` 中还有旧合约的数据  
**解决**：清空 `permits.json`（见步骤 5）

### 错误：`VPN: not the payer`
**原因**：合约的 `cancelAuthorization` 函数不允许 relayer 调用  
**解决**：修改合约，允许 `msg.sender == payer || msg.sender == relayer`

### 错误：`unknown function`
**原因**：`contract-abi.json` 未更新或不完整  
**解决**：重新生成完整 ABI（见步骤 4）

### 错误：服务启动失败 `contract.relayer is not a function`
**原因**：ABI 缺少 `relayer` 等必要函数  
**解决**：确保使用完整的合约 ABI，不要手动精简

## 注意事项

1. **顺序很重要**：必须先部署合约，再更新配置，最后清空数据
2. **CDP 白名单**：新合约地址必须在 CDP Portal 中配置，否则 Paymaster 无法赞助 gas
3. **数据清空**：新合约是全新的链上状态，旧的 `permits.json` 数据无效且会导致前端显示错误
4. **测试完整流程**：每次更新合约后都要测试订阅、续费、取消的完整流程
