# Phase 4 README

## 当前目标

本目录当前只做一件事：

**围绕 `VPNCreditVaultV4` 完成一个文件型订阅服务 POC，并验证四条核心业务链路：**

1. 订阅
2. 续费
3. 取消订阅
4. 升级 / 降级

这次不做数据库版，不做复杂后台，不做完整产品化，只验证技术方案成立。

---

## 合约职责

`contracts/src/VPNCreditVaultV4.sol` 的职责已经被收敛为：

- 绑定 `identity -> payer`
- 使用 permit 设置 Vault allowance
- 使用 `chargeId` 执行扣费
- 防止重复扣费

也就是说：

- 套餐不在链上
- 订阅状态不在链上
- 取消/恢复不在链上
- 升降级业务也不在链上

这些全部由服务端 JSON 状态管理。

---

## POC 数据文件

当前推荐的文件型数据源：

- `plans.json` - 套餐配置
- `subscriptions.json` - 订阅状态
- `authorizations.json` - permit 授权记录
- `charges.json` - 扣费记录
- `events.json` - 链上事件镜像

这样即使没有数据库，也能完整验证：

- 状态是否正确流转
- charge 是否唯一
- 取消订阅后是否停止续费
- 升级/降级是否按预期工作

---

## 需要验证的业务链路

### 1. 首次订阅

流程：

- 用户选择套餐
- 服务端计算 `expectedAllowance` / `targetAllowance`
- 用户签 permit
- 服务端调用 `authorizeChargeWithPermit(...)`
- 服务端生成首次 `chargeId`
- 服务端调用 `charge(...)`
- 写入 `subscriptions.json` / `authorizations.json` / `charges.json`

### 2. 自动续费

流程：

- 服务端扫描到期订阅
- 生成本期唯一 `chargeId`
- 调用 `charge(...)`
- 推进账期并更新 `remaining_allowance`

### 3. 取消订阅

流程：

- 服务端把 `auto_renew=false`
- `status=cancelled`
- 当前账期继续有效
- 后续不再生成 renewal charge

### 4. 升级 / 降级

流程：

- 升级：服务端可立即补一笔差价 charge
- 降级：服务端只切换下一期套餐，不额外扣费

---

## 当前目录结构

```text
phase4/
├── README.md
├── QUICKSTART.md
├── SERVER_REFACTORING_PLAN.md
├── plans.json
├── subscriptions.json
├── authorizations.json
├── charges.json
├── events.json
├── auth-service/
├── contracts/
└── web/
```

---

## 当前代码现状

当前 `auth-service` 仍保留旧版 POC 痕迹，核心问题是：

- 数据模型仍是旧支付流程
- 接口命名还没有完全贴合 `VPNCreditVaultV4`
- 还残留旧的 auto renew profile 心智

但 Phase 4 的正确方向已经明确：

- 以 `subscription + authorization + charge` 为中心
- 所有业务状态落 JSON
- 链上只做授权和扣费

---

## 下一步建议

优先级建议如下：

1. 重构 `auth-service/main.go` 的数据结构
2. 把旧 JSON 文件模型切换到新的 5 个文件
3. 改写 API，让它覆盖：
   - 创建订阅
   - 授权 permit
   - 执行首次扣费
   - 执行续费
   - 取消订阅
   - 升级套餐
   - 降级套餐
4. 跑通手工测试
5. 再决定是否升级为数据库版
