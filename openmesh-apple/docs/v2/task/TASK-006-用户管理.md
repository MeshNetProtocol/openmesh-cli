# TASK-006: 用户管理功能

## 任务信息

- **任务编号**: TASK-006
- **所属阶段**: Phase 1 - Week 1 (Day 5)
- **预计时间**: 1 天
- **依赖任务**: TASK-001, TASK-002
- **状态**: 待开始

## 任务目标

实现用户管理功能,包括用户创建、配额设置、流量使用情况查询。

## 工作范围

### 1. 用户管理器

创建 `internal/user/manager.go`:

```go
package user

import (
    "context"
    "fmt"
    "time"

    "github.com/openmesh/metering-service/internal/database"
    "github.com/openmesh/metering-service/pkg/models"
    "github.com/rs/zerolog"
)

// Manager 用户管理器
type Manager struct {
    db     *database.Database
    logger zerolog.Logger
}

// NewManager 创建用户管理器
func NewManager(db *database.Database, logger zerolog.Logger) *Manager {
    return &Manager{
        db:     db,
        logger: logger,
    }
}

// CreateUser 创建用户
func (m *Manager) CreateUser(ctx context.Context, userID string, quota int64) error {
    if err := m.db.CreateUser(userID, quota); err != nil {
        return fmt.Errorf("failed to create user: %w", err)
    }

    m.logger.Info().
        Str("user_id", userID).
        Int64("quota", quota).
        Msg("user created successfully")

    return nil
}

// UpdateQuota 更新用户配额
func (m *Manager) UpdateQuota(ctx context.Context, userID string, quota int64) error {
    if err := m.db.UpdateUserQuota(userID, quota); err != nil {
        return fmt.Errorf("failed to update quota: %w", err)
    }

    m.logger.Info().
        Str("user_id", userID).
        Int64("quota", quota).
        Msg("quota updated successfully")

    return nil
}

// GetTrafficStats 获取用户流量统计
func (m *Manager) GetTrafficStats(ctx context.Context, userID string, startTime, endTime time.Time) (*TrafficStats, error) {
    logs, err := m.db.GetUserTrafficLogs(userID, startTime, endTime, 1000)
    if err != nil {
        return nil, fmt.Errorf("failed to get traffic logs: %w", err)
    }

    stats := &TrafficStats{
        UserID:    userID,
        StartTime: startTime,
        EndTime:   endTime,
        Logs:      logs,
    }

    // 计算总流量
    for _, log := range logs {
        stats.TotalTx += log.Tx
        stats.TotalRx += log.Rx
    }

    return stats, nil
}
```

## 交付物

### 代码文件
- [ ] `internal/user/manager.go` - 用户管理器
- [ ] `internal/user/stats.go` - 流量统计

### 测试
- [ ] `internal/user/manager_test.go` - 单元测试

### 文档
- [ ] `internal/user/README.md` - 使用文档

## 验收标准

### 功能验收
- [ ] 可以创建用户
- [ ] 可以更新配额
- [ ] 可以查询流量统计

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-006)
