# TASK-004: 配额管理器升级

## 任务信息

- **任务编号**: TASK-004
- **所属阶段**: Phase 1 - Week 1 (Day 3-4)
- **预计时间**: 1.5 天
- **依赖任务**: TASK-001, TASK-002
- **状态**: 待开始

## 任务目标

将 Phase 0 原型的配额管理器升级为生产级实现,实现原子性配额扣减、配额查询功能、超额自动封禁逻辑。

## 技术背景

### Phase 0 原型情况

**原型代码**: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/quota.go` (165 行)

**核心功能**:
1. 检查用户配额是否超额
2. 超额后调用认证 API 标记用户为 blocked
3. 从所有节点踢出超额用户
4. 更新数据库中的用户状态

**原型的局限性**:
- 简单的错误处理
- 无配额查询 API
- 硬编码的认证 API URL
- 简单的日志输出

## 工作范围

### 1. 升级配额管理器结构

创建 `internal/quota/checker.go`:

```go
package quota

import (
    "context"
    "fmt"
    "net/http"
    "time"

    "github.com/openmesh/metering-service/internal/config"
    "github.com/openmesh/metering-service/internal/database"
    "github.com/openmesh/metering-service/pkg/models"
    "github.com/rs/zerolog"
)

// Checker 配额检查器
type Checker struct {
    db         *database.Database
    cfg        *config.AuthAPIConfig
    logger     zerolog.Logger
    client     *http.Client
}

// NewChecker 创建配额检查器
func NewChecker(db *database.Database, cfg *config.AuthAPIConfig, logger zerolog.Logger) *Checker {
    return &Checker{
        db:     db,
        cfg:    cfg,
        logger: logger,
        client: &http.Client{Timeout: cfg.Timeout},
    }
}
```

### 2. 实现配额检查逻辑

```go
// CheckAll 检查所有活跃用户的配额
func (c *Checker) CheckAll(ctx context.Context) error {
    users, err := c.db.GetAllUsers()
    if err != nil {
        return fmt.Errorf("failed to get users: %w", err)
    }

    for _, user := range users {
        if user.Status != "active" {
            continue
        }

        if err := c.CheckAndEnforce(ctx, user.UserID); err != nil {
            c.logger.Error().
                Str("user_id", user.UserID).
                Err(err).
                Msg("failed to check quota")
        }
    }

    return nil
}

// CheckAndEnforce 检查单个用户配额并执行封禁
func (c *Checker) CheckAndEnforce(ctx context.Context, userID string) error {
    user, err := c.db.GetUser(userID)
    if err != nil {
        return fmt.Errorf("failed to get user: %w", err)
    }

    if user.Used <= user.Quota {
        return nil // 未超额
    }

    c.logger.Warn().
        Str("user_id", userID).
        Int64("used", user.Used).
        Int64("quota", user.Quota).
        Msg("user exceeded quota")

    // 执行封禁流程
    return c.blockUser(ctx, userID)
}
```

### 3. 实现封禁流程

```go
// blockUser 封禁超额用户
func (c *Checker) blockUser(ctx context.Context, userID string) error {
    // 1. 标记用户为 blocked (认证 API)
    if err := c.setUserStatus(ctx, userID, "blocked"); err != nil {
        return fmt.Errorf("failed to set user status: %w", err)
    }
    c.logger.Info().Str("user_id", userID).Msg("marked user as blocked in auth API")

    // 2. 从所有节点踢出用户
    nodes, err := c.db.GetNodes()
    if err != nil {
        return fmt.Errorf("failed to get nodes: %w", err)
    }

    for _, node := range nodes {
        if err := c.kickUser(ctx, node, userID); err != nil {
            c.logger.Error().
                Str("user_id", userID).
                Str("node_id", node.NodeID).
                Err(err).
                Msg("failed to kick user from node")
        } else {
            c.logger.Info().
                Str("user_id", userID).
                Str("node_id", node.NodeID).
                Msg("kicked user from node")
        }
    }

    // 3. 更新数据库状态
    if err := c.db.UpdateUserStatus(userID, "blocked"); err != nil {
        return fmt.Errorf("failed to update user status in database: %w", err)
    }

    c.logger.Info().Str("user_id", userID).Msg("user blocked successfully")
    return nil
}
```

### 4. 实现配额查询功能

创建 `internal/quota/query.go`:

```go
package quota

import (
    "fmt"
    "github.com/openmesh/metering-service/pkg/models"
)

// QuotaInfo 配额信息
type QuotaInfo struct {
    UserID     string `json:"user_id"`
    TotalQuota int64  `json:"total_quota"`
    Used       int64  `json:"used"`
    Remaining  int64  `json:"remaining"`
    Status     string `json:"status"`
    UsagePercent float64 `json:"usage_percent"`
}

// GetQuota 获取用户配额信息
func (c *Checker) GetQuota(userID string) (*QuotaInfo, error) {
    user, err := c.db.GetUser(userID)
    if err != nil {
        return nil, fmt.Errorf("failed to get user: %w", err)
    }

    remaining := user.Quota - user.Used
    if remaining < 0 {
        remaining = 0
    }

    usagePercent := 0.0
    if user.Quota > 0 {
        usagePercent = float64(user.Used) / float64(user.Quota) * 100
    }

    return &QuotaInfo{
        UserID:       user.UserID,
        TotalQuota:   user.Quota,
        Used:         user.Used,
        Remaining:    remaining,
        Status:       user.Status,
        UsagePercent: usagePercent,
    }, nil
}
```

## 技术约束

1. **原子性**: 配额扣减必须是原子性的,避免并发问题
2. **保持 API 兼容**: 与 Phase 0 原型的认证 API 保持兼容
3. **性能要求**: 配额查询 < 50ms

## 依赖

### 内部依赖
- TASK-001: 数据库层实现
- TASK-002: 配置管理系统

### 参考资料
- Phase 0 原型: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/quota.go`

## 交付物

### 代码文件
- [ ] `internal/quota/checker.go` - 配额检查器
- [ ] `internal/quota/query.go` - 配额查询
- [ ] `internal/quota/enforce.go` - 封禁执行

### 测试
- [ ] `internal/quota/checker_test.go` - 单元测试

### 文档
- [ ] `internal/quota/README.md` - 使用文档

## 验收标准

### 功能验收
- [ ] 配额检查正常工作
- [ ] 超额自动封禁
- [ ] 配额查询准确
- [ ] 原子性保证

### 性能验收
- [ ] 配额查询 < 50ms
- [ ] 支持并发检查

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-004)
