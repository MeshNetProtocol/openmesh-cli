# sing-box 多用户测试环境

这是 OpenMesh V2 流量统计验证的测试环境，用于验证多节点并行架构下的流量汇总和预付费计费能力。

## 快速启动

### 1. 启动所有服务节点

```bash
./start-nodes.sh
```

这将启动 3 个 sing-box 节点：
- node-a: 127.0.0.1:8001
- node-b: 127.0.0.1:8002
- node-c: 127.0.0.1:8003

### 2. 启动客户端

```bash
./start-client.sh
```

默认连接到 node-a。客户端会在 127.0.0.1:1080 提供 SOCKS5 代理。

切换到其他节点：
```bash
./start-client.sh node-b  # 连接到 node-b
./start-client.sh node-c  # 连接到 node-c
```

### 3. 测试连接

在另一个终端运行：
```bash
./test-traffic.sh
```

或手动测试：
```bash
curl -x socks5h://127.0.0.1:1080 https://www.google.com
```

### 4. 停止所有节点

```bash
./stop-nodes.sh
```

客户端按 Ctrl+C 停止。

## 目录结构

```
test-environment/
├── sing-box              # sing-box 可执行文件
├── passwords.txt         # 密码配置（敏感信息）
├── nodes/
│   ├── node-a/
│   │   ├── config.json   # 节点 A 配置（端口 8001）
│   │   └── logs/         # 节点 A 日志
│   ├── node-b/
│   │   ├── config.json   # 节点 B 配置（端口 8002）
│   │   └── logs/         # 节点 B 日志
│   └── node-c/
│       ├── config.json   # 节点 C 配置（端口 8003）
│       └── logs/         # 节点 C 日志
├── client/
│   ├── config.json       # 客户端配置
│   └── logs/             # 客户端日志
└── metering-service/     # 记账服务（待实现）
```

## 测试用户

所有节点配置了 3 个测试用户：

| 用户名 | 用途 |
|--------|------|
| alice | 默认测试用户 |
| bob | 多用户并发测试 |
| charlie | 多用户并发测试 |

密码详见 `passwords.txt` 文件。

## 配置说明

### 服务端节点配置

- **协议**: Shadowsocks 2022 (2022-blake3-aes-128-gcm)
- **监听地址**: 127.0.0.1（单机测试）
- **多用户**: 启用 `managed: true`
- **多路复用**: 启用
- **出站**: Direct，绑定物理网卡 en0（避免流量死循环）

### 客户端配置

- **入站**: SOCKS5 (127.0.0.1:1080)
- **出站**: Shadowsocks，连接到服务节点
- **默认用户**: alice

## 查看日志

```bash
# 查看节点日志
tail -f nodes/node-a/logs/sing-box.log
tail -f nodes/node-b/logs/sing-box.log
tail -f nodes/node-c/logs/sing-box.log

# 查看所有节点日志
tail -f nodes/*/logs/sing-box.log
```

## 切换到双机部署

当前配置为单机测试。如需切换到双机部署：

1. **修改服务端配置**（在服务器机器上）：
   - 将所有节点配置中的 `"listen": "127.0.0.1"` 改为 `"listen": "0.0.0.0"`
   - 确保防火墙允许端口 8001-8003

2. **修改客户端配置**（在客户端机器上）：
   - 将 `client/config.json` 中的 `"server": "127.0.0.1"` 改为服务器 IP
   - 可以移除服务端配置中的 `"bind_interface": "en0"`（不再需要避免死循环）

## 常见问题

### 节点启动失败

1. **端口被占用**
   ```bash
   lsof -i :8001  # 检查端口占用
   ```
   解决：修改配置文件中的端口号

2. **权限问题**
   - macOS 可能提示允许网络访问
   - 前往：系统设置 → 隐私与安全性 → 允许 sing-box

### 客户端连接失败

1. **检查节点是否运行**
   ```bash
   ps aux | grep sing-box
   ```

2. **检查日志**
   ```bash
   tail -f nodes/node-a/logs/sing-box.log
   ```

3. **验证密码配置**
   - 确保客户端密码格式正确：`<server_password>:<user_password>`

### 流量死循环

如果在单机测试时遇到流量死循环：
- 确保服务端配置中有 `"bind_interface": "en0"`
- 检查网卡名称是否正确：`ifconfig` 查看可用网卡

## 下一步

- [ ] P0.3 - 实现统一记账服务
- [ ] P0.4 - 实现节点流量上报
- [ ] P0.5 - 编写自动化测试脚本
- [ ] P0.6 - 部署测试环境
- [ ] P0.7 - 执行功能测试

## 参考文档

- [00-测试目标与架构.md](../00-测试目标与架构.md)
- [P0.1-sing-box多用户配置技术调研报告.md](../P0.1-sing-box多用户配置技术调研报告.md)
- [sing-box 官方文档](https://sing-box.sagernet.org)
