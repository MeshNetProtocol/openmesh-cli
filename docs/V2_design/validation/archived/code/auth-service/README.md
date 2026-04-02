# Auth Service

EVM 地址准入控制的 HTTP 服务,负责管理允许列表、生成 sing-box 配置并触发 graceful reload。

## 功能特性

- **UUID 派生**: 使用 UUID v5 (SHA-1 + NAMESPACE_DNS) 将 EVM 地址转换为 UUID
- **准入检查**: 验证 EVM 地址是否在允许列表中
- **配置同步**: 自动生成 sing-box 配置并触发 graceful reload
- **健康检查**: 提供服务状态监控端点

## API 端点

### POST /v1/sync
同步用户列表并重载 sing-box 配置。

**响应示例:**
```json
{
  "status": "synced_and_reloaded",
  "user_count": 1,
  "users": [
    {
      "evm_address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "uuid": "d3507f8a-d4eb-541a-a231-929c6237eee5"
    }
  ]
}
```

### GET /v1/check?id=<evm_address>
检查 EVM 地址是否在允许列表中。

**响应示例 (允许):**
```json
{
  "evm_address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "uuid": "d3507f8a-d4eb-541a-a231-929c6237eee5",
  "allowed": true
}
```

**响应示例 (拒绝):**
```json
{
  "evm_address": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "uuid": "b5001757-5cd5-56f9-b9ae-6168583ce15a",
  "allowed": false
}
```

### GET /health
健康检查端点。

**响应示例:**
```json
{
  "status": "healthy",
  "user_count": 1,
  "timestamp": "2026-04-01T19:55:24+08:00"
}
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | `8080` | 服务监听端口 |
| `ALLOWED_IDS_PATH` | `../allowed_ids.json` | 允许列表配置文件路径 |
| `CLASH_API_URL` | `http://127.0.0.1:9090` | Clash API 地址 |
| `CLASH_API_SECRET` | `poc-secret` | Clash API 密钥 |

## 快速开始

### 1. 编译运行

```bash
cd auth-service
go build -o auth-service
./auth-service
```

### 2. 使用环境变量

```bash
PORT=8080 \
ALLOWED_IDS_PATH=/path/to/allowed_ids.json \
CLASH_API_URL=http://127.0.0.1:9090 \
CLASH_API_SECRET=your-secret \
./auth-service
```

### 3. 测试 API

```bash
# 健康检查
curl http://localhost:8080/health

# 检查地址
curl "http://localhost:8080/v1/check?id=0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# 同步配置
curl -X POST http://localhost:8080/v1/sync
```

## UUID 算法验证

运行测试程序验证 Go 和 Python 的 UUID 生成一致性:

```bash
go run test_uuid.go
```

**预期输出:**
```
=== UUID 算法一致性测试 ===

client_a: 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  Go 生成:     d3507f8a-d4eb-541a-a231-929c6237eee5
  Python 期望: d3507f8a-d4eb-541a-a231-929c6237eee5
  结果: ✓ 一致

=== 所有测试通过 ===
```

## 技术实现

### UUID v5 派生算法

```go
// 使用 NAMESPACE_DNS: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
// SHA-1(namespace_bytes + lowercase(evm_address))
// 设置版本位 (5) 和变体位
func evmToUUID(evmAddress string) string {
    namespace := []byte{0x6b, 0xa7, 0xb8, 0x10, ...}
    h := sha1.New()
    h.Write(namespace)
    h.Write([]byte(strings.ToLower(evmAddress)))
    hash := h.Sum(nil)
    hash[6] = (hash[6] & 0x0f) | 0x50  // version 5
    hash[8] = (hash[8] & 0x3f) | 0x80  // variant
    return formatUUID(hash)
}
```

### Clash API 集成

使用 `PUT /configs?force=false` 实现 graceful reload:
- 新配置立即生效
- 已有连接不中断
- reload 时间 < 100ms

## 文件结构

```
auth-service/
├── main.go          # 主服务代码
├── test_uuid.go     # UUID 一致性测试
├── go.mod           # Go 模块配置
└── README.md        # 本文档
```
