# OpenMesh V2 准入控制 POC - 集成测试指南

## 概述

本指南提供完整的端到端集成测试步骤,用于验证 EVM 地址准入控制的三个核心命题。

## 环境要求

✓ sing-box 已安装
✓ Go 1.21+ 已安装  
✓ Python 3.8+ 已安装
✓ curl 可用

## 快速启动

使用提供的启动脚本一键启动所有组件:

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
bash scripts/start_all.sh
```

## 手动启动步骤

### Step 0: 准备工作

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code

# 查看 UUID 映射
python3 scripts/gen_uuid.py
```

**输出示例:**
```
client_a: 0xaaaa... → UUID: d3507f8a-d4eb-541a-a231-929c6237eee5
client_b: 0xbbbb... → UUID: b5001757-5cd5-56f9-b9ae-6168583ce15a
client_c: 0xcccc... → UUID: 5d6feeaf-3d34-589c-a21d-795a2f9d99af
```

### Step 1: 启动 Auth Service

```bash
# 终端 1
cd auth-service
ALLOWED_IDS_PATH=../allowed_ids.json \
CONFIG_PATH=../singbox-server/config.json \
PORT=8080 \
go run main.go
```

**验证:** 服务在 :8080 启动,日志显示:
```
Auth Service 启动在 :8080
配置文件路径: ../allowed_ids.json
当前用户数: 1
```

### Step 2: 初始同步

```bash
# 新终端
curl -X POST http://127.0.0.1:8080/v1/sync
```

**预期响应:**
```json
{
  "status": "synced_only",
  "user_count": 1,
  "users": [...]
}
```

**说明:** 此时 sing-box 未启动,配置已保存但 reload 失败是正常的。

### Step 3: 启动 sing-box 服务端

```bash
# 终端 2
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
sing-box run -c singbox-server/config.json
```

**验证:**
- VMess inbound 在 :10086 启动
- Clash API 在 :9090 可用
- 日志显示用户列表已加载

### Step 4: 启动客户端

```bash
# 终端 3 - Client A
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
sing-box run -c singbox-client-a/config.json

# 终端 4 - Client B
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
sing-box run -c singbox-client-b/config.json
```

**验证:**
- Client A SOCKS 代理在 :1080
- Client B SOCKS 代理在 :1081
- 两个客户端都显示已连接

### Step 5: 执行自动化测试

```bash
# 新终端
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
bash scripts/test_all.sh
```

## 验证检查点

### 1. 前置检查
- [ ] Auth Service 健康检查返回 200
- [ ] Client A 的 EVM 地址显示 `"allowed": true`
- [ ] Client B 的 EVM 地址显示 `"allowed": false`

```bash
curl http://localhost:8080/health
curl "http://localhost:8080/v1/check?id=0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
curl "http://localhost:8080/v1/check?id=0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
```

### 2. 命题 A (准入)
- [ ] Client A 通过 SOCKS :1080 成功访问外部 URL
- [ ] sing-box 服务端日志显示连接成功
- [ ] 返回的 IP 地址是服务端的出口 IP

```bash
curl --socks5 127.0.0.1:1080 http://httpbin.org/ip
```

### 3. 命题 B (拒绝)
- [ ] Client B 通过 SOCKS :1081 访问失败
- [ ] sing-box 服务端日志显示认证失败
- [ ] curl 返回连接错误

```bash
curl --socks5 127.0.0.1:1081 http://httpbin.org/ip
```

### 4. 命题 C (动态生效)
- [ ] `allowed_ids.json` 成功添加 Client B 地址
- [ ] `/v1/sync` 返回 `"status": "synced_and_reloaded"`
- [ ] Client B 重试后访问成功
- [ ] Client A 在整个过程中持续可用 (不中断)
- [ ] reload 时间 < 100ms

### 5. 状态恢复
- [ ] `allowed_ids.json` 还原到初始状态
- [ ] Client B 再次被拒绝

## 性能指标

- **reload 时间:** < 100ms
- **已有连接:** 不中断
- **新连接:** 立即使用新配置

## 故障排查

### Auth Service 无法连接 Clash API
**症状:** `/v1/sync` 返回 "synced_only"  
**解决:** 确保 sing-box 已启动且 Clash API 在 :9090 可用

### 客户端连接失败
**症状:** curl 返回 SOCKS5 连接错误  
**检查:**
1. sing-box 客户端是否正常启动
2. UUID 是否正确填入配置文件
3. 服务端是否在 :10086 监听

### UUID 不匹配
**症状:** 客户端连接被拒绝,但地址在列表中  
**解决:**
1. 运行 `python3 scripts/gen_uuid.py` 重新生成 UUID
2. 确保客户端配置使用正确的 UUID
3. 调用 `/v1/sync` 重新同步

## 成功标准

所有测试通过,输出显示:
```
验证结果: 通过 4 个, 失败 0 个
🎉 所有命题验证通过
```

## 组件架构

```
┌─────────────────┐
│  Auth Service   │ :8080
│  (Go)           │
└────────┬────────┘
         │ /v1/sync
         ↓
┌─────────────────┐
│  sing-box       │ :10086 (VMess)
│  Server         │ :9090 (Clash API)
└────────┬────────┘
         │
    ┌────┴────┐
    ↓         ↓
┌────────┐ ┌────────┐
│Client A│ │Client B│
│:1080   │ │:1081   │
└────────┘ └────────┘
```

## 文件清单

```
code/
├── allowed_ids.json              # 允许列表配置
├── auth-service/
│   ├── main.go                   # Auth Service 主程序
│   ├── go.mod                    # Go 模块配置
│   └── README.md                 # Auth Service 文档
├── singbox-server/
│   └── config.json               # 服务端配置 (由 Auth Service 生成)
├── singbox-client-a/
│   └── config.json               # Client A 配置
├── singbox-client-b/
│   └── config.json               # Client B 配置
└── scripts/
    ├── gen_uuid.py               # UUID 生成工具
    ├── test_all.sh               # 自动化测试脚本
    └── start_all.sh              # 一键启动脚本
```

## 相关文档

- [POC 准入控制验证方案](../POC_准入控制验证方案.md)
- [Auth Service README](auth-service/README.md)
