# OpenMesh VPN 订阅服务 V2.1 - Phase 4

基于 EIP-712 签名和 CDP Paymaster 的订阅分级系统 + 流量管理。

## 📚 核心文档

- **[技术方案](../usdc_subscription_payment_v3.md)** - V2.1 完整技术方案
- **[重构进度](REFACTORING_PROGRESS.md)** - 实施进度追踪
- **[测试指南](TESTING_GUIDE.md)** - 完整测试手册

---

## 快速开始

### 1. 获取测试 USDC

访问 [Circle Faucet](https://faucet.circle.com/):
- 输入你的钱包地址
- 选择 Base Sepolia 网络
- 领取测试 USDC

### 2. 启动后端服务

```bash
cd subscription-service
npm install
npm start
```

服务运行在 `http://localhost:3000`

### 3. 测试 API

```bash
# 查询所有套餐
curl http://localhost:3000/api/plans

# 查询流量使用
curl http://localhost:3000/api/traffic/0xYourIdentityAddress
```

---

## 核心特性

### ✅ Phase 1-2 已完成

- ✅ **订阅分级系统**: Free/Basic/Premium 三层套餐
- ✅ **流量管理**: 日/月流量限制、自动暂停、定期重置
- ✅ **订阅升级**: 立即生效 + Proration 补差价
- ✅ **订阅降级**: 下周期生效
- ✅ **0 ETH Gas**: 通过 CDP Paymaster 赞助所有交易
- ✅ **EIP-712 签名**: 用户链下签名,安全可验证
- ✅ **自动续费**: 支持套餐变更应用

### ⏸️ Phase 3-5 待实施

- ⏸️ 前端开发 (套餐选择、流量显示、订阅变更界面)
- ⏸️ 集成测试
- ⏸️ 主网部署

---

## 已部署资源

```
智能合约: 0xc9cF89D4B09d0c6ee42ab7EAFaFA9C0E4682fBdf (V2.1)
USDC (Base Sepolia): 0x036CbD53842c5426634e7929541eC2318f3dCF7e
网络: Base Sepolia (Chain ID: 84532)
区块浏览器: https://sepolia.basescan.org
部署时间: 2026-04-13
```

## 订阅套餐

| 套餐 | planId | 月价 | 年价 | 日流量限制 | 月流量限制 |
|------|--------|------|------|-----------|-----------|
| Free | 2 | 0 USDC | 0 USDC | 100 MB | 无限 |
| Basic | 3 | 5 USDC | 50 USDC | 无限 | 100 GB |
| Premium | 4 | 10 USDC | 100 USDC | 无限 | 无限 |

---

## 项目结构

```
phase4/
├── README.md                      # 本文件 (快速开始)
├── REFACTORING_PROGRESS.md        # 重构进度追踪
├── TESTING_GUIDE.md               # 测试指南
├── contracts/                     # 智能合约
│   ├── src/VPNSubscriptionV2.sol # V2.1 合约源码
│   ├── test/VPNSubscriptionV2.t.sol
│   ├── script/DeployV2.s.sol
│   └── DEPLOYMENT.md
├── subscription-service/          # Node.js 后端服务
│   ├── index.js                  # Express API
│   ├── traffic-tracker.js        # 流量追踪服务
│   ├── renewal-service.js        # 自动续费服务
│   ├── mock-db.js                # 本地测试数据库
│   └── package.json
└── frontend/                      # Web 前端 (待开发)
    ├── index.html
    ├── app.js
    └── README.md
```

---

## API 端点

### 套餐管理
- `GET /api/plans` - 查询所有活跃套餐
- `GET /api/plan/:planId` - 查询单个套餐详情

### 流量管理
- `GET /api/traffic/:identityAddress` - 查询流量使用
- `POST /api/traffic/record` - VPN 服务器上报流量

### 订阅变更
- `GET /api/subscription/proration` - 计算升级补差价
- `POST /api/subscription/upgrade` - 升级订阅 (立即生效)
- `POST /api/subscription/downgrade` - 降级订阅 (下周期生效)
- `POST /api/subscription/cancel-change` - 取消待生效变更

---

## 测试状态

详细测试步骤请查看 [TESTING_GUIDE.md](TESTING_GUIDE.md)

**Phase 1-2 测试状态**:
- ✅ 合约单元测试 (31/31 通过)
- ✅ 后端 API 集成
- ✅ 流量追踪服务
- ✅ 自动续费服务
- ⏸️ 前端集成测试 (待 Phase 3)

---

## 参考资料

- [V2.1 技术方案](../usdc_subscription_payment_v3.md)
- [重构进度追踪](REFACTORING_PROGRESS.md)
- [测试指南](TESTING_GUIDE.md)
- [合约部署文档](contracts/DEPLOYMENT.md)
- [CDP Paymaster 文档](https://docs.cdp.coinbase.com/paymaster/introduction/welcome)
- [EIP-712 规范](https://eips.ethereum.org/EIPS/eip-712)

---

**最后更新**: 2026-04-14  
**当前状态**: Phase 1-2 已完成,可进入 Phase 3 前端开发
