# Phase 1 工作计划：Metering Service 生产开发

**基于 Phase 0 验证结果**
**创建日期**：2026-03-24
**预计周期**：1.5-2 周

---

## 一、Phase 0 验证结论

### ✅ 核心验证结果

**Hysteria2 技术方案完全可行**：
- 无需修改 Hysteria2 源码
- 流量统计准确（包含 5-6% HTTPS 协议开销，这是正确的计费方式）
- 定时采集机制可靠（每 10-15 秒 + `?clear=true` 增量统计）
- 完整的超额处理闭环已验证（标记 + kick + 拒绝重连）
- Metering Service 原型已实现并可用

### 📦 可用资源

**原型代码位置**：`openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/`

包含：
- `collector.go` - 流量采集器（定时拉取各节点 Traffic Stats API）
- `database.go` - 数据库管理（SQLite，用户、节点、流量日志）
- `quota.go` - 配额检查器（自动检测超额并封禁）
- `main.go` - 主服务（调度器、HTTP API）
- `schema.sql` - 数据库设计

**测试脚本**：`openmesh-apple/docs/v2/Hysteria2_Validation/tests/`
- 10 个可重复执行的测试脚本
- 覆盖单节点、多节点、流量控制、超额处理等场景

**验证报告**：`openmesh-apple/docs/v2/Hysteria2_Validation/results/`
- 5 个阶段的详细测试报告
- 性能数据、准确度数据、关键发现

---

## 二、Phase 1 目标

**将 Phase 0 原型升级为生产级 Metering Service**

### 核心功能

1. **流量采集**
   - 定时拉取所有节点的 Traffic Stats API
   - 计算流量增量（避免重复计数）
   - 按用户 ID 汇总多节点流量

2. **配额管理**
   - 原子性扣减配额
   - 配额查询 API（供客户端调用）
   - 超额自动封禁

3. **节点管理**
   - 动态添加/删除节点
   - 节点健康检查
   - 节点故障隔离

4. **用户管理**
   - 创建用户
   - 设置配额
   - 查询流量使用情况

---

## 三、技术升级计划

### 3.1 数据库升级

**从 SQLite 迁移到 PostgreSQL**

原因：
- 生产环境需要更好的并发性能
- 支持更复杂的查询和索引
- 更好的数据完整性保证

任务：
- [ ] 设计 PostgreSQL 表结构（基于 schema.sql）
- [ ] 编写数据库迁移脚本
- [ ] 更新 database.go 使用 PostgreSQL 驱动
- [ ] 添加连接池管理

### 3.2 配置管理

**添加灵活的配置系统**

原型使用硬编码配置，生产需要：
- [ ] 环境变量支持（12-factor app）
- [ ] 配置文件支持（YAML/TOML）
- [ ] 配置验证和默认值
- [ ] 敏感信息加密（数据库密码、API 密钥）

配置项：
```yaml
database:
  host: localhost
  port: 5432
  name: metering
  user: metering_user
  password: ${DB_PASSWORD}  # 从环境变量读取

collector:
  interval: 15s
  timeout: 5s

nodes:
  - name: node-a
    stats_url: http://node-a:8081/traffic
    stats_secret: ${NODE_A_SECRET}
  - name: node-b
    stats_url: http://node-b:8081/traffic
    stats_secret: ${NODE_B_SECRET}

auth_api:
  url: http://auth-api:8080
  timeout: 3s

server:
  port: 8090
  log_level: info
```

### 3.3 API 设计

**RESTful HTTP API**

#### 配额查询 API（供客户端调用）
```
GET /api/v1/quota/{user_id}
Response: {
  "user_id": "user_001",
  "total_quota": 1073741824,
  "used": 536870912,
  "remaining": 536870912,
  "status": "active"
}
```

#### 流量统计查询 API
```
GET /api/v1/traffic/{user_id}?start_time=xxx&end_time=xxx
Response: {
  "user_id": "user_001",
  "logs": [
    {
      "timestamp": "2026-03-24T10:00:00Z",
      "tx": 1024000,
      "rx": 2048000,
      "node": "node-a"
    }
  ]
}
```

#### 节点管理 API
```
POST /api/v1/admin/nodes
Body: {
  "name": "node-c",
  "stats_url": "http://node-c:8081/traffic",
  "stats_secret": "secret"
}

GET /api/v1/admin/nodes
DELETE /api/v1/admin/nodes/{node_id}
```

#### 用户管理 API
```
POST /api/v1/admin/users
Body: {
  "user_id": "user_002",
  "quota": 1073741824
}

PUT /api/v1/admin/users/{user_id}/quota
Body: {
  "quota": 2147483648
}
```

### 3.4 日志和监控

**结构化日志**
- [ ] 使用 zerolog 或 zap
- [ ] JSON 格式输出
- [ ] 日志级别控制
- [ ] 关键事件记录（采集成功/失败、超额封禁、API 调用）

**监控指标**
- [ ] Prometheus metrics 导出
  - 采集成功率
  - 采集延迟
  - API 响应时间
  - 活跃用户数
  - 超额用户数
- [ ] 健康检查端点（`/health`）

### 3.5 错误处理和重试

**健壮的错误处理**
- [ ] 采集失败重试机制（指数退避）
- [ ] 节点故障隔离（连续失败后暂时跳过）
- [ ] 数据库连接失败恢复
- [ ] API 超时处理

### 3.6 Docker 容器化

**生产部署准备**
- [ ] 编写 Dockerfile（多阶段构建）
- [ ] Docker Compose 配置（Metering + PostgreSQL）
- [ ] 环境变量配置
- [ ] 数据持久化（volume）

---

## 四、实施步骤

### Week 1: 核心功能开发（5-7 天）

#### Day 1-2: 项目结构和数据库
- [ ] 创建生产代码库结构
- [ ] 设计 PostgreSQL 表结构
- [ ] 实现数据库层（连接池、CRUD）
- [ ] 编写数据库迁移脚本

#### Day 3-4: 流量采集和配额管理
- [ ] 迁移 collector.go（添加配置、日志、错误处理）
- [ ] 迁移 quota.go（添加 API、监控）
- [ ] 实现节点管理逻辑
- [ ] 实现用户管理逻辑

#### Day 5-7: API 和配置
- [ ] 实现 HTTP API（配额查询、流量查询）
- [ ] 实现管理 API（节点、用户）
- [ ] 配置管理系统
- [ ] 日志和监控集成

### Week 2: 集成测试和部署（3-5 天）

#### Day 8-9: 集成测试
- [ ] 端到端测试（Metering + Hysteria2 + 认证 API）
- [ ] 性能测试（并发用户、多节点）
- [ ] 故障恢复测试（节点故障、数据库重启）

#### Day 10-11: Docker 和部署
- [ ] Docker 容器化
- [ ] Docker Compose 配置
- [ ] 部署文档编写
- [ ] 运维手册编写

#### Day 12: 文档和交付
- [ ] API 文档（OpenAPI/Swagger）
- [ ] 部署指南
- [ ] 监控和告警配置指南
- [ ] Phase 1 完成报告

---

## 五、技术决策

### 需要确认的选择

1. **数据库**
   - 推荐：PostgreSQL
   - 备选：MySQL
   - 决策依据：PostgreSQL 更好的 JSON 支持、更强的数据完整性

2. **部署方式**
   - 推荐：Docker Compose（开发/测试）
   - 生产：Kubernetes（可选，Phase 2）
   - 决策依据：Docker Compose 简单易用，满足初期需求

3. **认证方式**
   - 推荐：API Key（简单、够用）
   - 备选：JWT（更复杂，Phase 2 可考虑）
   - 决策依据：API Key 满足当前需求，实现简单

4. **日志方案**
   - 推荐：结构化日志（JSON）+ stdout
   - 聚合：可选（ELK/Loki，Phase 2）
   - 决策依据：stdout 配合 Docker 日志驱动即可

---

## 六、验收标准

### 功能验收

- [ ] 流量采集成功率 > 99%
- [ ] 配额扣减无超额（原子性保证）
- [ ] API 响应时间 < 100ms（P95）
- [ ] 支持至少 10 个并发用户
- [ ] 支持至少 5 个节点

### 性能验收

- [ ] 采集延迟 < 1 秒
- [ ] 数据库查询 < 50ms
- [ ] 内存使用 < 512MB
- [ ] CPU 使用 < 50%（正常负载）

### 可靠性验收

- [ ] 节点故障不影响其他节点
- [ ] 数据库重启后自动恢复
- [ ] 采集失败自动重试
- [ ] 无数据丢失

---

## 七、风险和应对

| 风险 | 可能性 | 影响 | 应对方案 |
|------|--------|------|---------|
| 数据库迁移复杂 | 中 | 中 | 使用 ORM 或迁移工具，充分测试 |
| 性能不达标 | 低 | 高 | 基于原型已验证，添加性能测试 |
| 配置管理复杂 | 低 | 低 | 使用成熟的配置库（viper） |
| Docker 部署问题 | 低 | 中 | 提前测试，编写详细文档 |

---

## 八、交付物

### 代码
- [ ] 生产级 Metering Service（Go）
- [ ] 数据库迁移脚本
- [ ] Docker 配置文件
- [ ] 测试代码

### 文档
- [ ] API 文档（OpenAPI）
- [ ] 部署指南
- [ ] 运维手册
- [ ] 监控配置指南
- [ ] Phase 1 完成报告

### 配置
- [ ] 示例配置文件
- [ ] Docker Compose 配置
- [ ] 环境变量模板

---

## 九、后续阶段预览

### Phase 2: Payment Service（1 周）
- x402 支付签名验证
- USDC → 流量配额兑换
- 购买记录存储

### Phase 3: 客户端集成（2 周）
- Hysteria2 配置生成
- 流量监控显示
- 钱包集成

### Phase 4: 供应商发现（1 周）
- Base 链上集成
- 供应商快速切换

---

**准备好开始 Phase 1 了吗？**

建议先确认技术决策（数据库、部署方式、认证方式），然后开始 Day 1 的工作。
