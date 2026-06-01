# Phase 4 目录清理计划

## 清理目标

清理旧方案的文档和代码，保留当前正在使用的核心文件，使目录结构清晰易维护。

---

## 当前使用的核心文件（保留）

### 1. 核心代码目录
- ✅ `contracts/` - VPNCreditVaultV4 智能合约
  - `src/VPNCreditVaultV4.sol` - 当前使用的合约
  - `script/DeployVPNCreditVaultV4.s.sol` - 部署脚本
  - `script/UpdateRelayer.s.sol` - Relayer 更新脚本
  - `out/` - 编译产物（保留）
  - `broadcast/` - 部署记录（保留）
  
- ✅ `subscription-service/` - 订阅服务后端
  - `index.js` - 主服务文件
  - `permit-store.js` - 状态存储
  - `permits.json` - 订阅数据
  - `contract-abi.json` - 合约 ABI
  
- ✅ `frontend/` - 订阅前端界面
  - `index.html` - 前端页面

### 2. 核心配置文件
- ✅ `.env` - 环境配置
- ✅ `.env.example` - 配置模板
- ✅ `.gitignore` - Git 忽略规则

### 3. 核心文档（保留并整理）
- ✅ `README.md` - 项目主文档
- ✅ `QUICKSTART.md` - 快速启动指南
- ✅ `CONTRACT_UPDATE_CHECKLIST.md` - 合约更新检查清单（重要）

---

## 需要删除的文件（旧方案遗留）

### 1. 旧方案文档（已过时）
- ❌ `DEPLOYMENT_V2.2.md` - V2.2 部署文档（已被 V4 替代）
- ❌ `FINAL_SMART_CONTRACT_DESIGN.md` - 旧设计文档（V4 已实现）
- ❌ `SIMPLIFIED_SUBSCRIPTION_DESIGN.md` - 旧简化方案（V4 已实现）
- ❌ `IMPLEMENTATION_PLAN.md` - V2.1 实施计划（已完成）
- ❌ `REFACTORING_PLAN.md` - 重构计划（已完成）
- ❌ `SERVER_REFACTORING_PLAN.md` - 服务端重构计划（已完成）
- ❌ `SERVER_REFACTORING_PROGRESS.md` - 重构进度报告（已完成）
- ❌ `TESTING_REPORT.md` - V2.1 测试报告（已过时）
- ❌ `DEPLOYMENT_CHECKLIST.md` - 旧部署检查列表（已被 CONTRACT_UPDATE_CHECKLIST.md 替代）

### 2. 状态文档（可归档或删除）
- ❌ `POC_ACCEPTANCE_CHECKLIST.md` - POC 验收清单（已完成验收）
- ❌ `CHAIN_INTEGRATION_SUMMARY.md` - 链上集成总结（已完成）
- ❌ `TESTNET_INTEGRATION_STATUS.md` - 测试网集成状态（已完成）
- ❌ `cancel-subscription-expected-behavior.md` - 取消订阅行为分析（临时文档）

### 3. 旧代码和测试文件
- ❌ `auth-service/` - 旧的 Go 语言认证服务（已不使用）
- ❌ `web/subscribe.html` - 旧前端页面（已被 frontend/index.html 替代）
- ❌ `test-eip3009-system.sh` - 旧测试脚本（EIP-3009 方案已废弃）
- ❌ `test-v4.html` - 临时测试页面（已有正式前端）

### 4. 旧数据文件（已不使用）
- ❌ `authorizations.json` - 旧授权数据（V4 不使用）
- ❌ `charges.json` - 旧扣费数据（V4 不使用）
- ❌ `events.json` - 旧事件数据（V4 不使用）
- ❌ `subscriptions.json` - 旧订阅数据（V4 不使用）
- ❌ `plans.json` - 旧套餐数据（V4 不使用）

### 5. 旧脚本
- ❌ `start.sh` - 旧启动脚本（功能简单，可直接用命令替代）

### 6. 空目录或无用目录
- ❌ `docs/V2_design/` - 空的嵌套目录结构

---

## 建议归档的文件（可选）

如果希望保留历史记录，可以创建 `archive/` 目录归档以下文件：

- `DEPLOYMENT_V2.2.md`
- `FINAL_SMART_CONTRACT_DESIGN.md`
- `SIMPLIFIED_SUBSCRIPTION_DESIGN.md`
- `IMPLEMENTATION_PLAN.md`
- `REFACTORING_PLAN.md`
- `POC_ACCEPTANCE_CHECKLIST.md`
- `CHAIN_INTEGRATION_SUMMARY.md`

---

## 清理后的目录结构

```
phase4/
├── .env                              # 环境配置
├── .env.example                      # 配置模板
├── .gitignore                        # Git 忽略规则
├── README.md                         # 项目主文档
├── QUICKSTART.md                     # 快速启动指南
├── CONTRACT_UPDATE_CHECKLIST.md     # 合约更新检查清单
├── contracts/                        # 智能合约
│   ├── src/
│   │   └── VPNCreditVaultV4.sol
│   ├── script/
│   │   ├── DeployVPNCreditVaultV4.s.sol
│   │   └── UpdateRelayer.s.sol
│   ├── out/                          # 编译产物
│   └── broadcast/                    # 部署记录
├── subscription-service/             # 订阅服务后端
│   ├── index.js
│   ├── permit-store.js
│   ├── permits.json
│   └── contract-abi.json
└── frontend/                         # 订阅前端
    └── index.html
```

---

## 执行步骤

### 步骤 1: 创建归档目录（可选）
```bash
mkdir -p archive/docs archive/old-code archive/old-data
```

### 步骤 2: 归档旧文档（可选）
```bash
mv DEPLOYMENT_V2.2.md archive/docs/
mv FINAL_SMART_CONTRACT_DESIGN.md archive/docs/
mv SIMPLIFIED_SUBSCRIPTION_DESIGN.md archive/docs/
mv IMPLEMENTATION_PLAN.md archive/docs/
mv REFACTORING_PLAN.md archive/docs/
mv SERVER_REFACTORING_PLAN.md archive/docs/
mv SERVER_REFACTORING_PROGRESS.md archive/docs/
mv TESTING_REPORT.md archive/docs/
mv DEPLOYMENT_CHECKLIST.md archive/docs/
mv POC_ACCEPTANCE_CHECKLIST.md archive/docs/
mv CHAIN_INTEGRATION_SUMMARY.md archive/docs/
mv TESTNET_INTEGRATION_STATUS.md archive/docs/
mv cancel-subscription-expected-behavior.md archive/docs/
```

### 步骤 3: 删除旧代码和测试文件
```bash
rm -rf auth-service/
rm -rf web/
rm -f test-eip3009-system.sh
rm -f test-v4.html
rm -f start.sh
```

### 步骤 4: 删除旧数据文件
```bash
rm -f authorizations.json
rm -f charges.json
rm -f events.json
rm -f subscriptions.json
rm -f plans.json
```

### 步骤 5: 清理空目录
```bash
rm -rf docs/
```

### 步骤 6: 或者直接删除所有旧文件（不归档）
```bash
# 删除旧文档
rm -f DEPLOYMENT_V2.2.md FINAL_SMART_CONTRACT_DESIGN.md SIMPLIFIED_SUBSCRIPTION_DESIGN.md
rm -f IMPLEMENTATION_PLAN.md REFACTORING_PLAN.md SERVER_REFACTORING_PLAN.md
rm -f SERVER_REFACTORING_PROGRESS.md TESTING_REPORT.md DEPLOYMENT_CHECKLIST.md
rm -f POC_ACCEPTANCE_CHECKLIST.md CHAIN_INTEGRATION_SUMMARY.md TESTNET_INTEGRATION_STATUS.md
rm -f cancel-subscription-expected-behavior.md

# 删除旧代码
rm -rf auth-service/ web/
rm -f test-eip3009-system.sh test-v4.html start.sh

# 删除旧数据
rm -f authorizations.json charges.json events.json subscriptions.json plans.json

# 清理空目录
rm -rf docs/
```

---

## 验证清理结果

清理完成后，运行以下命令验证：

```bash
# 检查目录结构
tree -L 2 -I 'node_modules|out|cache|broadcast'

# 验证服务仍可正常启动
cd subscription-service && node index.js

# 验证前端可访问
curl http://localhost:8080/
```

---

## 注意事项

1. **备份重要数据**：清理前确保 `permits.json` 已备份
2. **Git 提交**：清理后创建一个 commit 记录此次清理
3. **文档更新**：清理后更新 `README.md`，移除对已删除文件的引用
4. **团队通知**：如果是团队项目，通知其他成员此次清理

---

## 清理收益

- 减少目录文件数量：从 35+ 个文件减少到 ~15 个核心文件
- 清晰的目录结构：只保留当前使用的代码和文档
- 降低维护成本：减少过时文档带来的混淆
- 提高可读性：新成员更容易理解项目结构
