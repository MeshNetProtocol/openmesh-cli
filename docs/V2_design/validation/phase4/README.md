# OpenMesh VPN 订阅服务 - Phase 4

基于 EIP-712 签名和 CDP Paymaster 的 0 ETH 订阅系统。

## 📚 完整文档

**请查看 [COMPLETE_GUIDE.md](COMPLETE_GUIDE.md) 获取完整的技术文档、测试步骤和部署指南。**

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

### 3. 启动前端

```bash
cd frontend
python3 -m http.server 8080
```

访问 `http://localhost:8080`

### 4. 完成订阅

1. 点击"连接 MetaMask"
2. 选择订阅套餐
3. 输入 VPN 身份地址
4. 签名两次 (EIP-712 + Permit)
5. 等待交易确认 (0 ETH gas)
6. 订阅激活成功

---

## 核心特性

- ✅ **0 ETH Gas**: 通过 CDP Paymaster 赞助所有交易
- ✅ **EIP-712 签名**: 用户链下签名,安全可验证
- ✅ **智能合约**: VPNSubscription.sol 部署在 Base Sepolia
- ✅ **自动续费**: 后台服务自动监控和执行续费
- ✅ **订阅管理**: 完整的订阅/取消/查询 API

## 已部署资源

```
智能合约: 0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2
CDP Server Wallet: 0x8c145d6ae710531A13952337Bf2e8A31916963F3
USDC (Base Sepolia): 0x036CbD53842c5426634e7929541eC2318f3dCF7e
网络: Base Sepolia (Chain ID: 84532)
区块浏览器: https://sepolia.basescan.org
```

## 订阅计划

| Plan ID | 名称 | 价格 | 周期 |
|---------|------|------|------|
| 1 | 月付套餐 | 5 USDC | 30 天 |
| 2 | 年付套餐 | 50 USDC | 365 天 |

---

## 核心测试步骤

详细测试步骤请查看 [COMPLETE_GUIDE.md - 核心测试步骤](COMPLETE_GUIDE.md#核心测试步骤)

**快速测试清单**:
1. ✅ 完整订阅流程 (端到端)
2. ✅ 查询订阅状态
3. ✅ 自动续费服务
4. ✅ 取消订阅
5. ✅ CDP Paymaster Gas 赞助验证

---

## 项目结构

```
phase4/
├── COMPLETE_GUIDE.md           # 📚 完整技术文档 (必读!)
├── README.md                   # 本文件 (快速开始)
├── contracts/                  # 智能合约
│   └── src/VPNSubscription.sol
├── subscription-service/       # Node.js 后端服务
│   ├── index.js               # Express API
│   ├── cdp-transaction.js     # CDP 交易模块
│   ├── renewal-service.js     # 自动续费服务
│   └── package.json
├── frontend/                   # Web 前端
│   ├── index.html             # 订阅页面
│   ├── app.js                 # 前端逻辑
│   └── README.md
└── archive/                    # 历史文档
```

---

## API 端点

完整 API 文档请查看 [COMPLETE_GUIDE.md - API 文档](COMPLETE_GUIDE.md#api-文档)

**核心端点**:
- `GET /api/config` - 获取配置
- `POST /api/subscription/prepare` - 准备订阅签名
- `POST /api/subscription/subscribe` - 执行订阅
- `POST /api/subscription/cancel` - 取消订阅
- `GET /api/subscription/:address` - 查询订阅
- `GET /api/renewal/status` - 自动续费状态

---

## 故障排查

常见问题和解决方案请查看 [COMPLETE_GUIDE.md - 故障排查](COMPLETE_GUIDE.md#故障排查)

---

## 参考资料

- [完整技术文档](COMPLETE_GUIDE.md) - 必读!
- [前端集成指南](frontend/README.md)
- [CDP Paymaster 文档](https://docs.cdp.coinbase.com/paymaster/introduction/welcome)
- [EIP-712 规范](https://eips.ethereum.org/EIPS/eip-712)
- [Base Sepolia 区块浏览器](https://sepolia.basescan.org)

---

**最后更新**: 2026-04-11  
**状态**: ✅ 核心功能已完成,可进行测试
