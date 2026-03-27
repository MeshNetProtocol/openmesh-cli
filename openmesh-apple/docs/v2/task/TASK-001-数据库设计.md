# TASK-001: 项目结构和 PostgreSQL 数据库设计

## 任务信息

- **任务编号**: TASK-001
- **所属阶段**: Phase 1 - Week 1 (Day 1-2)
- **预计时间**: 2 天
- **依赖任务**: 无
- **状态**: 待开始

## 任务目标

创建生产级 Metering Service 的项目结构,并将 Phase 0 原型的 SQLite 数据库升级为 PostgreSQL,实现完整的数据库层功能。

## 技术背景

### Phase 0 原型情况

**原型代码位置**: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/`

**现有数据库实现**:
- 使用 SQLite 数据库
- 文件: `database.go` (237 行)
- 表结构: `schema.sql`
  - `users` 表: 用户配额管理
  - `traffic_logs` 表: 流量日志记录
  - `nodes` 表: 节点信息管理

**原型的局限性**:
- SQLite 并发性能有限,不适合生产环境
- 缺乏连接池管理
- 缺乏数据库迁移机制
- 硬编码的数据库路径

### 为什么升级到 PostgreSQL

1. **更好的并发性能**: 支持多个采集器同时写入
2. **更强的数据完整性**: ACID 保证、外键约束
3. **更好的 JSON 支持**: 便于存储复杂数据结构
4. **生产级特性**: 复制、备份、监控工具完善

## 工作范围

### 1. 创建项目结构

创建生产代码库的目录结构:

```
openmesh-apple/metering-service/
├── cmd/
│   └── metering/
│       └── main.go              # 服务入口
├── internal/
│   ├── config/                  # 配置管理
│   ├── database/                # 数据库层
│   │   ├── db.go               # 数据库连接和连接池
│   │   ├── user.go             # 用户相关操作
│   │   ├── traffic.go          # 流量日志操作
│   │   ├── node.go             # 节点管理操作
│   │   └── migrations/         # 数据库迁移脚本
│   ├── collector/               # 流量采集器
│   ├── quota/                   # 配额管理器
│   ├── api/                     # HTTP API
│   └── logger/                  # 日志管理
├── pkg/
│   └── models/                  # 数据模型
│       ├── user.go
│       ├── traffic.go
│       └── node.go
├── migrations/                  # SQL 迁移文件
│   ├── 001_initial_schema.up.sql
│   └── 001_initial_schema.down.sql
├── configs/                     # 配置文件示例
│   └── config.example.yaml
├── scripts/                     # 工具脚本
├── go.mod
├── go.sum
└── README.md
```

### 2. 设计 PostgreSQL 表结构

基于 Phase 0 的 `schema.sql`,设计 PostgreSQL 版本:

**users 表**:
```sql
CREATE TABLE users (
    user_id VARCHAR(255) PRIMARY KEY,
    quota BIGINT NOT NULL,
    used BIGINT NOT NULL DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_quota_positive CHECK (quota >= 0),
    CONSTRAINT check_used_non_negative CHECK (used >= 0),
    CONSTRAINT check_status CHECK (status IN ('active', 'blocked'))
);

CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_updated_at ON users(updated_at);
```

**traffic_logs 表**:
```sql
CREATE TABLE traffic_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    node_id VARCHAR(255) NOT NULL,
    tx BIGINT NOT NULL,
    rx BIGINT NOT NULL,
    collected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_node FOREIGN KEY (node_id) REFERENCES nodes(node_id) ON DELETE CASCADE,
    CONSTRAINT check_tx_non_negative CHECK (tx >= 0),
    CONSTRAINT check_rx_non_negative CHECK (rx >= 0)
);

CREATE INDEX idx_traffic_logs_user_id ON traffic_logs(user_id);
CREATE INDEX idx_traffic_logs_node_id ON traffic_logs(node_id);
CREATE INDEX idx_traffic_logs_collected_at ON traffic_logs(collected_at);
CREATE INDEX idx_traffic_logs_user_collected ON traffic_logs(user_id, collected_at DESC);
```

**nodes 表**:
```sql
CREATE TABLE nodes (
    node_id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    traffic_api_url TEXT NOT NULL,
    secret TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_name_not_empty CHECK (name <> ''),
    CONSTRAINT check_url_not_empty CHECK (traffic_api_url <> '')
);

CREATE INDEX idx_nodes_enabled ON nodes(enabled);
CREATE INDEX idx_nodes_last_seen ON nodes(last_seen_at);
```

### 3. 实现数据库层

**核心功能**:

1. **连接管理** (`internal/database/db.go`):
   - PostgreSQL 连接池配置
   - 连接健康检查
   - 优雅关闭

2. **用户操作** (`internal/database/user.go`):
   - `CreateUser(userID string, quota int64)` - 创建用户
   - `GetUser(userID string)` - 获取用户信息
   - `GetAllUsers()` - 获取所有用户
   - `IncrementTraffic(userID string, tx, rx int64)` - 原子性增加流量
   - `UpdateUserStatus(userID, status string)` - 更新用户状态
   - `UpdateUserQuota(userID string, quota int64)` - 更新配额

3. **流量日志操作** (`internal/database/traffic.go`):
   - `LogTraffic(userID, nodeID string, tx, rx int64)` - 记录流量
   - `GetUserTrafficLogs(userID string, startTime, endTime time.Time, limit int)` - 查询流量日志
   - `GetTrafficStats(userID string, startTime, endTime time.Time)` - 统计流量

4. **节点操作** (`internal/database/node.go`):
   - `CreateNode(node *models.Node)` - 创建节点
   - `GetNode(nodeID string)` - 获取节点信息
   - `GetNodes()` - 获取所有启用的节点
   - `GetAllNodes()` - 获取所有节点(包括禁用的)
   - `UpdateNode(node *models.Node)` - 更新节点信息
   - `DeleteNode(nodeID string)` - 删除节点
   - `UpdateNodeLastSeen(nodeID string)` - 更新节点最后在线时间

### 4. 数据库迁移

使用 [golang-migrate](https://github.com/golang-migrate/migrate) 实现迁移:

1. 创建迁移文件:
   - `migrations/001_initial_schema.up.sql` - 创建表
   - `migrations/001_initial_schema.down.sql` - 回滚

2. 实现迁移工具:
   - 自动执行迁移
   - 支持版本管理
   - 支持回滚

## 技术约束

1. **不能修改 Hysteria2 源码**: 数据库设计必须适配现有的 Traffic Stats API
2. **保持向后兼容**: 数据模型要与 Phase 0 原型兼容
3. **性能要求**:
   - 数据库查询 < 50ms
   - 支持至少 10 个并发连接
   - 流量记录写入延迟 < 10ms

## 依赖

### 外部依赖
- PostgreSQL 14+ 数据库
- Go 1.21+
- 第三方库:
  - `github.com/lib/pq` - PostgreSQL 驱动
  - `github.com/golang-migrate/migrate/v4` - 数据库迁移
  - `github.com/jmoiron/sqlx` - SQL 扩展(可选,简化查询)

### 参考资料
- Phase 0 原型: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/`
  - `database.go` - 原型数据库实现
  - `schema.sql` - 原型表结构
- Phase 1 工作计划: `openmesh-apple/docs/v2/Phase1-工作计划.md`

## 交付物

### 代码文件
- [ ] `cmd/metering/main.go` - 服务入口(基础框架)
- [ ] `internal/database/db.go` - 数据库连接管理
- [ ] `internal/database/user.go` - 用户操作
- [ ] `internal/database/traffic.go` - 流量日志操作
- [ ] `internal/database/node.go` - 节点操作
- [ ] `pkg/models/user.go` - 用户数据模型
- [ ] `pkg/models/traffic.go` - 流量数据模型
- [ ] `pkg/models/node.go` - 节点数据模型
- [ ] `migrations/001_initial_schema.up.sql` - 初始化迁移
- [ ] `migrations/001_initial_schema.down.sql` - 回滚迁移
- [ ] `go.mod` 和 `go.sum` - 依赖管理

### 测试
- [ ] `internal/database/user_test.go` - 用户操作单元测试
- [ ] `internal/database/traffic_test.go` - 流量操作单元测试
- [ ] `internal/database/node_test.go` - 节点操作单元测试
- [ ] 集成测试脚本(连接真实 PostgreSQL)

### 文档
- [ ] `README.md` - 项目说明和快速开始
- [ ] `internal/database/README.md` - 数据库层使用文档
- [ ] 数据库设计文档(表结构、索引、约束说明)

## 验收标准

### 功能验收
- [ ] 所有 CRUD 操作正常工作
- [ ] 流量增量操作是原子性的(无并发问题)
- [ ] 外键约束正确工作
- [ ] 数据库迁移可以正常执行和回滚
- [ ] 连接池正常工作,无连接泄漏

### 性能验收
- [ ] 单次查询延迟 < 50ms
- [ ] 支持 10 个并发连接
- [ ] 流量记录写入延迟 < 10ms
- [ ] 批量插入 1000 条流量日志 < 1 秒

### 代码质量
- [ ] 所有函数有错误处理
- [ ] 使用 prepared statements 防止 SQL 注入
- [ ] 数据库连接正确关闭,无资源泄漏
- [ ] 代码符合 Go 最佳实践

## 实施建议

### 第一步: 创建项目结构
```bash
cd openmesh-apple
mkdir -p metering-service/{cmd/metering,internal/{database,config,collector,quota,api,logger},pkg/models,migrations,configs,scripts}
cd metering-service
go mod init github.com/openmesh/metering-service
```

### 第二步: 安装依赖
```bash
go get github.com/lib/pq
go get github.com/golang-migrate/migrate/v4
go get github.com/jmoiron/sqlx
```

### 第三步: 编写迁移文件
先创建 SQL 迁移文件,确保表结构正确。

### 第四步: 实现数据库层
按照 user → traffic → node 的顺序实现,每个模块完成后编写单元测试。

### 第五步: 集成测试
使用 Docker 启动 PostgreSQL 进行集成测试。

## 注意事项

1. **原子性**: `IncrementTraffic` 必须使用事务或原子操作,避免并发问题
2. **连接池**: 合理配置连接池大小,避免连接耗尽
3. **索引**: 确保查询性能,特别是 `traffic_logs` 表
4. **时区**: 统一使用 UTC 时间,避免时区问题
5. **错误处理**: 区分数据库错误类型(连接错误、约束错误、数据不存在等)

## 参考 Phase 0 原型

在实现时,参考原型代码的逻辑,但要注意:
- 原型使用 `database/sql`,生产版本可以考虑使用 `sqlx` 简化代码
- 原型没有连接池配置,生产版本必须配置
- 原型的错误处理较简单,生产版本需要更详细的错误分类

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-001)
