# AC-007: HTTP API 验收

## 验收信息

- **验收编号**: AC-007
- **对应任务**: [TASK-007](TASK-007-HTTP-API.md)
- **验收人**: 验收 AI
- **状态**: 待验收

## 功能测试

### 测试 1: 配额查询 API
```bash
curl http://localhost:8090/api/v1/quota/user_001
```

**预期结果**:
- [ ] 返回正确的配额信息
- [ ] 响应格式符合规范

### 测试 2: 流量统计查询 API
```bash
curl "http://localhost:8090/api/v1/traffic/user_001?start_time=2026-03-26T00:00:00Z&end_time=2026-03-26T23:59:59Z"
```

**预期结果**:
- [ ] 返回流量统计数据
- [ ] 时间范围过滤正确

### 测试 3: 节点管理 API
```bash
# 创建节点
curl -X POST http://localhost:8090/api/v1/admin/nodes \
  -H "Authorization: Bearer admin_token" \
  -H "Content-Type: application/json" \
  -d '{"name":"test-node","stats_url":"http://localhost:8081","stats_secret":"secret"}'

# 列出节点
curl http://localhost:8090/api/v1/admin/nodes \
  -H "Authorization: Bearer admin_token"
```

**预期结果**:
- [ ] 可以创建节点
- [ ] 可以列出节点
- [ ] 认证中间件工作

### 测试 4: 用户管理 API
```bash
# 创建用户
curl -X POST http://localhost:8090/api/v1/admin/users \
  -H "Authorization: Bearer admin_token" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test_user","quota":1048576}'

# 更新配额
curl -X PUT http://localhost:8090/api/v1/admin/users/test_user/quota \
  -H "Authorization: Bearer admin_token" \
  -H "Content-Type: application/json" \
  -d '{"quota":2097152}'
```

**预期结果**:
- [ ] 可以创建用户
- [ ] 可以更新配额

### 测试 5: 健康检查
```bash
curl http://localhost:8090/health
```

**预期结果**:
- [ ] 返回 200 状态码
- [ ] 返回健康状态信息

## 性能测试

### 测试 6: API 响应时间
```bash
# 使用 ab 或 wrk 进行压测
ab -n 1000 -c 10 http://localhost:8090/api/v1/quota/user_001
```

**预期结果**:
- [ ] P95 响应时间 < 100ms
- [ ] 支持并发请求

## 验收标准

### 通过条件
- [ ] 所有 API 端点正常工作
- [ ] 认证中间件正确工作
- [ ] 错误处理完善
- [ ] 性能达标

### 失败条件
- [ ] 任何 API 测试失败
- [ ] 性能不达标
- [ ] 认证可以被绕过

---

**创建日期**: 2026-03-26
**对应任务**: TASK-007
