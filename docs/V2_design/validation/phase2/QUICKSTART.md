# Phase 2 验证测试

## 快速开始

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase2

# 1. 启动所有服务
./start_all.sh

# 2. 测试客户端连接
./test_clients.sh

# 3. 访问 Web 界面管理用户
open http://localhost:8080

# 4. 在界面中禁用 user1，然后再次测试
./test_clients.sh

# 5. 停止所有服务
./stop_all.sh
```

## 架构说明

- **Xray Server** (端口 10086): VLESS 协议服务端
- **Auth Service** (端口 8080): Web 界面 + gRPC API 管理
- **IP Query Service** (端口 9999): 简单的 IP 查询服务
- **Sing-box Client 1** (端口 10801): user1@test.com
- **Sing-box Client 2** (端口 10802): user2@test.com

## 测试流程

1. 所有用户初始状态为启用
2. 测试两个客户端连接（都应该成功）
3. 在 Web 界面禁用 user1
4. 再次测试（user1 失败，user2 成功）
5. 在 Web 界面启用 user1
6. 再次测试（都应该成功）

## 文件说明

- `xray_server.json` - Xray 服务端配置
- `singbox_client1.json` - Sing-box 客户端 1 配置
- `singbox_client2.json` - Sing-box 客户端 2 配置
- `users.json` - 用户配置文件
- `auth-service/` - Go Auth Service 源码
- `ip-service/` - Go IP 查询服务源码
- `start_all.sh` - 启动所有服务
- `stop_all.sh` - 停止所有服务
- `test_clients.sh` - 测试客户端连接
- `logs/` - 服务日志目录
