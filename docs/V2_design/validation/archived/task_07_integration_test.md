---
task_id: 07
task_name: 执行完整集成测试
priority: high
dependencies: [01, 02, 03, 04, 05, 06]
status: pending
---

# 任务：执行完整集成测试

## 目标
按照正确的顺序启动所有组件，执行完整的端到端验证。

## 测试环境要求
- sing-box 已安装
- Go 1.21+ 已安装
- Python 3.8+ 已安装
- curl 可用

## 执行步骤

### Step 0：准备工作
```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code

# 查看 UUID 映射
python3 scripts/gen_uuid.py

# 记录输出的 UUID，填入客户端配置文件
```

**重要提示：** 所有代码文件都应该写入到 `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code` 目录下

### Step 1：启动 Auth Service
```bash
cd auth-service

# POC 环境（默认）
go run main.go

# 或生产环境
# CLASH_API_URL=http://<sing-box-ip>:9090 \
# CLASH_API_SECRET=<secret> \
# go run main.go
```

**验证：** 服务在 :8080 启动，日志显示监听端口

### Step 2：初始同步
```bash
# 新终端
curl -X POST http://127.0.0.1:8080/v1/sync
```

**预期响应：**
```json
{
  "status": "sing_box_not_running",
  "user_count": 1,
  "users": [...]
}
```

**说明：** 此时 sing-box 未启动，这是正常的

### Step 3：启动 sing-box 服务端
```bash
# 新终端
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
sing-box run -c singbox-server/config.json
```

**验证：**
- 服务在 :10086 启动
- Clash API 在 :9090 可用
- 日志显示 VMess inbound 已启动

### Step 4：启动客户端
```bash
# 终端 A
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
sing-box run -c singbox-client-a/config.json

# 终端 B（新终端）
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
sing-box run -c singbox-client-b/config.json
```

**验证：**
- Client A SOCKS 代理在 :1080
- Client B SOCKS 代理在 :1081
- 两个客户端都显示已连接到服务端

### Step 5：执行自动化测试
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

### 2. 命题 A（准入）
- [ ] Client A 通过 SOCKS :1080 成功访问外部 URL
- [ ] sing-box 服务端日志显示连接成功
- [ ] 返回的 IP 地址是服务端的出口 IP

### 3. 命题 B（拒绝）
- [ ] Client B 通过 SOCKS :1081 访问失败
- [ ] sing-box 服务端日志显示认证失败
- [ ] curl 返回连接错误

### 4. 命题 C（动态生效）
- [ ] `allowed_ids.json` 成功添加 Client B 地址
- [ ] `/v1/sync` 返回 `"status": "synced_and_reloaded"`
- [ ] Client B 重试后访问成功
- [ ] Client A 在整个过程中持续可用（不中断）
- [ ] reload 时间 < 100ms

### 5. 状态恢复
- [ ] `allowed_ids.json` 还原到初始状态
- [ ] Client B 再次被拒绝

## 性能指标
- reload 时间：< 100ms
- 已有连接不中断
- 新连接立即使用新配置

## 故障排查

### Auth Service 无法连接 Clash API
**症状：** `/v1/sync` 返回 "sing_box_not_running"
**解决：** 确保 sing-box 已启动且 Clash API 在 :9090 可用

### 客户端连接失败
**症状：** curl 返回 SOCKS5 连接错误
**检查：**
1. sing-box 客户端是否正常启动
2. UUID 是否正确填入配置文件
3. 服务端是否在 :10086 监听

### UUID 不匹配
**症状：** 客户端连接被拒绝，但地址在列表中
**解决：**
1. 运行 `python3 scripts/gen_uuid.py` 重新生成 UUID
2. 确保客户端配置使用正确的 UUID
3. 调用 `/v1/sync` 重新同步

## 成功标准
所有测试通过，输出显示：
```
验证结果：通过 4 个，失败 0 个
🎉 所有命题验证通过
```

## 文档位置
参考 [POC_准入控制验证方案.md](POC_准入控制验证方案.md) 第 6-7 节
