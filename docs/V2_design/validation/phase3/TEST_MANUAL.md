# Phase 3 测试与验证手册

## 概述

本手册指导如何测试和验证 Phase 3 的用户流量统计和限制功能。

## 前置条件

1. 已完成 Phase 2 的测试验证
2. 确保以下工具已安装：
   - xray (支持 Stats API)
   - sing-box
   - Python 3 (带 xtlsapi 库)
   - Go 1.20+
   - curl

## 测试环境准备

### 1. 编译 Auth Service

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase3/auth-service
go build -o auth-service
```

预期输出：
- 编译成功，生成 `auth-service` 可执行文件
- 无编译错误

### 2. 启动所有服务

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase3
./start_all.sh
```

预期输出：
```
Starting Xray server...
Xray server started (PID: xxxxx)

Starting Auth Service...
Auth Service started (PID: xxxxx)
Auth Service started at http://localhost:8080

Starting IP Query Service...
IP Query Service started (PID: xxxxx)

Starting Sing-box clients...
Sing-box client 1 started (PID: xxxxx)
Sing-box client 2 started (PID: xxxxx)

All services started successfully!
```

### 3. 验证服务状态

```bash
# 检查进程是否运行
ps aux | grep xray
ps aux | grep auth-service
ps aux | grep sing-box

# 检查端口是否监听
lsof -i :10086  # Xray VLESS
lsof -i :10085  # Xray API
lsof -i :8080   # Auth Service
lsof -i :9999   # IP Query Service
```

## 流量生成工具

Phase 3 提供了专门的流量生成脚本 `generate_traffic.sh`，用于下载图片生成流量。

### 基本用法

```bash
# 为 Client 1 生成流量（默认）
./generate_traffic.sh

# 为 Client 1 下载 20 次图片
./generate_traffic.sh -c1 -n 20

# 为 Client 2 生成流量
./generate_traffic.sh -c2

# 为两个客户端都生成流量
./generate_traffic.sh -c1 -c2

# 查看帮助
./generate_traffic.sh -h
```

### 脚本特点

- **真实流量**: 从百度图片服务器下载约 200-300 KB 的图片
- **详细输出**: 显示 HTTP 状态码和下载字节数
- **统计信息**: 显示成功和失败次数
- **灵活配置**: 可指定客户端和下载次数

### 预期输出

```
使用 Client 1 (SOCKS5 代理端口 1080) 生成流量...
  下载图片 10 次...

  [1/10] ✅ 下载成功 (HTTP 200, 245678 bytes)
  [2/10] ✅ 下载成功 (HTTP 200, 243521 bytes)
  ...
  
  统计: 成功 10, 失败 0
```

---

## 测试场景

### 测试 1: 验证 Xray Stats API 工作正常

**目的**: 确认 Xray 的流量统计功能已启用

**步骤**:
```bash
xray api statsquery --server=127.0.0.1:10085
```

**预期结果**:
```
user>>>0x1234567890abcdef1234567890abcdef12345678>>>traffic>>>uplink: 0
user>>>0x1234567890abcdef1234567890abcdef12345678>>>traffic>>>downlink: 0
user>>>0x9876543210fedcba9876543210fedcba98765432>>>traffic>>>uplink: 0
user>>>0x9876543210fedcba9876543210fedcba98765432>>>traffic>>>downlink: 0
```

**验证点**:
- ✅ 命令执行成功，无错误
- ✅ 显示两个用户的流量统计
- ✅ 初始流量为 0

---

### 测试 2: 访问 Web 界面

**目的**: 验证 Web 界面正常显示

**步骤**:
1. 打开浏览器访问 http://localhost:8080
2. 观察页面内容

**预期结果**:
- ✅ 页面标题显示 "Auth Service - User Management with Traffic Stats"
- ✅ 表格包含 7 列：Email, UUID, Status, Uplink, Downlink, Total, Actions
- ✅ 显示 2 个用户
- ✅ User 1 (0x1234...) 状态为 "✓ Enabled"，有 "Disable" 和 "Restrict" 两个按钮
- ✅ User 2 (0x9876...) 状态为 "✗ Disabled"，只有 "Enable" 按钮
- ✅ 所有流量显示为 "0 B"

**截图示例**:
```
┌──────────────────────────────────────────┬──────────────────────────────────────┬──────────┬────────┬──────────┬────────┬─────────────────────┐
│ Email                                    │ UUID                                 │ Status   │ Uplink │ Downlink │ Total  │ Actions             │
├──────────────────────────────────────────┼──────────────────────────────────────┼──────────┼────────┼──────────┼────────┼─────────────────────┤
│ 0x1234567890abcdef1234567890abcdef12345678│ 11111111-1111-1111-1111-111111111111│ ✓ Enabled│ 0 B    │ 0 B      │ 0 B    │ [Disable] [Restrict]│
│ 0x9876543210fedcba9876543210fedcba98765432│ 22222222-2222-2222-2222-222222222222│ ✗ Disabled│ 0 B   │ 0 B      │ 0 B    │ [Enable]            │
└──────────────────────────────────────────┴──────────────────────────────────────┴──────────┴────────┴──────────┴────────┴─────────────────────┘
```

---

### 测试 3: 生成流量并观察统计

**目的**: 验证流量统计功能实时更新

**步骤**:

1. 使用流量生成脚本为 Client 1 生成流量（User 1 已启用）:
```bash
# 使用流量生成脚本（推荐）
./generate_traffic.sh

# 或者指定下载次数
./generate_traffic.sh -c1 -n 20

# 或者手动下载图片
for i in {1..10}; do
  curl -x socks5://127.0.0.1:1080 \
    "https://gips3.baidu.com/it/u=3886271102,3123389489&fm=3028&app=3028&f=JPEG&fmt=auto?w=1280&h=960" \
    -o /dev/null -s
  sleep 0.5
done
```

2. 观察 Web 界面（每 3 秒自动刷新）

**预期结果**:
- ✅ User 1 的 Uplink 流量增加（显示为 KB 或 MB）
- ✅ User 1 的 Downlink 流量增加
- ✅ User 1 的 Total 流量 = Uplink + Downlink
- ✅ User 2 的流量保持为 0 B（因为未启用）
- ✅ 流量数值自动格式化（B → KB → MB → GB）

**示例输出**:
```
User 1:
  Uplink: 2.34 KB
  Downlink: 5.67 KB
  Total: 8.01 KB

User 2:
  Uplink: 0 B
  Downlink: 0 B
  Total: 0 B
```

---

### 测试 4: 验证流量统计 API

**目的**: 确认后端 API 正确返回流量数据

**步骤**:
```bash
curl http://localhost:8080/api/users | jq
```

**预期结果**:
```json
{
  "users": [
    {
      "email": "0x1234567890abcdef1234567890abcdef12345678",
      "uuid": "11111111-1111-1111-1111-111111111111",
      "enabled": true,
      "traffic_uplink": 2345,
      "traffic_downlink": 5678
    },
    {
      "email": "0x9876543210fedcba9876543210fedcba98765432",
      "uuid": "22222222-2222-2222-2222-222222222222",
      "enabled": false,
      "traffic_uplink": 0,
      "traffic_downlink": 0
    }
  ]
}
```

**验证点**:
- ✅ 返回 JSON 格式数据
- ✅ 包含 `traffic_uplink` 和 `traffic_downlink` 字段
- ✅ User 1 的流量值 > 0
- ✅ User 2 的流量值 = 0

---

### 测试 5: 测试 Restrict 按钮功能

**目的**: 验证限制按钮能立即停止用户服务

**步骤**:

1. 在 Web 界面点击 User 1 旁边的 "Restrict" 按钮
2. 在弹出的确认对话框中点击 "确定"
3. 观察界面变化
4. 测试 User 1 是否还能连接

```bash
# 尝试通过 Client 1 访问（应该失败）
curl -x socks5://127.0.0.1:1080 http://127.0.0.1:9999/ip
```

**预期结果**:
- ✅ 弹出确认对话框："Are you sure you want to restrict this user? This will immediately stop their service."
- ✅ 点击确定后，显示成功消息："User restricted successfully"
- ✅ User 1 的状态变为 "✗ Disabled"
- ✅ User 1 的 Actions 列只显示 "Enable" 按钮
- ✅ curl 命令失败，无法连接（连接被拒绝或超时）

**验证 Xray 中用户已被删除**:
```bash
xray api inbounduser --server=127.0.0.1:10085 -tag=vless-in
```

预期输出：
- 不包含 User 1 的 email

---

### 测试 6: 启用 User 2 并观察流量

**目的**: 验证启用用户后流量统计正常工作

**步骤**:

1. 在 Web 界面点击 User 2 的 "Enable" 按钮
2. 等待操作完成
3. 使用 Client 2 生成流量

```bash
# 通过 Client 2 的 SOCKS5 代理访问
for i in {1..10}; do
  curl -x socks5://127.0.0.1:1081 http://127.0.0.1:9999/ip
  sleep 0.5
done
```

4. 观察 Web 界面

**预期结果**:
- ✅ User 2 状态变为 "✓ Enabled"
- ✅ User 2 显示 "Disable" 和 "Restrict" 按钮
- ✅ curl 命令成功返回 IP 地址
- ✅ User 2 的流量统计开始增加
- ✅ 流量数值实时更新（每 3 秒刷新）

---

### 测试 7: 测试 Disable 按钮（对比 Restrict）

**目的**: 验证 Disable 和 Restrict 功能相同

**步骤**:

1. 在 Web 界面点击 User 2 的 "Disable" 按钮
2. 观察界面变化
3. 测试 User 2 是否还能连接

```bash
curl -x socks5://127.0.0.1:1081 http://127.0.0.1:9999/ip
```

**预期结果**:
- ✅ User 2 状态变为 "✗ Disabled"
- ✅ curl 命令失败
- ✅ 功能与 Restrict 按钮相同

**区别说明**:
- **Disable**: 切换按钮，可以再次点击变为 Enable
- **Restrict**: 单向操作，直接禁用用户，需要点击 Enable 恢复

---

### 测试 8: 验证流量统计持久性

**目的**: 确认流量统计在 Xray 运行期间持续累计

**步骤**:

1. 启用 User 1
2. 记录当前流量值
3. 生成更多流量
4. 验证流量累加

```bash
# 第一次查询
xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>0x1234567890abcdef1234567890abcdef12345678>>>"

# 生成流量
for i in {1..20}; do
  curl -x socks5://127.0.0.1:1080 http://127.0.0.1:9999/ip
done

# 第二次查询
xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>0x1234567890abcdef1234567890abcdef12345678>>>"
```

**预期结果**:
- ✅ 第二次查询的流量值 > 第一次查询的流量值
- ✅ 流量持续累加，不会重置

---

### 测试 9: 测试自动刷新功能

**目的**: 验证 Web 界面自动刷新

**步骤**:

1. 打开浏览器开发者工具（F12）
2. 切换到 Network 标签
3. 观察网络请求

**预期结果**:
- ✅ 每 3 秒自动发送一次 GET /api/users 请求
- ✅ 无需手动刷新页面，流量数据自动更新
- ✅ 页面无闪烁，体验流畅

---

### 测试 10: 压力测试

**目的**: 验证系统在高流量下的稳定性

**步骤**:

1. 启用两个用户
2. 同时生成大量流量

```bash
# 终端 1: Client 1 生成流量
for i in {1..100}; do
  curl -x socks5://127.0.0.1:1080 http://127.0.0.1:9999/ip &
done

# 终端 2: Client 2 生成流量
for i in {1..100}; do
  curl -x socks5://127.0.0.1:1081 http://127.0.0.1:9999/ip &
done
```

3. 观察 Web 界面和系统资源

**预期结果**:
- ✅ 两个用户的流量都正常增加
- ✅ Web 界面响应正常，无卡顿
- ✅ Auth Service 日志无错误
- ✅ CPU 和内存使用正常

---

## 故障排查

### 问题 1: 流量统计显示为 0

**可能原因**:
- Xray Stats API 未启用
- 用户未启用
- 客户端未通过代理访问

**解决方法**:
```bash
# 检查 Xray 配置
cat xray_server.json | jq '.stats'
cat xray_server.json | jq '.api.services'

# 确认包含 "StatsService" 和 "stats": {}

# 手动查询流量
xray api statsquery --server=127.0.0.1:10085
```

### 问题 2: Restrict 按钮点击后无反应

**可能原因**:
- Auth Service 未运行
- xray api rmu 命令失败

**解决方法**:
```bash
# 检查 Auth Service 日志
tail -f logs/auth-service.log

# 手动测试删除用户
xray api rmu --server=127.0.0.1:10085 -tag=vless-in 0x1234567890abcdef1234567890abcdef12345678
```

### 问题 3: Web 界面不刷新

**可能原因**:
- JavaScript 错误
- 浏览器缓存

**解决方法**:
```bash
# 清除浏览器缓存
# Chrome: Cmd+Shift+R (Mac) 或 Ctrl+Shift+R (Windows)

# 检查浏览器控制台是否有错误
# F12 → Console 标签
```

### 问题 4: 流量格式化错误

**可能原因**:
- JavaScript formatBytes 函数错误

**解决方法**:
- 检查浏览器控制台
- 验证 API 返回的流量值是否为数字

---

## 清理环境

测试完成后，停止所有服务：

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase3
./stop_all.sh
```

预期输出：
```
Stopping all services...
Stopped process xxxxx (xray)
Stopped process xxxxx (auth-service)
Stopped process xxxxx (ip-service)
Stopped process xxxxx (sing-box)
Stopped process xxxxx (sing-box)
All services stopped.
```

---

## 测试检查清单

完成以下所有测试项后，Phase 3 验证通过：

- [ ] Xray Stats API 正常工作
- [ ] Web 界面正常显示流量统计
- [ ] 流量统计实时更新（每 3 秒）
- [ ] 流量格式化正确（B/KB/MB/GB）
- [ ] Restrict 按钮功能正常
- [ ] Disable 按钮功能正常
- [ ] Enable 按钮功能正常
- [ ] 两个用户可以独立统计流量
- [ ] 禁用用户后流量停止增长
- [ ] 启用用户后流量恢复统计
- [ ] API 返回正确的 JSON 数据
- [ ] 自动刷新功能正常
- [ ] 压力测试通过
- [ ] 无内存泄漏或性能问题

---

## 验收标准

Phase 3 功能验收通过需满足：

1. **功能完整性**: 所有测试场景通过
2. **性能要求**: 
   - Web 界面响应时间 < 1 秒
   - 流量统计延迟 < 5 秒
   - 支持至少 2 个并发用户
3. **稳定性**: 连续运行 1 小时无崩溃
4. **用户体验**: 
   - 界面友好，操作直观
   - 流量格式化易读
   - 按钮功能明确

---

## 下一步

Phase 3 验证通过后，可以考虑以下扩展：

1. **流量配额管理**: 为每个用户设置流量限制
2. **流量历史记录**: 将流量数据持久化到数据库
3. **流量图表**: 使用 Chart.js 显示流量趋势
4. **流量报警**: 超过阈值时发送通知
5. **流量重置**: 提供按钮重置用户流量统计
