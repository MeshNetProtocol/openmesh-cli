# CDP VPN 订阅支付 POC 方案说明

## 文档信息

**文档类型**: 技术方案说明  
**创建日期**: 2026-04-08  
**最后更新**: 2026-04-08  
**目标网络**: Base Sepolia  
**状态**: 待审查

## 一、目标

本方案用于验证以下产品模型是否成立:

1. VPN 客户端以 `identity_address` 作为身份
2. 任何外部钱包都可以为该身份购买订阅
3. 自动续费不要求依赖同一个外部付款钱包
4. 尽可能降低用户持有 ETH 的门槛

这和 [项目总览](../0.项目总览.md) 以及 [技术方案](../1.技术方案.md) 中“区块链地址认证 + 订阅式付费”的方向一致，但进一步把“身份账户”和“支付账户”拆开了。

## 二、核心结论

### 2.1 一次性订阅支付

推荐使用:

```text
x402 + Base Sepolia + USDC
```

原因:

- 更贴近“服务访问权购买”
- 不要求先走商户账户路径
- 支付确认可直接内嵌在 Auth 服务请求链路中
- 能自然表达“某次请求对应某次付款”

### 2.2 自动续费

推荐使用:

```text
Spend Permissions + Smart Account + Paymaster
```

原因:

- 官方明确支持订阅 / 周期扣费用例
- 可限制 spender、token、额度、周期
- 比强行用 x402 做“未来支付授权”更稳妥

### 2.3 降低 ETH 门槛

推荐顺序:

1. Smart Account + CDP Paymaster
2. ERC20 Gas Payments
3. 普通 EOA + 少量 ETH 仅作为基线测试

## 三、账户模型

### 3.1 identity_address

表示:

- VPN 用户身份
- 订阅绑定主体
- 登录/授权主体

特点:

- 不要求持有 USDC
- 不要求直接付款

### 3.2 payer_address

表示:

- 一次性付款地址
- 可以是赠送者或代付者

特点:

- 与 `identity_address` 可以不同
- 只影响付款审计,不影响订阅主体归属

### 3.3 billing_account

表示:

- 自动续费资金账户
- 向服务端 spender 授权周期扣费

特点:

- 建议使用 Smart Account
- 可单独承载自动续费逻辑

## 四、两条支付路径

### 4.1 路径 A: 一次性订阅

```text
identity_address 发起订阅请求
→ Auth 服务返回 x402 付费要求
→ payer_address 支付 USDC
→ facilitator 验证与结算
→ Auth 服务激活订阅
```

产出:

- 支付记录
- payer 地址
- 交易哈希
- 激活日志

### 4.2 路径 B: 自动续费

```text
billing_account 预先授权 Spend Permission
→ Auth 服务或 renew worker 到期触发扣费
→ spender 在额度与周期限制内扣费
→ Auth 服务记录续费
```

产出:

- permission hash
- renew 交易哈希
- 周期额度消耗记录
- 续费日志

## 五、为什么不继续沿用 Coinbase Commerce 文档路径

原来的 Commerce 思路更接近:

- hosted checkout
- webhook
- 商户型支付

这不是本次 POC 的最佳起点，原因是:

1. 你当前已经注册的是 CDP 开发者路径
2. 你要验证的是“服务访问权购买”，不是完整商户收银台
3. 你还希望顺便验证 x402 与 gas sponsorship

因此本次把 POC 中心切到 CDP 原生开发者能力。

## 六、能力边界

### 6.1 x402 的适用边界

x402 适合:

- 按次付费
- 请求级支付
- 对某个 API / 服务访问权收费

x402 目前不适合作为本次“自动续费”的唯一实现路径，因为自动续费本质上需要提前授权未来扣费。

### 6.2 Spend Permissions 的适用边界

Spend Permissions 适合:

- SaaS 订阅
- 周期扣费
- 额度和时间窗口控制

但它要求你有一个可授予权限的账户模型，因此更适合作为自动续费专用路径，而不是用户首次代付购买的唯一入口。

### 6.3 完全零 ETH 的边界

需要区分:

1. **普通 EOA**
   - 往往仍需要少量 ETH 做 gas

2. **Smart Account + Paymaster**
   - 可显著降低甚至免除用户持有 ETH 的要求

3. **ERC20 Gas Payments**
   - 用户不持有 ETH，但用 USDC 等代币承担 gas

因此本次 POC 不直接承诺“所有支付场景完全零 ETH”，而是通过对比实验得出建议路径。

## 七、最小 POC 输出

### 7.1 一次性订阅成功日志

```text
[SUBSCRIPTION_ACTIVATED] order=... identity=... payer=... amount=... tx=...
```

### 7.2 自动续费成功日志

```text
[SUBSCRIPTION_RENEWED] identity=... billing_account=... amount=... tx=...
```

### 7.3 推荐数据表

最小只需要三份数据:

- `subscription_requests.json`
- `payments.json`
- `auto_renew_profiles.json`

## 八、推荐的工程拆分

### 8.1 Auth Service

负责:

- 接受订阅请求
- 生成订单
- 集成 x402
- 激活订阅
- 触发 renew
- 打日志

### 8.2 Renew Worker

可选拆分:

- 扫描到期订阅
- 调用 Spend Permission 完成续费
- 回写续费结果

POC 阶段也可以不单独拆服务，只保留一个命令即可。

### 8.3 Wallet / Payment Tools

负责:

- 准备测试 USDC
- 准备测试 ETH
- 准备 billing account
- 为自动续费配置 permission

## 九、推荐验证顺序

不要一开始就做自动续费。顺序建议固定为:

1. 跑通一次性支付
2. 确认能记录 `identity_address` 和 `payer_address`
3. 再做自动续费
4. 最后再做 gas 门槛优化对比

原因:

- 一次性支付链路最短
- 自动续费涉及账户模型更多
- gas 优化是体验增强项，不是支付主链路前置条件

## 十、POC 通过后的产品建议

### 10.1 短期上线形态

优先上线:

- 手动购买订阅
- 第三方代付 / 赠送订阅

暂缓:

- 默认自动续费

### 10.2 中期增强

引入:

- Smart Account
- Paymaster
- Spend Permissions

这样能把“自动续费”和“低 ETH 门槛”同时做得更完整。

### 10.3 长期增强

如果将来要更接近 Web2 订阅体验，再补:

- 更完整 checkout 页面
- 订单管理后台
- 用户自助变更 billing account

## 十一、执行文档

具体执行步骤请直接使用:

- [coinbase_commerce_poc.md](./coinbase_commerce_poc.md)

## 十二、参考资料

- [项目总览](../0.项目总览.md)
- [技术方案](../1.技术方案.md)
- [CDP x402 Overview](https://docs.cdp.coinbase.com/x402/welcome)
- [x402 Quickstart for Sellers](https://docs.cdp.coinbase.com/x402/quickstart-for-sellers)
- [x402 Quickstart for Buyers](https://docs.cdp.coinbase.com/x402/quickstart-for-buyers)
- [Spend Permissions - Embedded Wallets](https://docs.cdp.coinbase.com/embedded-wallets/evm-features/spend-permissions)
- [Spend Permissions - Server Wallet](https://docs.cdp.coinbase.com/server-wallets/v2/evm-features/spend-permissions)
- [CDP Paymaster Overview](https://docs.cdp.coinbase.com/paymaster/docs/welcome/)
- [Pay Gas in ERC20 Tokens](https://docs.cdp.coinbase.com/paymaster/guides/erc20-gas-payments)

---

**文档维护者**: [待填写]  
**状态**: 待审查
