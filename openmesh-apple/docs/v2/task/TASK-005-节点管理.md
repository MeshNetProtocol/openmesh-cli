# TASK-005: 节点管理功能

## 任务信息

- **任务编号**: TASK-005
- **所属阶段**: Phase 1 - Week 1 (Day 5)
- **预计时间**: 1 天
- **依赖任务**: TASK-001, TASK-002
- **状态**: 待开始

## 任务目标

实现节点管理功能,包括动态添加/删除节点、节点健康检查、节点故障隔离。

## 工作范围

### 1. 节点管理器

创建 `internal/node/manager.go`:

```go
package node

import (
    "context"
    "fmt"
    "net/http"
    "time"

    "github.com/openmesh/metering-service/internal/database"
    "github.com/openmesh/metering-service/pkg/models"
    "github.com/rs/zerolog"
)

// Manager 节点管理器
type Manager struct {
    db     *database.Database
    logger zerolog.Logger
    client *http.Client
}

// NewManager 创建节点管理器
func NewManager(db *database.Database, logger zerolog.Logger) *Manager {
    return &Manager{
        db:     db,
        logger: logger,
        client: &http.Client{Timeout: 5 * time.Second},
    }
}

// AddNode 添加节点
func (m *Manager) AddNode(ctx context.Context, node *models.Node) error {
    // 验证节点连接
    if err := m.checkNodeHealth(ctx, node); err != nil {
        return fmt.Errorf("node health check failed: %w", err)
    }

    // 保存到数据库
    if err := m.db.CreateNode(node); err != nil {
        return fmt.Errorf("failed to create node: %w", err)
    }

    m.logger.Info().
        Str("node_id", node.NodeID).
        Str("name", node.Name).
        Msg("node added successfully")

    return nil
}

// RemoveNode 删除节点
func (m *Manager) RemoveNode(ctx context.Context, nodeID string) error {
    if err := m.db.DeleteNode(nodeID); err != nil {
        return fmt.Errorf("failed to delete node: %w", err)
    }

    m.logger.Info().
        Str("node_id", nodeID).
        Msg("node removed successfully")

    return nil
}

// checkNodeHealth 检查节点健康状态
func (m *Manager) checkNodeHealth(ctx context.Context, node *models.Node) error {
    req, err := http.NewRequestWithContext(ctx, "GET", node.TrafficAPIURL, nil)
    if err != nil {
        return err
    }

    req.Header.Set("Authorization", node.Secret)

    resp, err := m.client.Do(req)
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("unexpected status code: %d", resp.StatusCode)
    }

    return nil
}

// HealthCheckAll 检查所有节点健康状态
func (m *Manager) HealthCheckAll(ctx context.Context) error {
    nodes, err := m.db.GetAllNodes()
    if err != nil {
        return err
    }

    for _, node := range nodes {
        if err := m.checkNodeHealth(ctx, &node); err != nil {
            m.logger.Warn().
                Str("node_id", node.NodeID).
                Err(err).
                Msg("node health check failed")
        } else {
            m.db.UpdateNodeLastSeen(node.NodeID)
        }
    }

    return nil
}
```

## 交付物

### 代码文件
- [ ] `internal/node/manager.go` - 节点管理器
- [ ] `internal/node/health.go` - 健康检查

### 测试
- [ ] `internal/node/manager_test.go` - 单元测试

### 文档
- [ ] `internal/node/README.md` - 使用文档

## 验收标准

### 功能验收
- [ ] 可以动态添加节点
- [ ] 可以删除节点
- [ ] 健康检查正常工作
- [ ] 节点状态正确更新

### 性能验收
- [ ] 健康检查 < 5 秒

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-005)
