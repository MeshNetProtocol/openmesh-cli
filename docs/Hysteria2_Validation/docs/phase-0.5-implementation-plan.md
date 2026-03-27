# Phase 0.5 Metering Service 原型实现 - 计划

**日期**: 2026-03-24
**状态**: 📋 计划中

---

## 一、目标

实现一个完整的流量采集和计费原型（Metering Service），整合 Phase 0.1-0.4 验证的所有功能。

### 核心功能

1. **定时采集**: 每 10 秒并发拉取所有节点的流量数据
2. **流量汇总**: 聚合多节点的增量流量
3. **数据持久化**: 将流量数据写入 SQLite 数据库
4. **配额检查**: 检测超额用户并执行封禁
5. **错误处理**: 处理节点故障和采集失败

---

## 二、架构设计

### 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                   Metering Service                       │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ 定时调度器    │  │ 流量采集器    │  │ 配额检查器    │ │
│  │ (每 10 秒)   │→ │ (并发拉取)   │→ │ (超额处理)   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         ↓                  ↓                  ↓         │
│  ┌──────────────────────────────────────────────────┐  │
│  │              SQLite 数据库                        │  │
│  │  - users (用户配额)                               │  │
│  │  - traffic_logs (流量记录)                        │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         ↓                                    ↓
┌─────────────────┐                  ┌─────────────────┐
│  Node A (8443)  │                  │  Node B (8444)  │
│  Stats: 8081    │                  │  Stats: 8082    │
└─────────────────┘                  └─────────────────┘
         ↓                                    ↓
┌─────────────────────────────────────────────────────────┐
│              认证 API (8080)                             │
│  - 检查用户状态                                          │
│  - 返回认证结果                                          │
└─────────────────────────────────────────────────────────┘
```

### 核心组件

**1. 节点管理器 (NodeManager)**
- 管理所有 Hysteria2 节点配置
- 提供节点列表

**2. 流量采集器 (TrafficCollector)**
- 并发拉取所有节点的 `/traffic?clear=true`
- 汇总各节点的增量流量
- 错误处理和重试

**3. 数据库管理器 (DatabaseManager)**
- 用户配额管理
- 流量记录持久化
- 查询和统计

**4. 配额检查器 (QuotaChecker)**
- 检查用户是否超额
- 调用认证 API 标记用户
- 调用 `/kick` API 踢出用户

**5. 定时调度器 (Scheduler)**
- 每 10 秒触发一次采集
- 协调各组件工作

---

## 三、数据库设计

### 表结构

**users 表**:
```sql
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    quota INTEGER NOT NULL,           -- 配额（bytes）
    used INTEGER NOT NULL DEFAULT 0,  -- 已用流量（bytes）
    status TEXT NOT NULL DEFAULT 'active',  -- active/blocked
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**traffic_logs 表**:
```sql
CREATE TABLE traffic_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    tx INTEGER NOT NULL,              -- 上传流量（bytes）
    rx INTEGER NOT NULL,              -- 下载流量（bytes）
    collected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);
```

**nodes 表**:
```sql
CREATE TABLE nodes (
    node_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    traffic_api_url TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## 四、实现计划

### 阶段 1: 数据库和基础设施

**任务**:
1. 创建 SQLite 数据库
2. 实现数据库管理器
3. 初始化测试数据

**产出**:
- `prototype/metering/database.go`
- `prototype/metering/schema.sql`

---

### 阶段 2: 流量采集器

**任务**:
1. 实现节点管理器
2. 实现流量采集器（并发拉取）
3. 实现流量汇总逻辑

**产出**:
- `prototype/metering/collector.go`
- `prototype/metering/nodes.go`

**核心逻辑**:
```go
func (c *Collector) CollectAll() (map[string]Traffic, error) {
    nodes := c.nodeManager.GetNodes()
    results := make(chan NodeTraffic, len(nodes))
    errors := make(chan error, len(nodes))

    // 并发采集
    for _, node := range nodes {
        go func(n Node) {
            traffic, err := c.fetchNode(n)
            if err != nil {
                errors <- err
                return
            }
            results <- NodeTraffic{NodeID: n.ID, Traffic: traffic}
        }(node)
    }

    // 汇总结果
    aggregated := make(map[string]Traffic)
    for i := 0; i < len(nodes); i++ {
        select {
        case result := <-results:
            for userID, traffic := range result.Traffic {
                aggregated[userID].Tx += traffic.Tx
                aggregated[userID].Rx += traffic.Rx
            }
        case err := <-errors:
            log.Printf("Node collection error: %v", err)
        }
    }

    return aggregated, nil
}
```

---

### 阶段 3: 配额检查器

**任务**:
1. 实现配额检查逻辑
2. 集成认证 API（标记用户）
3. 集成 Traffic Stats API（踢出用户）

**产出**:
- `prototype/metering/quota.go`

**核心逻辑**:
```go
func (q *QuotaChecker) CheckAndEnforce(userID string) error {
    user, err := q.db.GetUser(userID)
    if err != nil {
        return err
    }

    if user.Used > user.Quota {
        // 1. 标记用户为 blocked
        if err := q.authAPI.SetUserStatus(userID, "blocked"); err != nil {
            return err
        }

        // 2. 踢出所有节点的连接
        for _, node := range q.nodes.GetNodes() {
            if err := q.kickUser(node, userID); err != nil {
                log.Printf("Failed to kick user %s from node %s: %v",
                    userID, node.ID, err)
            }
        }

        // 3. 更新数据库状态
        return q.db.UpdateUserStatus(userID, "blocked")
    }

    return nil
}
```

---

### 阶段 4: 主服务和定时调度

**任务**:
1. 实现主服务入口
2. 实现定时调度器
3. 整合所有组件

**产出**:
- `prototype/metering/main.go`
- `prototype/metering/scheduler.go`

**核心逻辑**:
```go
func (s *Scheduler) Start() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            s.runCollection()
        case <-s.stopCh:
            return
        }
    }
}

func (s *Scheduler) runCollection() {
    // 1. 采集流量
    traffic, err := s.collector.CollectAll()
    if err != nil {
        log.Printf("Collection error: %v", err)
        return
    }

    // 2. 更新数据库
    for userID, t := range traffic {
        if err := s.db.IncrementTraffic(userID, t.Tx, t.Rx); err != nil {
            log.Printf("Failed to update traffic for %s: %v", userID, err)
            continue
        }

        // 3. 检查配额
        if err := s.quotaChecker.CheckAndEnforce(userID); err != nil {
            log.Printf("Quota check error for %s: %v", userID, err)
        }
    }
}
```

---

### 阶段 5: 测试和验证

**任务**:
1. 编写集成测试
2. 验证完整流程
3. 性能测试

**测试场景**:
1. 正常流量采集和累加
2. 超额用户自动封禁
3. 节点故障处理
4. 并发采集性能

---

## 五、配置文件

### metering-config.yaml

```yaml
database:
  path: ./data/metering.db

nodes:
  - id: node-a
    name: Node A
    traffic_api_url: http://127.0.0.1:8081
    secret: test_secret_key_12345

  - id: node-b
    name: Node B
    traffic_api_url: http://127.0.0.1:8082
    secret: test_secret_key_12345

auth_api:
  url: http://127.0.0.1:8080
  set_status_endpoint: /api/v1/admin/set-status

scheduler:
  interval: 10s

logging:
  level: info
  file: ./logs/metering.log
```

---

## 六、测试计划

### 集成测试

**测试 1: 正常流量采集**
```bash
# 1. 启动所有服务
# 2. 用户产生流量
# 3. 等待采集周期
# 4. 验证数据库记录
```

**测试 2: 超额自动封禁**
```bash
# 1. 设置用户配额为 100KB
# 2. 用户下载 200KB
# 3. 等待采集和检查
# 4. 验证用户被封禁
# 5. 验证无法重连
```

**测试 3: 多节点流量汇总**
```bash
# 1. 用户在 Node A 下载 100KB
# 2. 用户在 Node B 下载 100KB
# 3. 验证数据库总流量 = 200KB
```

**测试 4: 节点故障处理**
```bash
# 1. 停止 Node B
# 2. 等待采集周期
# 3. 验证 Node A 的流量仍被记录
# 4. 验证服务继续运行
```

---

## 七、成功标准

Phase 0.5 成功完成的标准：

1. ✅ 定期采集成功率 > 99%
2. ✅ 增量计算准确（无重复扣减）
3. ✅ 多节点汇总准确
4. ✅ 超额用户被正确阻止
5. ✅ 错误重试机制有效
6. ✅ 数据库持久化正常
7. ✅ 所有集成测试通过

---

## 八、实施时间表

- **阶段 1**: 数据库和基础设施（1-2 小时）
- **阶段 2**: 流量采集器（2-3 小时）
- **阶段 3**: 配额检查器（1-2 小时）
- **阶段 4**: 主服务和调度（1 小时）
- **阶段 5**: 测试和验证（2-3 小时）

**总计**: 约 7-11 小时

---

**下一步**: 开始实现阶段 1 - 数据库和基础设施
