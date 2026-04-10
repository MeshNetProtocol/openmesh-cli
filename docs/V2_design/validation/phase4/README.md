# Phase 4: CDP 订阅支付 POC 验证

## 概述

Phase 4 用于验证基于 Coinbase Developer Platform (CDP) 的订阅支付能力，包括：
- 一次性订阅支付（x402）
- 自动续费（Spend Permissions）
- 降低 ETH 门槛（Smart Account + Paymaster）

**重要**: 这是 POC 验证代码，不是生产代码。

## 目标

验证以下产品模型是否成立：
1. VPN 客户端以 `identity_address` 作为身份
2. 任何外部钱包都可以为该身份购买订阅
3. 自动续费不依赖同一个外部付款钱包
4. 尽可能降低用户持有 ETH 的门槛

## 架构

```
[MetaMask Wallet] 
       ↓ 支付 USDC
[CDP x402 / Spend Permissions]
       ↓ 验证支付
[Auth Service - 4个最小接口]
       ↓ 记录订阅
[JSON 文件存储]
```

## 组件

1. **Auth Service** - Go HTTP 服务，提供 4 个最小接口
2. **JSON 数据文件** - 存储订阅请求、支付记录、自动续费配置
3. **MetaMask 钱包** - Base Sepolia 测试网钱包

## 快速开始

### 1. 准备环境

```bash
# 设置环境变量
cp .env.example .env
# 编辑 .env 填入你的配置
```

### 2. 启动 Auth 服务

```bash
cd auth-service
go mod tidy
go run main.go
```

### 3. 访问服务

```
http://localhost:8080
```

## 测试流程

### 测试 1: 一次性订阅支付

```bash
# 1. 创建订阅请求
curl -X POST http://localhost:8080/poc/subscriptions \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0xYourIdentityAddress",
    "plan_id": "weekly_test"
  }'

# 2. 触发付费激活（使用 x402）
curl -X POST http://localhost:8080/poc/subscriptions/{order_id}/activate
```

### 测试 2: 自动续费

```bash
# 1. 配置自动续费
curl -X POST http://localhost:8080/poc/auto-renew/setup \
  -H 'Content-Type: application/json' \
  -d '{
    "identity_address": "0xIdentityAddr",
    "billing_account": "0xBillingSmartAccount",
    "spender_address": "0xAuthSpender",
    "permission_hash": "0xPermissionHash",
    "period_seconds": 604800
  }'

# 2. 触发续费
curl -X POST http://localhost:8080/poc/auto-renew/{identity_address}/trigger
```

## 验收标准

### 一次性支付
- [ ] 成功打印 `[SUBSCRIPTION_ACTIVATED]` 日志
- [ ] `payments.json` 新增记录
- [ ] 支持 `identity_address` 与 `payer_address` 分离

### 自动续费
- [ ] 成功打印 `[SUBSCRIPTION_RENEWED]` 日志
- [ ] 记录 `permission_hash` 和 `transaction_hash`
- [ ] 周期额度正确扣减

### Gas 门槛
- [ ] 记录普通 EOA 的 ETH 要求
- [ ] 记录 Smart Account + Paymaster 的 ETH 要求
- [ ] 确定推荐的低门槛支付路径

## 参考文档

- [CDP 订阅支付 POC 方案说明](../cdp_subscription_payment_poc.md)
- [CDP 订阅支付 POC 执行手册](../coinbase_commerce_poc.md)
- [项目总览](../../0.项目总览.md)

## 状态

- **创建日期**: 2026-04-10
- **状态**: 开发中
- **负责人**: -
