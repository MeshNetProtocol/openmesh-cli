# Phase 0.4 多节点流量汇总验证 - 测试计划

**日期**: 2026-03-24
**状态**: 📋 计划中

---

## 一、测试目标

验证多节点场景下的流量汇总逻辑，确保用户在不同节点间切换时流量统计准确无误。

### 核心验收标准

| 验收项 | 目标 | 状态 |
|--------|------|------|
| 多节点独立运行 | 两个节点同时运行互不干扰 | ⬜️ 待验证 |
| 跨节点流量汇总 | 用户在不同节点的流量正确累加 | ⬜️ 待验证 |
| 并发采集无重复 | 同时采集多节点不会重复计数 | ⬜️ 待验证 |
| 节点故障隔离 | 单节点故障不影响其他节点 | ⬜️ 待验证 |

---

## 二、测试架构

### 多节点部署方案

```
客户端 (sing-box)
    ↓
    ├─→ Node A (127.0.0.1:8443)
    │   ├─ Auth API: 127.0.0.1:8080 (共享)
    │   └─ Traffic Stats API: 127.0.0.1:8081
    │
    └─→ Node B (127.0.0.1:8444)
        ├─ Auth API: 127.0.0.1:8080 (共享)
        └─ Traffic Stats API: 127.0.0.1:8082
```

### 关键配置

**Node A** (现有节点):
- 服务端口: 8443
- Traffic Stats API: 127.0.0.1:8081

**Node B** (新增节点):
- 服务端口: 8444
- Traffic Stats API: 127.0.0.1:8082

**共享组件**:
- 认证 API: 127.0.0.1:8080 (两个节点共用)

---

## 三、测试计划

### 测试 1: 多节点独立运行验证

**目标**: 验证两个 Hysteria2 节点可以同时运行且互不干扰

**步骤**:
1. 启动 Node A (端口 8443)
2. 启动 Node B (端口 8444)
3. 验证两个节点都正常运行
4. 分别连接两个节点
5. 验证连接互不干扰

**预期结果**:
- 两个节点同时运行无冲突
- 客户端可以分别连接两个节点
- 认证 API 正确处理来自两个节点的请求

**验证方法**:
```bash
# 检查 Node A
curl -s http://127.0.0.1:8081/online -H "Authorization: test_secret_key_12345"

# 检查 Node B
curl -s http://127.0.0.1:8082/online -H "Authorization: test_secret_key_12345"
```

---

### 测试 2: 跨节点流量汇总验证

**目标**: 验证用户在不同节点使用时流量正确汇总

**测试场景**:

**场景 A: 用户在单个节点使用**
1. 用户连接 Node A
2. 下载 256KB 文件
3. 验证 Node A 流量统计
4. 验证 Node B 无此用户流量

**场景 B: 用户切换节点**
1. 用户先连接 Node A，下载 256KB
2. 用户切换到 Node B，下载 256KB
3. 采集两个节点的流量
4. 验证总流量 = Node A + Node B ≈ 512KB

**场景 C: 用户同时使用两个节点**
1. 启动两个客户端（相同 token）
2. 客户端 1 连接 Node A，下载文件
3. 客户端 2 连接 Node B，下载文件
4. 验证流量分别统计
5. 验证总流量 = 两个节点之和

**预期结果**:
- 每个节点独立统计流量
- 后端汇总时总流量 = 各节点流量之和
- 无重复计数

**验证方法**:
```bash
# 采集 Node A 流量
TRAFFIC_A=$(curl -s http://127.0.0.1:8081/traffic?clear=true -H "Authorization: test_secret_key_12345")

# 采集 Node B 流量
TRAFFIC_B=$(curl -s http://127.0.0.1:8082/traffic?clear=true -H "Authorization: test_secret_key_12345")

# 后端汇总
# total = TRAFFIC_A[user_id] + TRAFFIC_B[user_id]
```

---

### 测试 3: 并发采集无重复计数验证

**目标**: 验证同时采集多个节点时不会重复计数

**测试步骤**:
1. 用户在两个节点都产生流量
2. 使用 `?clear=true` 同时采集两个节点
3. 再次采集，验证计数器已清零
4. 验证总流量 = 第一次采集的总和

**关键验证点**:
- `?clear=true` 在每个节点独立清零
- 不会出现"采集 A 时 B 的流量丢失"的情况
- 增量采集逻辑正确

**预期结果**:
```bash
# 第一次采集
Node A: {"user_001": {"tx": 664, "rx": 128544}}
Node B: {"user_001": {"tx": 663, "rx": 151534}}
Total: tx=1327, rx=280078

# 第二次采集（应该为空或很小）
Node A: {}
Node B: {}
```

---

### 测试 4: 节点故障隔离验证

**目标**: 验证单个节点故障不影响其他节点的流量统计

**测试步骤**:
1. 两个节点正常运行
2. 用户在两个节点都产生流量
3. 停止 Node B
4. 采集 Node A 流量（应该成功）
5. 尝试采集 Node B 流量（应该失败）
6. 验证 Node A 的流量统计不受影响

**预期结果**:
- Node A 流量统计正常
- Node B 采集失败但不影响 Node A
- 后端能够处理部分节点故障的情况

**错误处理**:
```go
// 伪代码
for _, node := range nodes {
    traffic, err := fetchTraffic(node)
    if err != nil {
        log.Error("Failed to fetch from node", node, err)
        continue  // 继续采集其他节点
    }
    aggregate(traffic)
}
```

---

## 四、实施步骤

### Day 1 上午: 部署第二个节点

1. 复制 Node A 配置
2. 修改端口配置（8444, 8082）
3. 启动 Node B
4. 验证两个节点同时运行

### Day 1 下午: 测试 1 + 测试 2

1. 执行多节点独立运行测试
2. 执行跨节点流量汇总测试
3. 记录测试数据

### Day 2 上午: 测试 3 + 测试 4

1. 执行并发采集测试
2. 执行节点故障隔离测试
3. 分析测试结果

### Day 2 下午: 总结

1. 整理测试数据
2. 编写测试报告
3. 更新 README.md

---

## 五、配置文件

### Node B 配置 (hysteria2-server-node-b.yaml)

```yaml
listen: :8444

tls:
  cert: config/cert.pem
  key: config/key.pem

auth:
  type: http
  http:
    url: http://127.0.0.1:8080/api/v1/hysteria/auth
    insecure: false

trafficStats:
  listen: 127.0.0.1:8082
  secret: test_secret_key_12345

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
```

### sing-box 客户端配置（切换节点）

```json
{
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "node-a",
      "server": "127.0.0.1",
      "server_port": 8443,
      "password": "test_user_token_123"
    },
    {
      "type": "hysteria2",
      "tag": "node-b",
      "server": "127.0.0.1",
      "server_port": 8444,
      "password": "test_user_token_123"
    }
  ]
}
```

---

## 六、关键技术点

### 1. 增量采集逻辑

```bash
# 每 10 秒采集一次
while true; do
    # 并发采集所有节点
    TRAFFIC_A=$(curl -s http://127.0.0.1:8081/traffic?clear=true -H "Authorization: xxx")
    TRAFFIC_B=$(curl -s http://127.0.0.1:8082/traffic?clear=true -H "Authorization: xxx")

    # 汇总并写入数据库
    aggregate_and_save "$TRAFFIC_A" "$TRAFFIC_B"

    sleep 10
done
```

### 2. 流量汇总算法

```go
// 伪代码
func aggregateTraffic(nodeTraffics []NodeTraffic) map[string]Traffic {
    result := make(map[string]Traffic)

    for _, nodeTraffic := range nodeTraffics {
        for userID, traffic := range nodeTraffic.Users {
            result[userID].Tx += traffic.Tx
            result[userID].Rx += traffic.Rx
        }
    }

    return result
}
```

### 3. 错误处理

```go
// 伪代码
func collectAllNodes(nodes []Node) (map[string]Traffic, []error) {
    var errors []error
    aggregated := make(map[string]Traffic)

    for _, node := range nodes {
        traffic, err := fetchTraffic(node)
        if err != nil {
            errors = append(errors, err)
            continue  // 继续采集其他节点
        }

        for userID, t := range traffic {
            aggregated[userID].Tx += t.Tx
            aggregated[userID].Rx += t.Rx
        }
    }

    return aggregated, errors
}
```

---

## 七、风险与应对

| 风险 | 影响 | 应对方案 |
|------|------|---------|
| 端口冲突 | 节点无法启动 | 使用不同端口（8443, 8444） |
| 并发采集竞态 | 数据不一致 | 使用 `?clear=true` 独立清零 |
| 节点故障影响采集 | 部分流量丢失 | 错误处理 + 重试机制 |
| 时钟不同步 | 采集时序问题 | 使用相对时间戳 |

---

## 八、成功标准

Phase 0.4 成功完成的标准：

1. ✅ 两个节点同时运行无冲突
2. ✅ 跨节点流量汇总准确（误差 < 1%）
3. ✅ 并发采集无重复计数
4. ✅ 节点故障不影响其他节点
5. ✅ 所有测试脚本可重复执行
6. ✅ 测试报告完整清晰

---

**下一步**: 开始部署第二个 Hysteria2 节点
