---
task_id: 03
task_name: 实现 Auth Service HTTP 服务
priority: high
dependencies: [01, 02]
status: pending
---

# 任务：实现 Auth Service HTTP 服务

## 目标
用 Go 实现 HTTP 服务，负责读取允许列表、生成 sing-box 配置、触发 graceful reload。

## API 端点

### 1. POST /v1/sync
**功能：** 同步用户列表并 reload sing-box
- 读取 `allowed_ids.json`
- 为每个 EVM 地址计算 UUID
- 生成完整的 sing-box config.json
- 通过 Clash API 推送配置并触发 graceful reload

**响应：**
```json
{
  "status": "synced_and_reloaded",
  "user_count": 1,
  "users": [
    {
      "evm_address": "0xaaa...",
      "uuid": "..."
    }
  ]
}
```

### 2. GET /v1/check?id=<evm_address>
**功能：** 检查 EVM 地址是否在允许列表中
- 返回 200 (允许) 或 403 (拒绝)
- 包含 EVM 地址、UUID 和允许状态

### 3. GET /health
**功能：** 健康检查
- 返回服务状态和当前允许列表数量

## 技术要求

### UUID 派生算法
```go
// 使用 SHA-1 实现标准 uuid v5（NAMESPACE_DNS）
// 必须与 Python uuid.uuid5() 结果完全一致
func evmToUUID(evmAddress string) string {
    // NAMESPACE_DNS: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
    // SHA-1(namespace_bytes + evm_address_bytes)
    // 设置版本位（5）和变体位
}
```

### Clash API 集成
- POC 环境：`http://127.0.0.1:9090`
- 生产环境：通过 `CLASH_API_URL` 环境变量配置
- 认证：通过 `CLASH_API_SECRET` 环境变量配置
- 端点：`PUT /configs?force=false`（graceful reload）

### sing-box 配置生成
```json
{
  "log": { "level": "info" },
  "inbounds": [{
    "type": "vmess",
    "tag": "vmess-in",
    "listen": "0.0.0.0",
    "listen_port": 10086,
    "users": [
      {
        "name": "<evm_address>",
        "uuid": "<derived_uuid>",
        "alter_id": 0
      }
    ]
  }],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "secret": "poc-secret"
    }
  }
}
```

## 验证标准
- [ ] 所有 API 端点正常响应
- [ ] UUID 派生结果与 Python 工具一致
- [ ] 成功通过 Clash API 触发 sing-box reload
- [ ] reload 时间 < 100ms
- [ ] 已有连接不中断

## 文件位置
**代码输出目录：** `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code`

具体路径：`code/auth-service/main.go`

## 环境变量
- `PORT`: 服务监听端口（默认 8080）
- `CLASH_API_URL`: Clash API 地址（默认 http://127.0.0.1:9090）
- `CLASH_API_SECRET`: Clash API 密钥（默认 poc-secret）
