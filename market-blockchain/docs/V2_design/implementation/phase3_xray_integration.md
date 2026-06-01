# Phase 3: Xray 集成实施记录

**实施日期**: 2026-04-23  
**状态**: 🔄 进行中  
**负责人**: AI Assistant + User

---

## 实施概述

Phase 3 的目标是将订阅管理系统与 Xray 集成，实现：
1. 根据订阅状态自动管理 Xray 用户准入
2. 实时采集用户流量统计
3. 在管理员界面显示流量数据

---

## 已完成工作

### 1. Xray gRPC 客户端封装 ✅

**文件**: `market-blockchain/internal/xray/client.go`

**功能**:
- 使用 `xray api` 命令行工具与 Xray 通信
- 实现用户管理接口（添加、删除用户）
- 实现流量统计查询接口
- 提供流量格式化工具函数

**关键方法**:
```go
AddUser(ctx, inboundTag, email, uuid) error
RemoveUser(ctx, inboundTag, email) error
QueryUserTraffic(ctx, email) (*UserTraffic, error)
QueryAllUsersTraffic(ctx) ([]*UserTraffic, error)
FormatBytes(bytes int64) string
```

**UUID 生成策略**:
- 使用 SHA256 哈希 `identity_address` 生成确定性 UUID
- 确保同一地址始终获得相同的 UUID
- 格式：`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### 2. 生命周期入口内联 Xray 同步 ✅

**主入口文件**: `market-blockchain/internal/service/subscription_lifecycle_service.go`

**配套文件**:
- `market-blockchain/internal/xray/client.go`
- `market-blockchain/internal/app/app.go`

**功能**:
- 由统一生命周期入口直接触发 Xray 同步
- 首次激活成功（`pending -> active`）→ 添加用户到 Xray
- 用户取消 / 订阅过期（`active -> cancelled / expired`）→ 从 Xray 删除用户
- 续费成功时在保持 `active` 的同时再次确保 Xray 用户有效
- 升级 / 降级当前显式标记为 `intentional_noop`，避免语义含糊

**当前关键入口**:
```go
CompleteFirstCharge(subscription, authorization, charge, permitTxHash, chargeTxHash) error
CancelSubscription(subscription) error
ExpireSubscription(subscription, reason) error
ApplyRenewalSuccess(subscription, authorization, plan, chargeRecordID, chargeID) error
```

**说明**:
- 不再使用独立的 `xray_sync_service.go` 作为主同步入口
- 生命周期状态变化与 Xray 同步现在由 `SubscriptionLifecycleService` 统一承载
- Xray 失败采用当前最小策略：DB 状态已变化，主流程返回错误，并补写失败 event

### 3. 流量统计服务 ✅

**文件**: `market-blockchain/internal/service/traffic_stats_service.go`

**功能**:
- 定期从 Xray 查询所有用户流量
- 更新订阅记录中的流量数据
- 可配置的更新间隔（默认 10 秒）

**关键方法**:
```go
Start(ctx) // 启动定时任务
UpdateAllTrafficStats(ctx) error
```

### 4. 配置扩展 ✅

**文件**: `market-blockchain/internal/config/config.go`

**新增配置项**:
```bash
XRAY_ENABLED=true              # 是否启用 Xray 集成
XRAY_API_ADDRESS=127.0.0.1:10085  # Xray API 地址
XRAY_INBOUND_TAG=vless-in      # Xray inbound 标签
TRAFFIC_STATS_INTERVAL=10s     # 流量统计更新间隔
```

---

## 进行中工作

### 5. 应用集成 ✅

**已完成**:
- [x] 在 `app.go` 中初始化 Xray 客户端
- [x] 将 Xray client 注入 `SubscriptionLifecycleService`
- [x] 在统一生命周期入口中触发同步
- [x] 添加关闭时的 Xray client 释放逻辑

### 6. Domain 模型扩展 🔄

**待完成**:
- [ ] 在 `Subscription` 中添加流量字段
- [ ] 在 `Subscription` 中添加 Xray UUID 字段
- [ ] 更新数据库 schema

### 7. 管理员界面增强 ⏳

**待完成**:
- [ ] 在订阅列表显示流量数据
- [ ] 添加"限制用户"按钮
- [ ] 实现流量数据自动刷新
- [ ] 添加流量统计图表

### 8. 测试和文档 ⏳

**待完成**:
- [ ] 单元测试
- [ ] 集成测试（需要运行 Xray 实例）
- [ ] 手动测试完整流程
- [ ] 更新 API 文档
- [ ] 更新部署文档

---

## 技术决策

### UUID 生成策略

**决策**: 使用 SHA256 哈希 `identity_address` 生成确定性 UUID

**原因**:
- 确保同一地址始终获得相同的 UUID
- 避免需要额外的 UUID 存储
- 简化订阅-Xray 用户映射

### Xray 通信方式

**决策**: 使用 Xray gRPC API

**原因**:
- 当前代码已直接接通 `HandlerService` 与 `StatsService`
- `AddUser / RemoveUser / QueryUserTraffic / QueryAllUsersTraffic` 已通过 gRPC 实现
- 避免额外 shell 包装层，和应用内生命周期入口更一致
- 更适合后续补重试、补偿和健康检查

### 同步时机

**决策**: 事件驱动 + 定期全量同步

**原因**:
- 订阅状态变化时立即同步（实时性）
- 定期全量同步作为兜底（一致性）
- 避免状态不一致

---

## 依赖关系

### 外部依赖

- **Xray-core**: 需要安装并运行 Xray 服务器
- **Xray API**: 需要在 Xray 配置中启用 API 服务

### 配置要求

**Xray 服务器配置** (`xray_server.json`):
```json
{
  "api": {
    "tag": "api",
    "services": ["HandlerService", "StatsService"]
  },
  "stats": {},
  "policy": {
    "system": {
      "statsUserUplink": true,
      "statsUserDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "vless-in",
      "port": 10086,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      }
    },
    {
      "tag": "api",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ]
}
```

---

## 测试计划

### 单元测试

- [ ] Xray 客户端方法测试
- [ ] UUID 生成函数测试
- [ ] 同步服务逻辑测试

### 集成测试

- [ ] 启动测试 Xray 实例
- [ ] 测试用户添加/删除
- [ ] 测试流量查询
- [ ] 测试订阅状态同步

### 手动测试

1. 启动 Xray 服务器
2. 创建订阅 → 验证用户添加到 Xray
3. 生成流量 → 验证流量统计更新
4. 取消订阅 → 验证用户从 Xray 删除
5. 在管理员界面查看流量数据

---

## 已知限制

### 当前限制

- `TrafficStatsService` 的订阅映射查询语义仍需后续继续收口
- 目前没有 outbox / 自动重试 / 补偿机制
- 升级 / 降级尚未做更细粒度 Xray 套餐参数同步
- 管理员界面尚未显示完整流量与同步状态
- 没有流量告警功能

### 未来增强

- 流量配额管理
- 流量超限自动限制
- 流量趋势分析
- 多 Xray 服务器支持
- 流量数据导出

---

## 文件清单

### 新增文件

```
market-blockchain/internal/
├── xray/
│   ├── client.go              # Xray gRPC 客户端封装
│   ├── client_test.go         # 单元测试
│   └── proto/                 # Protobuf 定义（未来使用）
│       ├── stats.proto
│       └── handler.proto
└── service/
    ├── traffic_stats_service.go # 流量统计服务
    ├── subscription_lifecycle_service.go # 统一生命周期入口 + Xray 同步
```

### 修改文件

```
market-blockchain/internal/
├── config/config.go           # 添加 Xray 配置项
└── app/app.go                 # 集成 Xray 服务（待完成）
```

---

## 下一步

1. **完成应用集成** - 在 `app.go` 中初始化并启动 Xray 服务
2. **扩展 Domain 模型** - 添加流量字段到 Subscription
3. **更新数据库 schema** - 添加流量相关字段
4. **增强管理员界面** - 显示流量数据和限制按钮
5. **编写测试** - 单元测试和集成测试
6. **文档更新** - API 文档和部署指南

---

## 参考资料

- Phase 3 验证代码: `docs/V2_design/validation/phase3/`
- Xray API 文档: https://xtls.github.io/development/protocols/
- 设计文档: `docs/V2_design/DEVELOPMENT_PLAN.md`
