# VPN 订阅系统部署检查列表

## 部署前准备

### 1. 合约编译和部署
- [ ] 确认合约代码包含所有必要的功能（`_addToActiveSubscriptions`, `_removeFromActiveSubscriptions`）
- [ ] 运行 `forge build` 确认编译成功
- [ ] 部署合约并记录新合约地址
- [ ] 记录部署区块号（用于事件同步配置）

### 2. CDP 配置（重要！）
- [ ] 登录 https://portal.cdp.coinbase.com/
- [ ] 将新合约地址添加到 Paymaster 白名单
- [ ] 确认 CDP API Key 和 Secret 有效
- [ ] 确认 CDP Server Wallet 地址正确

### 3. 合约初始化
- [ ] 调用 `setRelayer()` 设置 Relayer 地址为 CDP Server Wallet 地址
- [ ] 验证 Relayer 地址：`cast call <CONTRACT> "relayer()(address)"`
- [ ] 添加测试套餐（如果需要）

## 配置文件更新

### 4. 后端配置 (.env)
- [ ] 更新 `VPN_SUBSCRIPTION_CONTRACT` 为新合约地址
- [ ] 更新 `EVENT_SYNC_START_BLOCK` 为部署区块号
- [ ] 确认 `CDP_SERVER_WALLET_ADDRESS` 与合约 Relayer 一致
- [ ] 确认 `PORT=8080`
- [ ] 确认 `SERVICE_WALLET_ADDRESS` 和 `PAY_TO_ADDRESS` 正确

### 5. 前端配置 (frontend/app.js)
- [ ] 更新 `CONTRACT_ADDRESS` 为新合约地址
- [ ] 确认 `API_BASE` 为 `http://localhost:8080/api`
- [ ] 确认 `USDC_ADDRESS` 正确
- [ ] 确认 `CHAIN_ID` 为 84532 (Base Sepolia)

### 6. 后端合约 ABI
- [ ] 复制最新的合约 ABI：
  ```bash
  cp contracts/out/VPNSubscriptionV2.sol/VPNSubscription.json subscription-service/contract-abi.json
  ```
- [ ] 验证 ABI 文件包含所有新增的函数

## 服务启动

### 7. 停止所有旧服务
- [ ] 停止所有 node 进程：`pkill -f "node index.js"`
- [ ] 验证没有残留进程：`ps aux | grep "node index.js"`

### 8. 启动后端服务
- [ ] 进入服务目录：`cd subscription-service`
- [ ] 启动服务：`node index.js > service.log 2>&1 &`
- [ ] 检查启动日志：`head -50 service.log`
- [ ] 验证关键信息：
  - [ ] CDP Client 初始化成功
  - [ ] Smart Account 地址正确
  - [ ] Relayer 校验通过
  - [ ] 事件同步器初始化成功
  - [ ] 服务监听在 8080 端口

### 9. 验证服务状态
- [ ] 访问 http://localhost:8080 确认前端可访问
- [ ] 检查 API 端点：`curl http://localhost:8080/api/config`
- [ ] 验证合约地址在配置中正确

## 订阅测试

### 10. 准备测试账号
- [ ] 确认测试钱包有足够的 USDC（至少 0.2 USDC）
- [ ] 确认测试钱包有少量 ETH（用于签名，不需要很多）

### 11. 第一次订阅测试
- [ ] 在前端连接钱包
- [ ] 选择套餐并订阅
- [ ] 等待交易确认
- [ ] 检查 Basescan 确认：
  - [ ] 有 USDC Transfer 事件（从用户钱包到 SERVICE_WALLET_ADDRESS）
  - [ ] 有 SubscriptionCreated 事件（来自新合约地址）
  - [ ] 交易状态为成功
- [ ] 查询合约验证订阅存在：
  ```bash
  cast call <CONTRACT> "getSubscription(address)" <IDENTITY_ADDRESS> --rpc-url <RPC_URL>
  ```
- [ ] 验证返回的订阅数据不是全 0
- [ ] 验证活跃订阅列表：
  ```bash
  cast call <CONTRACT> "getAllActiveSubscriptions()(address[])" --rpc-url <RPC_URL>
  ```
- [ ] 确认返回的数组包含新订阅的地址

### 12. 第二次订阅测试
- [ ] 使用不同的 identityAddress 重复步骤 11
- [ ] 验证活跃订阅列表包含 2 个地址

### 13. 自动续费测试
- [ ] 检查服务日志：`tail -f service.log`
- [ ] 等待自动续费检查（每 60 秒一次）
- [ ] 验证日志显示：
  - [ ] "检查 2 个订阅..."
  - [ ] 每个订阅的状态快照（planId, autoRenew, suspended）
  - [ ] 时间快照（now, start, renewedAt, expiresAt, nextRenewalAt）
  - [ ] 距离到期的时间
- [ ] 等待订阅到期（根据配置的 lockedPeriod）
- [ ] 验证自动续费执行：
  - [ ] 日志显示"执行续费..."
  - [ ] 日志显示"续费成功! TX: <hash>"
  - [ ] Basescan 上有新的 USDC Transfer 事件
  - [ ] Basescan 上有 SubscriptionRenewed 事件
- [ ] 查询合约验证订阅已续费：
  ```bash
  cast call <CONTRACT> "getSubscription(address)" <IDENTITY_ADDRESS> --rpc-url <RPC_URL>
  ```
- [ ] 验证 `expiresAt` 和 `renewedAt` 已更新

## 常见问题排查

### 问题 1：合约查询返回全 0
**原因**：订阅不在新合约上，可能在旧合约上
**解决**：
1. 确认前端和后端配置的合约地址一致
2. 在新合约上重新订阅
3. 不要使用旧合约上的订阅数据

### 问题 2：自动续费显示"没有需要检查的订阅"
**原因**：
- 事件同步器没有加载订阅列表
- `getAllActiveSubscriptions()` 返回空数组
**解决**：
1. 检查合约是否正确实现了 `_addToActiveSubscriptions()`
2. 验证订阅创建时是否调用了 `_addToActiveSubscriptions()`
3. 重新部署合约并重新订阅

### 问题 3：多个服务实例同时运行
**原因**：启动新服务前没有停止旧服务
**解决**：
1. 停止所有 node 进程：`pkill -f "node index.js"`
2. 验证没有残留进程：`ps aux | grep "node index.js"`
3. 启动新服务

### 问题 4：前端连接错误的端口
**原因**：前端配置的 API_BASE 端口不正确
**解决**：
1. 确认后端 `.env` 中 `PORT=8080`
2. 确认前端 `app.js` 中 `API_BASE: 'http://localhost:8080/api'`
3. 重启服务

### 问题 5：CDP Paymaster 拒绝交易
**原因**：新合约地址没有添加到 CDP 白名单
**解决**：
1. 登录 https://portal.cdp.coinbase.com/
2. 将新合约地址添加到 Paymaster 白名单
3. 等待几分钟让配置生效
4. 重试交易

### 问题 6：Relayer 地址不匹配
**原因**：合约的 Relayer 地址与 CDP Server Wallet 地址不一致
**解决**：
1. 查询合约 Relayer：`cast call <CONTRACT> "relayer()(address)"`
2. 调用 `setRelayer()` 更新为正确的地址
3. 重启服务

### 问题 7：事件同步器加载旧数据
**原因**：`EVENT_SYNC_START_BLOCK` 配置错误
**解决**：
1. 更新 `.env` 中的 `EVENT_SYNC_START_BLOCK` 为新合约部署区块号
2. 重启服务

## 部署后验证清单

### 最终验证
- [ ] 2 个订阅都成功创建
- [ ] 合约查询返回正确的订阅数据（不是全 0）
- [ ] `getAllActiveSubscriptions()` 返回 2 个地址
- [ ] 服务日志显示"检查 2 个订阅..."
- [ ] 自动续费功能正常工作
- [ ] Basescan 上有正确的 USDC Transfer 和 SubscriptionRenewed 事件
- [ ] 没有多个服务实例同时运行
- [ ] 前端可以正常访问和操作

## 快速命令参考

```bash
# 1. 编译合约
cd contracts && forge build

# 2. 部署合约（记录地址和区块号）
forge script script/DeployVPNSubscriptionV2.s.sol --rpc-url <RPC_URL> --broadcast

# 3. 设置 Relayer
cast send <CONTRACT> "setRelayer(address)" <RELAYER_ADDRESS> --private-key <PRIVATE_KEY> --rpc-url <RPC_URL>

# 4. 验证 Relayer
cast call <CONTRACT> "relayer()(address)" --rpc-url <RPC_URL>

# 5. 更新后端 ABI
cp out/VPNSubscriptionV2.sol/VPNSubscription.json ../subscription-service/contract-abi.json

# 6. 停止所有服务
pkill -f "node index.js"

# 7. 启动服务
cd ../subscription-service && node index.js > service.log 2>&1 &

# 8. 检查服务日志
tail -f service.log

# 9. 查询订阅
cast call <CONTRACT> "getSubscription(address)" <IDENTITY_ADDRESS> --rpc-url <RPC_URL>

# 10. 查询活跃订阅列表
cast call <CONTRACT> "getAllActiveSubscriptions()(address[])" --rpc-url <RPC_URL>

# 11. 查询活跃订阅数量
cast call <CONTRACT> "getActiveSubscriptionCount()(uint256)" --rpc-url <RPC_URL>
```

## 注意事项

1. **每次部署新合约后，必须在 CDP 添加白名单**
2. **每次部署新合约后，必须调用 `setRelayer()`**
3. **每次更新配置后，必须重启服务**
4. **每次重启服务前，必须停止所有旧服务**
5. **订阅测试必须在新合约上进行，不要使用旧合约的订阅**
6. **验证订阅时，必须检查合约查询结果不是全 0**
7. **验证自动续费时，必须检查 Basescan 上的实际交易记录**
