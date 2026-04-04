# Phase 2 技术验证环境 - 完成

## 概述

已完成 Sing-box + Xray 动态用户管理验证环境的搭建。

## 架构

```
┌─────────────────┐
│  Auth Service   │ ← Web UI (http://localhost:8080)
│   (Go + Web)    │
└────────┬────────┘
         │ gRPC API (xray api adu/rmu)
         ↓
┌─────────────────┐
│  Xray Server    │ ← VLESS 协议 (端口 10086)
│   (VLESS)       │
└────────┬────────┘
         │
    ┌────┴────┐
    ↓         ↓
┌─────────┐ ┌─────────┐
│Sing-box1│ │Sing-box2│ ← 两个客户端实例
│ User 1  │ │ User 2  │
│:10801   │ │:10802   │
└────┬────┘ └────┬────┘
     │           │
     └─────┬─────┘
           ↓
    ┌─────────────┐
    │ IP Service  │ ← 本地 IP 查询 (端口 9999)
    └─────────────┘
```

## 组件说明

1. **Xray Server** (端口 10086)
   - VLESS 协议服务端
   - gRPC API (端口 10085)
   - 初始配置包含 2 个用户

2. **Auth Service** (端口 8080)
   - Go Web 服务
   - 提供用户管理界面
   - 通过 gRPC API 动态添加/删除用户
   - 读取 `users.json` 配置

3. **Sing-box Clients**
   - Client 1: 端口 10801, user1@test.com
   - Client 2: 端口 10802, user2@test.com
   - 每个客户端使用不同的 UUID

4. **IP Query Service** (端口 9999)
   - 简单的 Go HTTP 服务
   - 返回客户端 IP 地址

## 快速开始

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase2

# 1. 启动所有服务
./start_all.sh

# 2. 访问 Web 界面
open http://localhost:8080

# 3. 测试客户端连接
./test_clients.sh

# 4. 停止所有服务
./stop_all.sh
```

## 测试流程

### 自动化测试

1. 启动所有服务：`./start_all.sh`
2. 测试初始连接：`./test_clients.sh` (两个客户端都应该成功)
3. 在 Web 界面禁用 user1
4. 再次测试：`./test_clients.sh` (user1 失败，user2 成功)
5. 在 Web 界面启用 user1
6. 再次测试：`./test_clients.sh` (两个客户端都应该成功)

### 手动测试

```bash
# 通过 Client 1 访问 IP 服务
curl -x http://127.0.0.1:10801 http://localhost:9999/ip

# 通过 Client 2 访问 IP 服务
curl -x http://127.0.0.1:10802 http://localhost:9999/ip
```

## 文件结构

```
phase2/
├── README.md                    # 详细说明文档
├── QUICKSTART.md                # 快速开始指南
├── users.json                   # 用户配置文件
├── xray_server.json             # Xray 服务端配置
├── singbox_client1.json         # Sing-box 客户端 1
├── singbox_client2.json         # Sing-box 客户端 2
├── start_all.sh                 # 启动所有服务
├── stop_all.sh                  # 停止所有服务
├── test_clients.sh              # 测试脚本
├── auth-service/                # Auth Service 源码
│   ├── main.go                  # Go Web 服务
│   └── go.mod
├── ip-service/                  # IP 查询服务源码
│   ├── main.go                  # Go HTTP 服务
│   └── go.mod
└── logs/                        # 服务日志目录
```

## 验证目标

✅ 验证通过 Auth Service 动态控制用户访问权限
✅ 验证 Sing-box 客户端与 Xray 服务端的互操作性
✅ 验证 gRPC API 实时生效，无需重启服务
✅ 验证每次请求都是新连接（通过 IP 查询服务）

## 依赖要求

- xray (已安装)
- sing-box (需要安装: `brew install sing-box`)
- go 1.21+ (需要安装)

## 注意事项

1. 确保所有端口未被占用 (10085, 10086, 10801, 10802, 8080, 9999)
2. Auth Service 会自动调用 `xray api adu/rmu` 命令
3. 所有服务日志保存在 `logs/` 目录
4. 用户状态保存在 `users.json`，重启后保持

## 下一步

环境已准备完毕，可以开始测试：

```bash
cd phase2
./start_all.sh
```

然后访问 http://localhost:8080 进行用户管理。
