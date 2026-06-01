# market-blockchain

正式服务端代码目录，对应 V1 Phase 2 订阅管理服务的工程化实现。

## 设计原则

- 参考 `docs/V2_design/validation/phase4/` 的已验证业务链路
- 保留 `subscription + authorization + charge` 核心抽象
- 正式代码与验证代码分离，验证目录不直接作为正式实现

## 快速启动

### 1. 环境准备

```bash
# 复制配置文件
cp .env.example .env

# 编辑 .env 填入数据库连接信息
# DATABASE_URL=postgres://user:password@localhost:5432/market_blockchain?sslmode=disable
```

### 2. 数据库初始化

```bash
# 创建数据库
createdb market_blockchain

# 执行 migration
psql -d market_blockchain -f internal/store/migrations/0001_phase2_initial_schema.sql
```

### 3. 启动服务

```bash
# 编译
go build -o bin/server cmd/server/main.go

# 运行
./bin/server
```

服务默认监听 `http://localhost:8080`

## API 端点

### 创建订阅

```bash
POST /api/v1/subscriptions
Content-Type: application/json

{
  "identity_address": "0x...",
  "payer_address": "0x...",
  "plan_id": "basic_monthly",
  "expected_allowance": 1000000,
  "target_allowance": 3000000,
  "permit_deadline": 1735689600000
}
```

## 当前状态

Phase 2 核心功能已实现：
- PostgreSQL 数据模型和 repositories
- 创建订阅 API
- 链上交互封装（需补充合约 ABI 绑定）
- 自动续费调度器骨架

待补齐：
- 合约 ABI 绑定和实际链上调用
- 取消订阅、升级/降级 API
- 调度器 cron 触发
- 完整的集成测试
