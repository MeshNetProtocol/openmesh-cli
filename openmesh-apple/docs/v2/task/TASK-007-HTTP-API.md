# TASK-007: HTTP API 实现

## 任务信息

- **任务编号**: TASK-007
- **所属阶段**: Phase 1 - Week 1 (Day 6-7)
- **预计时间**: 2 天
- **依赖任务**: TASK-003, TASK-004, TASK-005, TASK-006
- **状态**: 待开始

## 任务目标

实现完整的 RESTful HTTP API,包括配额查询、流量统计查询、节点管理、用户管理和健康检查端点。

## 工作范围

### 1. API 路由设计

创建 `internal/api/router.go`:

```go
package api

import (
    "github.com/gin-gonic/gin"
    "github.com/openmesh/metering-service/internal/config"
    "github.com/openmesh/metering-service/internal/database"
    "github.com/rs/zerolog"
)

// Server HTTP API 服务器
type Server struct {
    router *gin.Engine
    cfg    *config.ServerConfig
    db     *database.Database
    logger zerolog.Logger
}

// NewServer 创建 API 服务器
func NewServer(cfg *config.ServerConfig, db *database.Database, logger zerolog.Logger) *Server {
    if cfg.LogLevel == "debug" {
        gin.SetMode(gin.DebugMode)
    } else {
        gin.SetMode(gin.ReleaseMode)
    }

    router := gin.New()
    router.Use(gin.Recovery())
    router.Use(LoggerMiddleware(logger))

    s := &Server{
        router: router,
        cfg:    cfg,
        db:     db,
        logger: logger,
    }

    s.setupRoutes()
    return s
}

// setupRoutes 设置路由
func (s *Server) setupRoutes() {
    // 健康检查
    s.router.GET("/health", s.handleHealth)

    // API v1
    v1 := s.router.Group("/api/v1")
    {
        // 配额查询 (公开)
        v1.GET("/quota/:user_id", s.handleGetQuota)

        // 流量统计查询 (公开)
        v1.GET("/traffic/:user_id", s.handleGetTraffic)

        // 管理 API (需要认证)
        admin := v1.Group("/admin")
        admin.Use(AuthMiddleware())
        {
            // 节点管理
            admin.POST("/nodes", s.handleCreateNode)
            admin.GET("/nodes", s.handleListNodes)
            admin.GET("/nodes/:node_id", s.handleGetNode)
            admin.PUT("/nodes/:node_id", s.handleUpdateNode)
            admin.DELETE("/nodes/:node_id", s.handleDeleteNode)

            // 用户管理
            admin.POST("/users", s.handleCreateUser)
            admin.GET("/users", s.handleListUsers)
            admin.GET("/users/:user_id", s.handleGetUser)
            admin.PUT("/users/:user_id/quota", s.handleUpdateQuota)
        }
    }
}
```

### 2. API 处理器实现

**配额查询 API**:
```go
// handleGetQuota 获取用户配额
func (s *Server) handleGetQuota(c *gin.Context) {
    userID := c.Param("user_id")

    quota, err := s.quotaChecker.GetQuota(userID)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
        return
    }

    c.JSON(http.StatusOK, quota)
}
```

**流量统计查询 API**:
```go
// handleGetTraffic 获取用户流量统计
func (s *Server) handleGetTraffic(c *gin.Context) {
    userID := c.Param("user_id")
    startTime := c.Query("start_time")
    endTime := c.Query("end_time")

    // 解析时间参数
    start, _ := time.Parse(time.RFC3339, startTime)
    end, _ := time.Parse(time.RFC3339, endTime)

    stats, err := s.userManager.GetTrafficStats(c.Request.Context(), userID, start, end)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, stats)
}
```

**节点管理 API**:
```go
// handleCreateNode 创建节点
func (s *Server) handleCreateNode(c *gin.Context) {
    var req struct {
        Name        string `json:"name" binding:"required"`
        StatsURL    string `json:"stats_url" binding:"required,url"`
        StatsSecret string `json:"stats_secret" binding:"required"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    node := &models.Node{
        NodeID:        generateNodeID(),
        Name:          req.Name,
        TrafficAPIURL: req.StatsURL,
        Secret:        req.StatsSecret,
        Enabled:       true,
    }

    if err := s.nodeManager.AddNode(c.Request.Context(), node); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, node)
}
```

### 3. 中间件实现

创建 `internal/api/middleware.go`:

```go
// LoggerMiddleware 日志中间件
func LoggerMiddleware(logger zerolog.Logger) gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        path := c.Request.URL.Path

        c.Next()

        logger.Info().
            Str("method", c.Request.Method).
            Str("path", path).
            Int("status", c.Writer.Status()).
            Dur("latency", time.Since(start)).
            Msg("http request")
    }
}

// AuthMiddleware 认证中间件
func AuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if token == "" {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "missing authorization"})
            c.Abort()
            return
        }

        // 验证 token (简化版本,生产环境需要更复杂的验证)
        if !isValidToken(token) {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
            c.Abort()
            return
        }

        c.Next()
    }
}
```

## 交付物

### 代码文件
- [ ] `internal/api/server.go` - API 服务器
- [ ] `internal/api/router.go` - 路由设置
- [ ] `internal/api/handlers.go` - 请求处理器
- [ ] `internal/api/middleware.go` - 中间件
- [ ] `internal/api/response.go` - 响应格式

### 测试
- [ ] `internal/api/handlers_test.go` - API 测试

### 文档
- [ ] `docs/api.md` - API 文档 (OpenAPI 格式)

## 验收标准

### 功能验收
- [ ] 所有 API 端点正常工作
- [ ] 请求验证正确
- [ ] 错误处理完善
- [ ] 认证中间件工作

### 性能验收
- [ ] API 响应时间 < 100ms (P95)
- [ ] 支持并发请求

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-007)
