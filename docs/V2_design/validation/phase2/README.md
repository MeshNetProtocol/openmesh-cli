# Phase 2: Sing-box + Xray 动态用户管理验证

## 测试目标

验证通过 Auth Service 动态控制用户访问权限：
- Sing-box 作为客户端
- Xray 作为服务端
- Go Auth Service 提供 Web 界面管理用户启用/禁用
- 实时生效，无需重启服务

## 架构

```
[Sing-box Client 1] ──┐
                       ├──> [Xray Server] ──> [IP Query Service]
[Sing-box Client 2] ──┘
         ↑
         │ gRPC API
         │
   [Auth Service]
   (Web UI + API)
```

## 组件

1. **Xray Server** - VLESS 协议服务端，监听 10086 端口
2. **Auth Service** - Go Web 服务，提供用户管理界面和 API
3. **Sing-box Clients** - 两个客户端实例，使用不同的 UUID
4. **IP Query Service** - 简单的本地 IP 查询服务

## 快速开始

```bash
# 1. 启动所有服务
./start_all.sh

# 2. 访问 Auth Service Web 界面
open http://localhost:8080

# 3. 测试客户端连接
./test_clients.sh

# 4. 停止所有服务
./stop_all.sh
```

## 测试流程

1. 启动 Xray 服务端
2. 启动 Auth Service
3. 启动 IP Query Service
4. 启动两个 Sing-box 客户端
5. 在 Web 界面禁用 User 1
6. 测试 User 1 连接（预期失败）
7. 测试 User 2 连接（预期成功）
8. 在 Web 界面启用 User 1
9. 测试 User 1 连接（预期成功）

## 文件结构

```
phase2/
├── README.md                 # 本文档
├── users.json               # 用户配置
├── xray_server.json         # Xray 服务端配置
├── singbox_client1.json     # Sing-box 客户端 1 配置
├── singbox_client2.json     # Sing-box 客户端 2 配置
├── auth-service/            # Auth Service 源码
│   ├── main.go
│   ├── go.mod
│   └── templates/
│       └── index.html
├── ip-service/              # IP 查询服务
│   └── main.go
├── start_all.sh             # 启动所有服务
├── stop_all.sh              # 停止所有服务
└── test_clients.sh          # 测试脚本
```
