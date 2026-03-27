# TASK-003: 流量采集器升级

## 任务信息

- **任务编号**: TASK-003
- **所属阶段**: Phase 1 - Week 1 (Day 3-4)
- **预计时间**: 1.5 天
- **依赖任务**: TASK-001, TASK-002
- **状态**: 待开始

## 任务目标

将 Phase 0 原型的流量采集器升级为生产级实现,添加配置支持、结构化日志、错误处理和重试机制、节点故障隔离等功能。

## 技术背景

### Phase 0 原型情况

**原型代码**: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/collector.go` (155 行)

**核心功能**:
1. 并发采集所有节点的流量数据
2. 调用 Hysteria2 的 Traffic Stats API (`/traffic?clear=true`)
3. 汇总多节点的用户流量
4. 保存流量到数据库

**原型的局限性**:
- 简单的错误处理,无重试机制
- 无节点故障隔离
- 硬编码的超时时间
- 简单的日志输出
- 无监控指标

## 工作范围

### 1. 升级采集器结构

创建 `internal/collector/collector.go`:

```go
package collector

import (
    "context"
    "sync"
    "time"

    "github.com/openmesh/metering-service/internal/config"
    "github.com/openmesh/metering-service/internal/database"
    "github.com/openmesh/metering-service/pkg/models"
    "github.com/rs/zerolog"
)

// Collector 流量采集器
type Collector struct {
    db           *database.Database
    cfg          *config.CollectorConfig
    logger       zerolog.Logger
    client       *http.Client
    failureCount map[string]int  // 节点失败计数
    mu           sync.RWMutex
}

// NewCollector 创建采集器
func NewCollector(db *database.Database, cfg *config.CollectorConfig, logger zerolog.Logger) *Collector {
    return &Collector{
        db:           db,
        cfg:          cfg,
        logger:       logger,
        client:       &http.Client{Timeout: cfg.Timeout},
        failureCount: make(map[string]int),
    }
}
```

### 2. 实现采集逻辑

**核心方法**:

```go
// CollectAll 采集所有节点的流量
func (c *Collector) CollectAll(ctx context.Context) (map[string]*models.Traffic, error) {
    nodes, err := c.db.GetNodes()
    if err != nil {
        return nil, fmt.Errorf("failed to get nodes: %w", err)
    }

    // 过滤掉故障节点
    activeNodes := c.filterActiveNodes(nodes)

    if len(activeNodes) == 0 {
        c.logger.Warn().Msg("no active nodes available")
        return make(map[string]*models.Traffic), nil
    }

    // 并发采集
    results := make(chan *NodeTrafficResult, len(activeNodes))
    var wg sync.WaitGroup

    for _, node := range activeNodes {
        wg.Add(1)
        go func(n models.Node) {
            defer wg.Done()
            c.collectFromNode(ctx, n, results)
        }(node)
    }

    go func() {
        wg.Wait()
        close(results)
    }()

    // 汇总结果
    return c.aggregateResults(results)
}

// collectFromNode 从单个节点采集流量(带重试)
func (c *Collector) collectFromNode(ctx context.Context, node models.Node, results chan<- *NodeTrafficResult) {
    var lastErr error

    // 重试机制(指数退避)
    for attempt := 0; attempt < 3; attempt++ {
        if attempt > 0 {
            backoff := time.Duration(attempt) * time.Second
            time.Sleep(backoff)
        }

        traffic, err := c.fetchNodeTraffic(ctx, node)
        if err == nil {
            c.onNodeSuccess(node.NodeID)
            results <- &NodeTrafficResult{
                NodeID:  node.NodeID,
                Traffic: traffic,
                Error:   nil,
            }
            return
        }

        lastErr = err
        c.logger.Warn().
            Str("node_id", node.NodeID).
            Int("attempt", attempt+1).
            Err(err).
            Msg("failed to collect from node")
    }

    // 所有重试失败
    c.onNodeFailure(node.NodeID)
    results <- &NodeTrafficResult{
        NodeID:  node.NodeID,
        Traffic: nil,
        Error:   lastErr,
    }
}
```

### 3. 节点故障隔离

```go
const (
    maxFailureCount = 3  // 连续失败3次后隔离
    isolationPeriod = 5 * time.Minute
)

// filterActiveNodes 过滤掉故障节点
func (c *Collector) filterActiveNodes(nodes []models.Node) []models.Node {
    c.mu.RLock()
    defer c.mu.RUnlock()

    var active []models.Node
    for _, node := range nodes {
        if c.failureCount[node.NodeID] < maxFailureCount {
            active = append(active, node)
        } else {
            c.logger.Warn().
                Str("node_id", node.NodeID).
                Int("failure_count", c.failureCount[node.NodeID]).
                Msg("node isolated due to repeated failures")
        }
    }
    return active
}

// onNodeSuccess 节点采集成功
func (c *Collector) onNodeSuccess(nodeID string) {
    c.mu.Lock()
    defer c.mu.Unlock()

    if c.failureCount[nodeID] > 0 {
        c.logger.Info().
            Str("node_id", nodeID).
            Msg("node recovered")
    }
    c.failureCount[nodeID] = 0
}

// onNodeFailure 节点采集失败
func (c *Collector) onNodeFailure(nodeID string) {
    c.mu.Lock()
    defer c.mu.Unlock()

    c.failureCount[nodeID]++
    c.logger.Error().
        Str("node_id", nodeID).
        Int("failure_count", c.failureCount[nodeID]).
        Msg("node collection failed")
}
```

### 4. HTTP 请求实现

```go
// fetchNodeTraffic 从节点获取流量数据
func (c *Collector) fetchNodeTraffic(ctx context.Context, node models.Node) (map[string]*models.Traffic, error) {
    url := fmt.Sprintf("%s?clear=true", node.TrafficAPIURL)

    req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
    if err != nil {
        return nil, fmt.Errorf("failed to create request: %w", err)
    }

    req.Header.Set("Authorization", node.Secret)

    resp, err := c.client.Do(req)
    if err != nil {
        return nil, fmt.Errorf("failed to fetch traffic: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        body, _ := io.ReadAll(resp.Body)
        return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(body))
    }

    var traffic map[string]*models.Traffic
    if err := json.NewDecoder(resp.Body).Decode(&traffic); err != nil {
        return nil, fmt.Errorf("failed to decode response: %w", err)
    }

    return traffic, nil
}
```

### 5. 结果汇总和保存

```go
// aggregateResults 汇总采集结果
func (c *Collector) aggregateResults(results <-chan *NodeTrafficResult) (map[string]*models.Traffic, error) {
    aggregated := make(map[string]*models.Traffic)
    var errors []error

    for result := range results {
        if result.Error != nil {
            errors = append(errors, fmt.Errorf("node %s: %w", result.NodeID, result.Error))
            continue
        }

        // 记录每个节点的流量日志
        for userID, traffic := range result.Traffic {
            if err := c.db.LogTraffic(userID, result.NodeID, traffic.Tx, traffic.Rx); err != nil {
                c.logger.Error().
                    Str("user_id", userID).
                    Str("node_id", result.NodeID).
                    Err(err).
                    Msg("failed to log traffic")
            }

            // 汇总流量
            if _, exists := aggregated[userID]; !exists {
                aggregated[userID] = &models.Traffic{}
            }
            aggregated[userID].Tx += traffic.Tx
            aggregated[userID].Rx += traffic.Rx
        }
    }

    if len(errors) > 0 {
        c.logger.Warn().
            Int("error_count", len(errors)).
            Msg("some nodes failed to collect")
    }

    return aggregated, nil
}

// SaveTraffic 保存流量到数据库
func (c *Collector) SaveTraffic(traffic map[string]*models.Traffic) error {
    for userID, t := range traffic {
        total := t.Tx + t.Rx
        if total == 0 {
            continue
        }

        if err := c.db.IncrementTraffic(userID, int64(t.Tx), int64(t.Rx)); err != nil {
            return fmt.Errorf("failed to increment traffic for user %s: %w", userID, err)
        }

        c.logger.Debug().
            Str("user_id", userID).
            Uint64("tx", t.Tx).
            Uint64("rx", t.Rx).
            Uint64("total", total).
            Msg("traffic updated")
    }

    return nil
}
```

## 技术约束

1. **不能修改 Hysteria2 源码**: 必须使用现有的 Traffic Stats API
2. **保持 API 兼容**: 与 Phase 0 原型的 API 格式保持一致
3. **性能要求**:
   - 采集延迟 < 1 秒
   - 支持至少 5 个节点并发采集
   - 采集成功率 > 99%

## 依赖

### 内部依赖
- TASK-001: 数据库层实现
- TASK-002: 配置管理系统

### 外部依赖
- `github.com/rs/zerolog` - 结构化日志

### 参考资料
- Phase 0 原型: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/collector.go`
- Hysteria2 Traffic Stats API 文档

## 交付物

### 代码文件
- [ ] `internal/collector/collector.go` - 采集器核心实现
- [ ] `internal/collector/retry.go` - 重试机制
- [ ] `internal/collector/isolation.go` - 节点故障隔离
- [ ] `pkg/models/traffic.go` - 流量数据模型

### 测试
- [ ] `internal/collector/collector_test.go` - 单元测试
- [ ] `internal/collector/integration_test.go` - 集成测试

### 文档
- [ ] `internal/collector/README.md` - 采集器使用文档

## 验收标准

### 功能验收
- [ ] 可以并发采集多个节点
- [ ] 重试机制正常工作
- [ ] 节点故障隔离正常工作
- [ ] 流量数据正确汇总
- [ ] 结构化日志输出完整

### 性能验收
- [ ] 采集 5 个节点 < 1 秒
- [ ] 采集成功率 > 99%
- [ ] 节点故障不影响其他节点

### 代码质量
- [ ] 错误处理完善
- [ ] 日志信息清晰
- [ ] 单元测试覆盖率 > 80%

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-003)
