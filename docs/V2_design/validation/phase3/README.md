# Phase 3: 用户流量统计与限制功能

## 概述

Phase 3 在 Phase 2 的基础上增加了用户流量统计功能,并在 Web 界面上显示每个用户的实时流量使用情况,同时提供限制按钮来快速停止服务。

## 新增功能

1. **实时流量统计**: 通过 Xray Stats API 获取每个用户的上行和下行流量
2. **流量可视化**: 在 Web 界面上以人类可读格式(B/KB/MB/GB)显示流量
3. **快速限制**: 在流量旁边提供"Restrict"按钮,一键停止用户服务
4. **自动刷新**: 界面每 3 秒自动更新流量数据

## 架构

```
[Sing-box Client 1] ──┐
                       ├──> [Xray Server] ──> [IP Query Service]
[Sing-box Client 2] ──┘         │
         ↑                       │
         │ gRPC API              │ Stats API
         │                       │
   [Auth Service] ←──────────────┘
   (Web UI + API + Traffic Stats)
```

## 组件

1. **Xray Server** - VLESS 协议服务端，监听 10086 端口，启用 Stats API
2. **Auth Service** - Go Web 服务，提供用户管理、流量统计界面和 API
3. **Sing-box Clients** - 两个客户端实例，使用不同的 UUID
4. **IP Query Service** - 简单的本地 IP 查询服务

## 快速开始

```bash
# 1. 编译 Auth Service
cd auth-service
go build -o auth-service
cd ..

# 2. 启动所有服务
./start_all.sh

# 3. 访问 Web 界面
open http://localhost:8080

# 4. 生成流量并观察统计
./test_clients.sh

# 5. 停止所有服务
./stop_all.sh
```

## 文件结构

```
phase3/
├── README.md                 # 本文档
├── TEST_MANUAL.md           # 详细测试手册
├── users.json               # 用户配置
├── xray_server.json         # Xray 服务端配置(已启用 Stats)
├── singbox_client1.json     # Sing-box 客户端 1 配置
├── singbox_client2.json     # Sing-box 客户端 2 配置
├── auth-service/            # Auth Service 源码(新增流量统计)
│   ├── main.go              # 主程序(包含流量查询和限制功能)
│   └── go.mod
├── ip-service/              # IP 查询服务
│   └── main.go
├── test_xtlsapi.py          # xtlsapi 测试脚本
├── grpc_add_user.py         # gRPC 添加用户脚本
├── start_all.sh             # 启动所有服务
├── stop_all.sh              # 停止所有服务
└── test_clients.sh          # 测试脚本
```

## 核心改进

### 1. Go Auth Service 改进

- 新增 `TrafficUplink` 和 `TrafficDownlink` 字段到 User 结构
- 实现 `queryUserTraffic()` 函数查询单个用户流量
- 实现 `UpdateTrafficStats()` 方法更新所有用户流量
- 新增 `/api/users/restrict` 端点用于快速限制用户
- 启动定时任务每 5 秒更新一次流量统计

### 2. Web UI 改进

- 表格新增 3 列: Uplink, Downlink, Total
- 实现 `formatBytes()` 函数格式化流量显示
- 新增 `restrictUser()` 函数处理限制操作
- 自动刷新间隔从 5 秒缩短到 3 秒
- 为已启用用户显示"Restrict"按钮

### 3. Xray 配置

Phase 2 的配置已经启用了 Stats API:
- `api.services` 包含 `StatsService`
- `stats: {}` 已启用
- `policy.system.statsInboundUplink: true`
- `policy.system.statsInboundDownlink: true`

## API 端点

### GET /api/users

返回所有用户及其流量统计:

```json
{
  "users": [
    {
      "email": "0x1234567890abcdef1234567890abcdef12345678",
      "uuid": "11111111-1111-1111-1111-111111111111",
      "enabled": true,
      "traffic_uplink": 1234567,
      "traffic_downlink": 7654321
    }
  ]
}
```

### POST /api/users/toggle

切换用户启用/禁用状态(与 Phase 2 相同)

### POST /api/users/restrict

快速限制用户(禁用并从 Xray 删除):

```json
{
  "email": "0x1234567890abcdef1234567890abcdef12345678"
}
```

## 测试验证

详细的测试步骤和验证方法请参考 [TEST_MANUAL.md](TEST_MANUAL.md)

主要测试场景:
1. 验证 Xray Stats API 工作正常
2. 访问 Web 界面查看流量统计
3. 生成流量并观察实时更新
4. 测试 Restrict 按钮功能
5. 验证流量统计持久性
6. 测试自动刷新功能

## 与 Phase 2 的区别

| 功能 | Phase 2 | Phase 3 |
|------|---------|---------|
| 用户管理 | ✅ | ✅ |
| 动态启用/禁用 | ✅ | ✅ |
| 流量统计 | ❌ | ✅ |
| 流量显示 | ❌ | ✅ |
| 快速限制按钮 | ❌ | ✅ |
| 自动刷新间隔 | 5 秒 | 3 秒 |

## 技术要点

1. **流量查询**: 使用 `xray api statsquery` 命令查询流量
2. **流量格式**: 统计键格式为 `user>>>{email}>>>traffic>>>{uplink|downlink}`
3. **定时更新**: 后端每 5 秒查询一次,前端每 3 秒刷新一次
4. **流量重置**: 流量统计在 Xray 重启后会重置为 0

## 下一步扩展

1. **流量配额管理**: 为每个用户设置流量限制,超过自动限制
2. **流量历史记录**: 将流量数据持久化到数据库
3. **流量图表**: 使用 Chart.js 显示流量趋势图
4. **流量报警**: 当用户流量超过阈值时发送通知
5. **流量重置**: 提供按钮重置用户的流量统计

## 参考文档

- [Phase 3 POC 文档](../phase3_traffic_stats_poc.md)
- [Phase 3 测试手册](TEST_MANUAL.md)
- [Phase 2 文档](../phase2/README.md)
- [技术方案](../../1.技术方案.md)
