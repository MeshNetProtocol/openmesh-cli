# TASK-009: 端到端集成测试

## 任务信息

- **任务编号**: TASK-009
- **所属阶段**: Phase 1 - Week 2 (Day 8-9)
- **预计时间**: 2 天
- **依赖任务**: TASK-007, TASK-008
- **状态**: 待开始

## 任务目标

编写端到端集成测试,验证 Metering Service 与 Hysteria2 节点、认证 API 的完整集成,包括性能测试和故障恢复测试。

## 工作范围

### 1. 集成测试框架

创建 `tests/integration/` 目录:

```
tests/
├── integration/
│   ├── setup.go              # 测试环境设置
│   ├── teardown.go           # 测试清理
│   ├── e2e_test.go           # 端到端测试
│   ├── performance_test.go   # 性能测试
│   ├── failover_test.go      # 故障恢复测试
│   └── docker-compose.test.yaml
```

### 2. 端到端测试场景

**测试场景 1: 完整流量计费流程**
```go
func TestE2ETrafficMetering(t *testing.T) {
    // 1. 启动测试环境
    // 2. 创建用户和节点
    // 3. 模拟流量
    // 4. 验证流量统计
    // 5. 验证配额扣减
}
```

**测试场景 2: 超额封禁流程**
```go
func TestE2EQuotaExceeded(t *testing.T) {
    // 1. 创建用户(小配额)
    // 2. 产生超额流量
    // 3. 验证用户被封禁
    // 4. 验证无法重连
}
```

**测试场景 3: 多节点流量汇总**
```go
func TestE2EMultiNodeAggregation(t *testing.T) {
    // 1. 启动多个节点
    // 2. 用户连接到不同节点
    // 3. 验证流量正确汇总
}
```

### 3. 性能测试

```go
func TestPerformanceConcurrentUsers(t *testing.T) {
    // 测试 10 个并发用户
    // 验证采集成功率 > 99%
    // 验证 API 响应时间 < 100ms
}

func TestPerformanceMultipleNodes(t *testing.T) {
    // 测试 5 个节点并发采集
    // 验证采集延迟 < 1 秒
}
```

### 4. 故障恢复测试

```go
func TestFailoverNodeFailure(t *testing.T) {
    // 1. 模拟节点故障
    // 2. 验证其他节点不受影响
    // 3. 验证节点恢复后自动重新启用
}

func TestFailoverDatabaseRestart(t *testing.T) {
    // 1. 重启数据库
    // 2. 验证服务自动恢复
    // 3. 验证无数据丢失
}
```

### 5. Docker Compose 测试环境

创建 `tests/integration/docker-compose.test.yaml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_pass
      POSTGRES_DB: metering_test
    ports:
      - "5432:5432"

  metering:
    build: ../../
    depends_on:
      - postgres
    environment:
      METERING_DATABASE_HOST: postgres
      METERING_DATABASE_PORT: 5432
      METERING_DATABASE_NAME: metering_test
      METERING_DATABASE_USER: test_user
      METERING_DATABASE_PASSWORD: test_pass
    ports:
      - "8090:8090"

  hysteria-node-1:
    image: hysteria2:latest
    ports:
      - "8081:8081"

  hysteria-node-2:
    image: hysteria2:latest
    ports:
      - "8082:8082"

  auth-api:
    image: auth-api:latest
    ports:
      - "8080:8080"
```

## 交付物

### 代码文件
- [ ] `tests/integration/setup.go` - 测试环境设置
- [ ] `tests/integration/e2e_test.go` - 端到端测试
- [ ] `tests/integration/performance_test.go` - 性能测试
- [ ] `tests/integration/failover_test.go` - 故障恢复测试
- [ ] `tests/integration/docker-compose.test.yaml` - 测试环境配置

### 脚本
- [ ] `tests/run_integration_tests.sh` - 集成测试运行脚本

### 文档
- [ ] `tests/integration/README.md` - 测试说明文档

## 验收标准

### 功能验收
- [ ] 所有端到端测试通过
- [ ] 性能测试达标
- [ ] 故障恢复测试通过

### 性能验收
- [ ] 采集成功率 > 99%
- [ ] API 响应时间 < 100ms (P95)
- [ ] 支持 10 个并发用户
- [ ] 支持 5 个节点

### 可靠性验收
- [ ] 节点故障不影响其他节点
- [ ] 数据库重启后自动恢复
- [ ] 无数据丢失

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-009)
