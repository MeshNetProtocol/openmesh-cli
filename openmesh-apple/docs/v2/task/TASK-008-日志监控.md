# TASK-008: 日志和监控集成

## 任务信息

- **任务编号**: TASK-008
- **所属阶段**: Phase 1 - Week 1 (Day 7)
- **预计时间**: 1 天
- **依赖任务**: TASK-003, TASK-004
- **状态**: 待开始

## 任务目标

集成结构化日志系统和 Prometheus 监控指标,实现完整的可观测性。

## 工作范围

### 1. 结构化日志

使用 `zerolog` 实现结构化日志:

```go
package logger

import (
    "os"
    "github.com/rs/zerolog"
    "github.com/rs/zerolog/log"
)

// Setup 初始化日志系统
func Setup(level, format string) zerolog.Logger {
    zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

    var logger zerolog.Logger

    if format == "text" {
        logger = log.Output(zerolog.ConsoleWriter{Out: os.Stdout})
    } else {
        logger = zerolog.New(os.Stdout).With().Timestamp().Logger()
    }

    // 设置日志级别
    switch level {
    case "debug":
        zerolog.SetGlobalLevel(zerolog.DebugLevel)
    case "info":
        zerolog.SetGlobalLevel(zerolog.InfoLevel)
    case "warn":
        zerolog.SetGlobalLevel(zerolog.WarnLevel)
    case "error":
        zerolog.SetGlobalLevel(zerolog.ErrorLevel)
    default:
        zerolog.SetGlobalLevel(zerolog.InfoLevel)
    }

    return logger
}
```

### 2. Prometheus 监控

创建 `internal/metrics/metrics.go`:

```go
package metrics

import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
)

var (
    // 采集指标
    CollectionTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "metering_collection_total",
            Help: "Total number of traffic collections",
        },
        []string{"status"}, // success, failure
    )

    CollectionDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "metering_collection_duration_seconds",
            Help:    "Duration of traffic collection",
            Buckets: prometheus.DefBuckets,
        },
        []string{"node_id"},
    )

    // 配额指标
    QuotaChecksTotal = promauto.NewCounter(
        prometheus.CounterOpts{
            Name: "metering_quota_checks_total",
            Help: "Total number of quota checks",
        },
    )

    QuotaExceededTotal = promauto.NewCounter(
        prometheus.CounterOpts{
            Name: "metering_quota_exceeded_total",
            Help: "Total number of users exceeding quota",
        },
    )

    // API 指标
    APIRequestsTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "metering_api_requests_total",
            Help: "Total number of API requests",
        },
        []string{"method", "path", "status"},
    )

    APIRequestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "metering_api_request_duration_seconds",
            Help:    "Duration of API requests",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "path"},
    )

    // 用户指标
    ActiveUsers = promauto.NewGauge(
        prometheus.GaugeOpts{
            Name: "metering_active_users",
            Help: "Number of active users",
        },
    )

    BlockedUsers = promauto.NewGauge(
        prometheus.GaugeOpts{
            Name: "metering_blocked_users",
            Help: "Number of blocked users",
        },
    )
)
```

### 3. 监控端点

在 API 服务器中添加 Prometheus 端点:

```go
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

func (s *Server) setupRoutes() {
    // Prometheus metrics
    s.router.GET("/metrics", gin.WrapH(promhttp.Handler()))

    // 其他路由...
}
```

## 交付物

### 代码文件
- [ ] `internal/logger/logger.go` - 日志系统
- [ ] `internal/metrics/metrics.go` - Prometheus 指标
- [ ] `internal/metrics/middleware.go` - 指标中间件

### 文档
- [ ] `docs/monitoring.md` - 监控配置指南

## 验收标准

### 功能验收
- [ ] 结构化日志正常输出
- [ ] Prometheus 指标正确导出
- [ ] 日志级别可配置

### 监控验收
- [ ] 所有关键指标都有记录
- [ ] Grafana 可以查询指标

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-008)
