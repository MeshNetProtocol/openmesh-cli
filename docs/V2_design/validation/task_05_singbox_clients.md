---
task_id: 05
task_name: 配置 sing-box 客户端
priority: medium
dependencies: [01]
status: pending
---

# 任务：配置 sing-box 客户端

## 目标
创建两个 sing-box 客户端配置，用于验证准入控制的三个命题。

## Client A 配置（ID 在列表中）

### 基本信息
- EVM 地址：`0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
- UUID：通过 `gen_uuid.py` 计算得出
- SOCKS 代理端口：1080

### 配置结构
```json
{
  "log": { "level": "info" },
  "inbounds": [{
    "type": "socks",
    "tag": "socks-in",
    "listen": "127.0.0.1",
    "listen_port": 1080
  }],
  "outbounds": [{
    "type": "vmess",
    "tag": "vmess-out",
    "server": "127.0.0.1",
    "server_port": 10086,
    "uuid": "<UUID_OF_CLIENT_A>",
    "security": "auto",
    "alter_id": 0
  }]
}
```

### 用途
- 验证命题 A：ID 在列表中的客户端可以正常使用
- 验证命题 C：reload 后已有连接不中断

## Client B 配置（ID 初始不在列表）

### 基本信息
- EVM 地址：`0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`
- UUID：通过 `gen_uuid.py` 计算得出
- SOCKS 代理端口：1081

### 配置结构
与 Client A 相同，但：
- `listen_port`: 1081
- `uuid`: `<UUID_OF_CLIENT_B>`

### 用途
- 验证命题 B：ID 不在列表中的客户端被拒绝
- 验证命题 C：动态添加后立即生效

## 实现步骤
1. 运行 `python3 scripts/gen_uuid.py` 获取两个客户端的 UUID
2. 将 UUID 填入对应的配置文件
3. 确保两个客户端使用不同的 SOCKS 端口（1080 和 1081）

## 验证标准
- [ ] Client A 配置正确，UUID 与 EVM 地址匹配
- [ ] Client B 配置正确，UUID 与 EVM 地址匹配
- [ ] 两个客户端可以同时启动，不冲突
- [ ] SOCKS 代理端口可正常访问

## 文件位置
**代码输出目录：** `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code`

具体路径：
- `code/singbox-client-a/config.json`
- `code/singbox-client-b/config.json`

## 启动命令
```bash
# 终端 A
sing-box run -c singbox-client-a/config.json

# 终端 B
sing-box run -c singbox-client-b/config.json
```
