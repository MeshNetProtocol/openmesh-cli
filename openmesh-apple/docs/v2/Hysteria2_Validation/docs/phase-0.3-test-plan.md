# Phase 0.3 流量控制与超额处理验证 - 测试计划

**日期**: 2026-03-24
**状态**: 📋 计划中

---

## 一、测试目标

验证 Hysteria2 的流量控制和超额处理机制，确保超额用户能够被正确阻止。

### 核心验收标准

| 验收项 | 目标 | 状态 |
|--------|------|------|
| 认证拒绝机制 | 返回 `{ok: false}` 时客户端无法连接 | ⬜️ 待验证 |
| `/kick` API 功能 | 能断开在线用户连接 | ⬜️ 待验证 |
| 完整超额流程 | 标记 + kick + 拒绝重连的闭环 | ⬜️ 待验证 |
| 多设备场景 | 流量合并统计和封禁策略 | ⬜️ 待验证 |

---

## 二、测试计划

### 测试 1: 认证拒绝机制验证

**目标**: 验证认证 API 返回 `{ok: false}` 时，客户端无法建立连接

**前置条件**:
- Hysteria2 服务端运行中
- 认证 API 运行中
- sing-box 客户端配置正确

**测试步骤**:
1. 修改认证 API，对特定 token 返回 `{ok: false}`
2. 配置 sing-box 使用被拒绝的 token
3. 启动 sing-box 客户端
4. 观察连接状态和日志

**预期结果**:
- sing-box 无法建立连接
- Hysteria2 服务端日志显示认证失败
- 客户端持续重试但始终失败

**验证方法**:
```bash
# 1. 修改认证 API 拒绝 user_blocked
# 2. 测试连接
curl -x socks5://127.0.0.1:10800 https://www.baidu.com
# 预期: 连接失败

# 3. 检查日志
tail -f logs/hysteria2-server.log
tail -f logs/sing-box-client.log
```

**产出**:
- 认证拒绝测试脚本
- 测试日志截图
- 测试结果记录

---

### 测试 2: `/kick` API 功能验证

**目标**: 验证 `/kick` API 能够断开在线用户的连接

**前置条件**:
- 用户已成功连接并在线
- 可以访问 Traffic Stats API

**测试步骤**:
1. 用户正常连接并使用（下载文件）
2. 查询 `/online` 确认用户在线
3. 调用 `POST /kick` 踢出用户
4. 观察连接状态变化
5. 检查用户是否自动重连

**预期结果**:
- `/kick` 调用成功返回
- 用户连接立即断开
- 客户端自动尝试重连
- 重连成功（因为认证仍然通过）

**验证方法**:
```bash
# 1. 确认用户在线
curl -s http://127.0.0.1:8081/online \
  -H "Authorization: test_secret_key_12345" | jq .

# 2. 踢出用户
curl -X POST http://127.0.0.1:8081/kick \
  -H "Authorization: test_secret_key_12345" \
  -H "Content-Type: application/json" \
  -d '["user_001"]'

# 3. 观察客户端日志
tail -f logs/sing-box-client.log

# 4. 再次检查在线状态
curl -s http://127.0.0.1:8081/online \
  -H "Authorization: test_secret_key_12345" | jq .
```

**产出**:
- `/kick` API 测试脚本
- 连接断开和重连的日志
- 测试结果记录

---

### 测试 3: 完整超额处理流程验证（核心）

**目标**: 验证完整的超额处理闭环：检测超额 → 标记 → 踢出 → 拒绝重连

**前置条件**:
- 认证 API 支持状态检查
- 可以模拟用户超额场景

**测试步骤**:

**阶段 1: 正常使用**
1. 用户正常连接并使用
2. 下载文件，累积流量
3. 验证流量统计正常

**阶段 2: 超额检测**
4. 模拟后端检测到用户超额
5. 在认证 API 中标记用户状态为 "blocked"

**阶段 3: 踢出连接**
6. 调用 `POST /kick` 断开用户连接
7. 验证连接已断开

**阶段 4: 拒绝重连**
8. 客户端自动重连
9. 认证 API 检查状态，返回 `{ok: false}`
10. 验证客户端无法重连

**预期结果**:
- 用户在超额前可以正常使用
- 超额后连接被断开
- 重连时认证失败
- 用户无法继续使用服务

**验证方法**:
```bash
# 完整流程测试脚本
./tests/phase-0.3-quota-control-test.sh
```

**产出**:
- 完整流程测试脚本
- 各阶段的日志和截图
- 流量统计数据
- 测试结果报告

---

### 测试 4: 多设备场景验证

**目标**: 验证同一用户多设备的流量统计和封禁策略

**测试场景**:

**场景 A: 相同 user_id（流量合并）**
1. 两个设备使用相同 token
2. 认证返回相同 `user_id`
3. 验证流量是否合并统计
4. 封禁一个设备，观察另一个设备

**场景 B: 不同 user_id（流量分离）**
1. 两个设备使用不同 token
2. 认证返回不同 `user_id`（如 `user_001_device_A`）
3. 验证流量是否分别统计
4. 封禁一个设备，观察另一个设备

**预期结果**:

**场景 A**:
- 两个设备的流量合并到同一个 `user_id`
- 封禁后两个设备都无法连接

**场景 B**:
- 两个设备的流量分别统计
- 封禁一个设备不影响另一个

**验证方法**:
```bash
# 场景 A: 相同 user_id
# 1. 启动两个客户端，使用相同 token
# 2. 分别下载文件
# 3. 检查流量统计
curl -s http://127.0.0.1:8081/traffic \
  -H "Authorization: test_secret_key_12345" | jq .

# 场景 B: 不同 user_id
# 1. 修改认证 API，根据 token 返回不同 user_id
# 2. 启动两个客户端，使用不同 token
# 3. 分别下载文件
# 4. 检查流量统计
```

**产出**:
- 多设备测试脚本
- 两种场景的测试数据
- 流量统计对比
- 测试结果分析

---

## 三、测试环境

### 服务端
- Hysteria2 服务端: v2.7.1
- 认证 API: 运行在 127.0.0.1:8080
- Traffic Stats API: 运行在 127.0.0.1:8081

### 客户端
- sing-box: v1.13.3
- 代理端口: 127.0.0.1:10800
- 配置文件: `config/sing-box-client.json`

### 测试工具
- curl: 用于 HTTP 请求
- jq: 用于 JSON 解析
- tail: 用于日志监控

---

## 四、实施顺序

### Day 1 上午: 测试 1 + 测试 2
1. 实现认证拒绝逻辑
2. 编写测试 1 脚本并执行
3. 编写测试 2 脚本并执行
4. 记录测试结果

### Day 1 下午: 测试 3
1. 实现完整的超额处理逻辑
2. 编写完整流程测试脚本
3. 执行测试并记录结果
4. 分析和验证

### Day 2 上午: 测试 4
1. 实现多设备场景支持
2. 编写多设备测试脚本
3. 执行两种场景测试
4. 对比和分析结果

### Day 2 下午: 总结
1. 整理所有测试结果
2. 编写 Phase 0.3 测试报告
3. 更新 README.md 进度
4. 准备进入 Phase 0.4

---

## 五、关键技术点

### 1. 认证 API 状态管理

需要在认证 API 中维护用户状态：

```go
// 用户状态
var userStatus = map[string]string{
    "user_001": "active",
    "user_002": "active",
    "user_blocked": "blocked",
}

// 认证处理
func authHandler(req AuthRequest) AuthResponse {
    status := userStatus[getUserID(req.Auth)]
    return AuthResponse{
        OK: status != "blocked",
        ID: getUserID(req.Auth),
    }
}
```

### 2. `/kick` API 调用

```bash
curl -X POST http://127.0.0.1:8081/kick \
  -H "Authorization: test_secret_key_12345" \
  -H "Content-Type: application/json" \
  -d '["user_001", "user_002"]'
```

### 3. 完整超额流程

```
1. 流量采集: GET /traffic?clear=true
2. 检查配额: if used > quota
3. 标记状态: userStatus[id] = "blocked"
4. 踢出连接: POST /kick [id]
5. 拒绝重连: 认证返回 {ok: false}
```

### 4. 多设备策略

**策略 A: 账号级配额（推荐）**
- 所有设备返回相同 `user_id`
- 流量合并统计
- 封禁影响所有设备

**策略 B: 设备级配额**
- 不同设备返回不同 `user_id`
- 流量分别统计
- 封禁只影响单个设备

---

## 六、风险与应对

| 风险 | 影响 | 应对方案 |
|------|------|---------|
| `/kick` 后客户端不重连 | 无法验证拒绝重连 | 检查 sing-box 配置，确保启用自动重连 |
| 认证拒绝后客户端仍能连接 | 核心功能失效 | 检查认证 API 逻辑，确保正确返回 `{ok: false}` |
| 多设备测试环境复杂 | 测试难度增加 | 使用不同端口运行多个 sing-box 实例 |
| 日志信息不足 | 难以定位问题 | 增加详细日志输出 |

---

## 七、产出清单

### 代码
- [ ] `prototype/auth-api.go` - 增强认证 API（状态管理）
- [ ] `tests/phase-0.3-test-1-auth-reject.sh` - 认证拒绝测试
- [ ] `tests/phase-0.3-test-2-kick-api.sh` - `/kick` API 测试
- [ ] `tests/phase-0.3-test-3-quota-control.sh` - 完整超额流程测试
- [ ] `tests/phase-0.3-test-4-multi-device.sh` - 多设备场景测试

### 文档
- [ ] `results/phase-0.3-test-1-results.md` - 测试 1 结果
- [ ] `results/phase-0.3-test-2-results.md` - 测试 2 结果
- [ ] `results/phase-0.3-test-3-results.md` - 测试 3 结果
- [ ] `results/phase-0.3-test-4-results.md` - 测试 4 结果
- [ ] `results/phase-0.3-final-report.md` - Phase 0.3 最终报告

### 数据
- [ ] 各测试的日志文件
- [ ] 流量统计数据
- [ ] 连接状态截图

---

## 八、成功标准

Phase 0.3 成功完成的标准：

1. ✅ 认证拒绝机制正常工作
2. ✅ `/kick` API 能断开连接
3. ✅ 客户端重连时被正确拒绝
4. ✅ 完整超额流程验证通过
5. ✅ 多设备场景处理正确
6. ✅ 所有测试脚本可重复执行
7. ✅ 测试报告完整清晰

---

**下一步**: 开始实施测试 1 - 认证拒绝机制验证
