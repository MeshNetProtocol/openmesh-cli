# Hysteria2 技术验证计划

> **目标**: 验证 Hysteria2 协议的用户级流量统计能力，确认其能够满足 OpenMesh V2 的多用户多服务器流量统计需求。

**验证周期**: 3-5 天
**当前状态**: 🟡 准备中
**最后更新**: 2026-03-24

---

## 源码分析结论

**基于 Hysteria2 源码分析（`/Users/wesley/MeshNetProtocol/openmesh-cli/hysteria`）**：

✅ **不需要修改 Hysteria2 源码**，原生功能完全满足需求：

1. **用户识别**：`extras/auth/http.go` 提供 HTTP 认证，返回唯一 `user_id`
2. **流量统计**：`extras/trafficlogger/http.go` 提供完整的 Traffic Stats API
3. **流量控制**：`LogTraffic` 返回 `false` 可断开连接
4. **HTTP API**：`/traffic`, `/online`, `/kick` 端点开箱即用

**关键理解**（基于源码 `core/server/server.go:148`）：
- 认证接口 `Authenticate(addr, auth, tx)` 的 `tx` 参数是**客户端带宽速率**（bytes/sec），不是累计流量
- 流量统计必须通过 `/traffic` API 获取，认证时无法获取已用流量
- 超额处理需要：数据库标记 + `/kick` 断开 + 认证拒绝重连

---

## 一、验证目标

### 核心验收标准

| 验收项 | 目标 | 状态 |
|--------|------|------|
| HTTP Auth API 集成 | 认证返回 user_id | ⬜️ 待验证 |
| Traffic Stats API 可用性 | API 返回用户级流量数据 | ⬜️ 待验证 |
| 流量统计准确度 | 误差 < 1% | ⬜️ 待验证 |
| 流量控制机制 | 超额用户可被阻止 | ⬜️ 待验证 |
| 多节点流量汇总 | 无重复计数，数据一致 | ⬜️ 待验证 |
| 并发用户支持 | 支持 10+ 并发用户 | ⬜️ 待验证 |

**关键决策点**: 如果任一核心验收标准未达标，需回滚到其他方案。

---

## 二、架构设计（基于源码分析）

### 整体架构

```
客户端 (MeshFluxMac)
  ↓ sing-box (TUN + Hysteria2 outbound)
  ↓ QUIC
服务端 (Hysteria2 Server)
  ↓ HTTP Auth API
  ↓ Traffic Stats API
后端 (OpenMesh Backend - Go)
  ↓ PostgreSQL
```

### 关键接口（基于源码）

**1. 认证接口** (`extras/auth/http.go:79`)
```go
// Hysteria2 调用我们的认证 API
POST /api/v1/hysteria/auth
Request:  {addr: string, auth: string, tx: uint64}
Response: {ok: bool, id: string}

// 注意：tx 是客户端带宽速率（bytes/sec），不是累计流量
```

**2. 流量统计接口** (`extras/trafficlogger/http.go`)
```go
// 获取用户流量统计
GET /traffic
Response: {"user_id": {"tx": uint64, "rx": uint64}}

// 获取并清零（用于增量采集）
GET /traffic?clear=true

// 在线用户
GET /online
Response: {"user_id": device_count}

// 踢出用户
POST /kick
Request: ["user_id1", "user_id2"]
```

**3. 流量记录接口** (`core/server/config.go:227`)
```go
// Hysteria2 每次流量变化都会调用
LogTraffic(id string, tx, rx uint64) (ok bool)
// 返回 false 可断开连接
```

### 超额处理流程

```
1. 定时采集（每 10 秒）
   GET /traffic?clear=true → 获取增量流量

2. 数据库累加
   UPDATE users SET used = used + increment

3. 检查配额
   IF used > quota THEN
     - 数据库标记：status = 'blocked'
     - 踢出连接：POST /kick ["user_id"]

4. 用户重连
   认证 API 检查 status
   IF status = 'blocked' THEN
     返回 {ok: false}  // 拒绝重连
```

---

## 三、验证阶段

### Phase 0.1: 环境搭建 (1天)

**目标**: 搭建基础的 Hysteria2 测试环境

**任务清单**:
- [ ] 安装 Hysteria2 服务端（Docker 或二进制）
- [ ] 实现简单的 HTTP 认证 API（Go）
  - 接收 `{addr, auth, tx}` 参数
  - 验证 token，返回 `{ok, id}`
  - 注意：`tx` 是带宽速率，不是累计流量
- [ ] 配置 Hysteria2 启用 Traffic Stats API
- [ ] 配置 sing-box 客户端连接
- [ ] 验证认证流程和流量统计 API

**产出**:
- `config/hysteria2-server.yaml` - 服务端配置文件
- `config/sing-box-client.json` - 客户端配置文件
- `prototype/auth-api.go` - 简单认证 API 实现
- `docs/setup-guide.md` - 环境搭建文档

**验收标准**:
- ✅ Hysteria2 服务端成功启动
- ✅ 认证 API 正常工作（返回正确的 user_id）
- ✅ Traffic Stats API 可访问（`GET /traffic` 返回 200）
- ✅ sing-box 客户端成功连接并通过认证
- ✅ `/traffic` API 能看到用户流量数据

---

### Phase 0.2: 单节点流量统计验证 (1天)

**目标**: 验证单个 Hysteria2 节点的流量统计准确性

**测试场景**:

1. **基础流量测试**
   - 用户 A 下载 100KB 文件
   - 用户 B 上传 100KB 文件
   - 用户 C 混合上传下载各 100KB

2. **准确度测试**
   - 使用 `curl` 下载已知大小文件（100KB, 256KB, 512KB）
   - 对比 Traffic Stats API 返回值与实际传输量
   - 计算误差率：`|统计值 - 实际值| / 实际值 * 100%`

3. **并发测试**
   - 3 个用户同时传输数据
   - 验证流量统计互不干扰
   - 验证总流量 = 各用户流量之和

4. **增量采集测试**（关键）
   - 调用 `GET /traffic?clear=true` 获取增量
   - 再次调用，验证计数器已清零
   - 验证增量累加逻辑正确

**产出**:
- `tests/single-node-test.sh` - 自动化测试脚本
- `results/single-node-results.md` - 测试结果报告
- `results/accuracy-data.csv` - 准确度测试数据

**验收标准**:
- ✅ 流量统计误差 < 1%
- ✅ 多用户流量统计互不干扰
- ✅ API 响应时间 < 100ms
- ✅ 上传和下载流量分别统计准确
- ✅ `?clear=true` 参数正确清零计数器

---

### Phase 0.3: 流量控制与超额处理验证 (1天)

**目标**: 验证超额用户的阻止机制

**测试场景**:

1. **认证拒绝测试**
   - 模拟用户超额场景
   - 认证 API 返回 `{ok: false}`
   - 验证客户端无法连接

2. **`/kick` API 测试**
   - 用户在线时调用 `/kick`
   - 验证连接立即断开
   - 验证客户端自动重连

3. **完整超额流程测试**（关键）
   ```
   1. 用户正常连接并使用
   2. 后端检测到超额
   3. 数据库标记 status='blocked'
   4. 调用 POST /kick ["user_id"]
   5. 用户重连时认证返回 {ok: false}
   6. 验证用户无法继续使用
   ```

4. **多设备场景测试**
   - 同一用户的不同设备使用不同 token
   - 验证流量是否合并统计
   - 测试单设备封禁 vs 全用户封禁

**产出**:
- `tests/quota-control-test.sh` - 配额控制测试脚本
- `prototype/quota-checker.go` - 配额检查原型
- `results/quota-control-results.md` - 测试结果

**验收标准**:
- ✅ 认证拒绝机制正常工作
- ✅ `/kick` API 能断开连接
- ✅ 客户端重连时被正确拒绝
- ✅ 多设备场景处理正确

---

### Phase 0.4: 多节点流量汇总验证 (1天)

**目标**: 验证多节点场景下的流量汇总逻辑

**测试场景**:

1. **多节点部署**
   - 部署 2 个 Hysteria2 节点（Node A, Node B）
   - 配置相同的认证 API
   - 验证两个节点独立运行

2. **流量汇总测试**
   - 用户 A 在 Node A 下载 256KB
   - 用户 A 切换到 Node B 下载 256KB
   - 后端汇总：总流量 = 512KB
   - 验证各节点独立统计正确

3. **并发采集测试**
   - 后端同时拉取两个节点的 `/traffic?clear=true`
   - 验证增量累加逻辑
   - 验证无重复计数

**产出**:
- `config/node-a.yaml`, `config/node-b.yaml` - 多节点配置
- `tests/multi-node-test.sh` - 多节点测试脚本
- `prototype/traffic-collector.go` - 流量采集原型
- `results/multi-node-results.md` - 测试结果

**验收标准**:
- ✅ 多节点流量汇总准确（无重复计数）
- ✅ 并发采集无数据竞争
- ✅ 节点故障不影响其他节点统计

---

### Phase 0.5: Metering Service 原型验证 (1天)

**目标**: 实现完整的流量采集和计费原型

**核心功能**:
```go
// 定时任务（每 10 秒）
func collectTraffic() {
    // 1. 并发拉取所有节点
    for _, node := range nodes {
        go fetchTraffic(node)
    }

    // 2. 汇总增量
    for userID, traffic := range aggregated {
        db.IncrementTraffic(userID, traffic.Tx, traffic.Rx)

        // 3. 检查配额
        if db.GetUsed(userID) > db.GetQuota(userID) {
            db.SetStatus(userID, "blocked")
            kickUser(userID)
        }
    }
}

// 认证 API
func authHandler(req AuthRequest) AuthResponse {
    // 注意：req.Tx 是带宽速率，不是累计流量
    userID := validateToken(req.Auth)
    status := db.GetStatus(userID)

    return AuthResponse{
        OK: status != "blocked",
        ID: userID,
    }
}
```

**产出**:
- `prototype/metering-service.go` - 完整原型
- `prototype/auth-api.go` - 认证 API 实现
- `tests/integration-test.sh` - 集成测试
- `results/metering-results.md` - 测试结果
- `docs/implementation-guide.md` - 实现指南

**验收标准**:
- ✅ 定期拉取成功率 > 99%
- ✅ 增量计算准确（无重复扣减）
- ✅ 多节点汇总准确
- ✅ 超额用户被正确阻止
- ✅ 错误重试机制有效

---

## 四、测试环境规格

### 服务端配置
- **操作系统**: Ubuntu 22.04 LTS / macOS 14+
- **CPU**: 2 核
- **内存**: 4GB
- **网络**: 100Mbps
- **部署方式**: Docker（推荐）或二进制

### 客户端配置
- **操作系统**: macOS 14+
- **sing-box 版本**: 1.8.0+
- **测试工具**: curl, wget

### 测试数据文件
- 100KB 测试文件
- 256KB 测试文件
- 512KB 测试文件

---

## 五、关键技术问题（基于源码分析）

### 1. 认证参数理解

**问题**: `Authenticate(addr, auth, tx)` 的 `tx` 参数含义？

**源码证据** (`core/server/server.go:148`):
```go
authReq := protocol.AuthRequestFromHeader(r.Header)
actualTx := authReq.Rx  // 客户端的 Rx
ok, id := h.config.Authenticator.Authenticate(h.conn.RemoteAddr(), authReq.Auth, actualTx)
```

**结论**: `tx` 是**客户端带宽速率**（bytes/sec），用于拥塞控制，不是累计流量。

**影响**: 认证时无法获取用户已用流量，必须查询数据库或调用 `/traffic` API。

---

### 2. `/kick` API 的局限性

**问题**: 调用 `/kick` 后用户是否会重连？

**源码证据** (`extras/trafficlogger/http.go:285`):
```go
func (s *trafficStatsServerImpl) kick(w http.ResponseWriter, r *http.Request) {
    // 只是标记 KickMap，下次 LogTraffic 返回 false
    for _, id := range ids {
        s.KickMap[id] = struct{}{}
    }
}
```

**结论**: `/kick` 只断开当前连接，客户端会自动重连。

**解决方案**: 必须配合认证拒绝：
1. 数据库标记 `status='blocked'`
2. 调用 `/kick` 断开连接
3. 重连时认证 API 返回 `{ok: false}`

---

### 3. 多设备流量统计

**问题**: 同一用户的多个设备如何统计？

**源码证据** (`extras/trafficlogger/http.go:52`):
```go
func (s *trafficStatsServerImpl) LogTraffic(id string, tx, rx uint64) (ok bool) {
    entry, ok := s.StatsMap[id]
    if !ok {
        entry = &trafficStatsEntry{}
        s.StatsMap[id] = entry
    }
    entry.Tx += tx  // 按 id 累加
    entry.Rx += rx
}
```

**结论**: 相同 `id` 的流量会合并统计。

**解决方案**:
- 如需分设备计费：token 包含设备标识，认证返回 `user_123_device_A`
- 如需合并计费：所有设备使用相同 token，认证返回 `user_123`

---

## 六、风险与应对

### 主要风险

| 风险 | 可能性 | 影响 | 应对方案 |
|------|--------|------|---------|
| 认证参数理解错误 | 低 | 高 | 已通过源码分析确认 |
| `/kick` 无法阻止重连 | 低 | 高 | 配合认证拒绝机制 |
| 流量统计误差 > 1% | 中 | 高 | 分析误差来源，调整拉取频率 |
| 多节点汇总复杂度高 | 中 | 中 | 使用 `?clear=true` 增量采集 |
| 并发采集性能问题 | 低 | 中 | 优化并发策略，增加超时控制 |

### 回滚方案

**触发条件**:
- 流量统计误差 > 5%
- Traffic Stats API 可用性 < 95%
- 多节点汇总出现重复计数
- 无法解决的技术障碍

**回滚步骤**:
1. 停止 Hysteria2 验证
2. 评估其他协议方案
3. 更新技术选型文档
4. 重新制定实施计划

---

## 七、进度跟踪

### 当前进度

```
Phase 0.1: 环境搭建          ⬜️ 0%
Phase 0.2: 单节点验证        ⬜️ 0%
Phase 0.3: 流量控制验证      ⬜️ 0%
Phase 0.4: 多节点验证        ⬜️ 0%
Phase 0.5: Metering 原型     ⬜️ 0%
```

### 更新日志

| 日期 | 阶段 | 进展 | 备注 |
|------|------|------|------|
| 2026-03-24 | - | 完成源码分析 | 确认不需要修改 Hysteria2 源码 |
| 2026-03-24 | - | 更新验证计划 | 基于源码分析修正关键理解 |

---

## 八、下一步行动

**立即开始**: Phase 0.1 环境搭建

**关键问题需确认**:
1. 测试环境部署位置？（本地 macOS / 云服务器）
2. Hysteria2 安装方式？（推荐 Docker）
3. 是否需要 PostgreSQL？（Phase 0.5 需要）

**需要准备**:
- [ ] Hysteria2 官方文档
- [ ] sing-box 配置模板
- [ ] 测试数据文件（100KB, 256KB, 512KB）
- [ ] Go 开发环境（用于实现认证 API）

---

## 九、参考资料

### 官方文档
- [Hysteria2 官方文档](https://v2.hysteria.network/)
- [Hysteria2 Traffic Stats API](https://v2.hysteria.network/docs/advanced/Traffic-Stats-API/)
- [sing-box Hysteria2 配置](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)

### 源码分析
- `hysteria/extras/auth/http.go` - HTTP 认证实现
- `hysteria/extras/trafficlogger/http.go` - Traffic Stats API 实现
- `hysteria/core/server/config.go` - 核心接口定义
- `hysteria/core/server/server.go` - 认证调用逻辑

### 项目文档
- [OpenMesh V2 架构设计](../02-系统架构设计.md)
- [核心需求与技术选型](../01-核心需求与技术选型.md)
- [AI 工作准则](../PROMPT_FOR_NEW_AI.md)

---

## 十、文件组织

本目录将包含以下内容：

```
Hysteria2_Validation/
├── README.md                    # 本文档
├── config/                      # 配置文件
│   ├── hysteria2-server.yaml
│   ├── node-a.yaml
│   ├── node-b.yaml
│   └── sing-box-client.json
├── tests/                       # 测试脚本
│   ├── single-node-test.sh
│   ├── quota-control-test.sh
│   ├── multi-node-test.sh
│   └── integration-test.sh
├── prototype/                   # 原型代码
│   ├── auth-api.go
│   ├── traffic-collector.go
│   ├── quota-checker.go
│   └── metering-service.go
├── results/                     # 测试结果
│   ├── single-node-results.md
│   ├── quota-control-results.md
│   ├── multi-node-results.md
│   ├── metering-results.md
│   └── accuracy-data.csv
└── docs/                        # 文档
    ├── setup-guide.md
    ├── implementation-guide.md
    └── source-code-analysis.md
```

---

## 十一、核心结论

**基于 Hysteria2 源码深度分析和官方文档验证，我们得出以下结论**：

### ✅ 技术可行性

**无需修改 Hysteria2 源码，现有 HTTP Auth + Traffic Stats API 已足以实现按用户认证、按用户流量统计、在线查询、踢线和超额封禁；但配额执行是"周期采集 + 封禁/踢线"的控制模型，而不是逐字节实时裁决模型。**

具体能力：
1. **用户识别**：HTTP Auth 返回唯一 `user_id`（认证时的 `tx` 参数是带宽速率，不是累计流量）
2. **流量统计**：Traffic Stats API 按 `user_id` 聚合流量，通过 `/traffic?clear=true` 周期采集增量
3. **流量控制**：数据库标记 `blocked` + `/kick` 踢线 + 认证拒绝重连的完整闭环
4. **多节点支持**：各节点独立统计，后端周期采集并汇总
5. **在线管理**：`/online` 显示设备数，`/dump/streams` 显示活跃流

### ⚠️ 关键约束与注意事项

**1. 配额执行精度受采集周期限制**
- `/traffic?clear=true` 是周期拉取增量，不是实时裁决
- 采集周期 10 秒 = 允许约 10 秒窗口的超用漂移
- 不能做到"逐字节精确控制"

**2. 超额处理必须是双动作**
- ❌ 只调用 `/kick`：客户端会自动重连
- ✅ 正确流程：
  1. 数据库标记 `status='blocked'`
  2. 调用 `POST /kick` 断开现有连接
  3. 重连时认证 API 返回 `{ok: false}`

**3. 统计维度严格绑定到认证返回的 `id`**
- 相同 `id` 的流量会合并统计
- 多设备场景需要设计 `id` 策略：
  - 账号总配额：所有设备返回相同 `user_id`
  - 设备级明细：返回 `user_id:device_id` 或在后端另存一层

**4. 统计数据必须落库，不能依赖 Hysteria2 内存**
- `clear=true` 清零后数据只存在于你的数据库
- Hysteria2 重启后内存统计丢失
- 必须设计可靠的采集和持久化机制

**5. `/online` 和 `/dump/streams` 的语义**
- `/online`：当前在线的 Hysteria 客户端**设备实例数**（不是连接数）
- `/dump/streams`：当前活跃的 QUIC/TCP **流快照**（不是历史）

### 🎯 架构确认

```
sing-box 客户端 (不修改)
    ↓ Hysteria2 协议 (password = user_token)
Hysteria2 服务端 (不修改)
    ↓ HTTP Auth API + Traffic Stats API
OpenMesh Backend (我们实现)
    ↓ 周期采集 + 配额检查 + 封禁控制
PostgreSQL (持久化账本)
```

**我们只需要实现后端服务，无需修改任何开源代码。**

### 📋 实施约束（必须遵守）

1. **所有统计必须落库，不能把 Hysteria2 内存统计当持久账本**
   - `clear=true` 只是采集接口，不是账本
   - 必须设计采集失败的重试和补偿机制

2. **所有超额控制必须是双动作：数据库标记 + `/kick`**
   - 只做其中一个都不完整
   - 认证 API 必须检查数据库状态

3. **采集周期需要权衡精度和性能**
   - 周期越短，超用窗口越小，但服务器压力越大
   - 建议起始值：10 秒（可根据实际情况调整）

4. **错误处理和监控至关重要**
   - 采集失败会导致流量"黑洞"
   - 必须监控采集成功率、延迟、数据一致性

---

**文档维护**: 每完成一个阶段后更新进度和结果，记录关键发现和决策。
