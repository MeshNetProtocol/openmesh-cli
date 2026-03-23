# 统一记账服务 (Metering Service)

OpenMesh V2 流量统计验证的核心组件，用于管理用户流量配额、接收节点流量上报、统计汇总。

## 功能特性

- **用户管理** - 添加/查询/删除用户，预付费购买流量
- **流量上报** - 接收节点上报的流量统计，原子性扣减配额
- **流量桶管理** - 管理每个用户的流量配额（充值、消耗、查询）
- **流量控制** - 流量耗尽时返回阻断指令
- **统计查询** - 查询用户和节点的流量统计

## 快速启动

### 1. 安装依赖

```bash
cd metering-service
pip3 install -r requirements.txt
```

### 2. 启动服务

```bash
cd ..
./start-metering.sh
```

服务将在 `http://127.0.0.1:9000` 启动。

### 3. 测试服务

```bash
./test-metering.sh
```

### 4. 停止服务

```bash
./stop-metering.sh
```

## API 文档

### 用户管理

#### 添加用户（预付费购买流量）

```bash
POST /api/v1/users
Content-Type: application/json

{
  "user_id": "alice",
  "usdc_amount": 5.0,
  "price_rate": 100.0  # 1 USDC = 100MB
}
```

#### 查询用户流量

```bash
GET /api/v1/users/{user_id}
```

#### 删除用户

```bash
DELETE /api/v1/users/{user_id}
```

#### 充值流量

```bash
POST /api/v1/users/{user_id}/recharge
Content-Type: application/json

{
  "amount_mb": 40
}
```

### 流量上报

#### 上报流量统计

```bash
POST /api/v1/metering/report
Content-Type: application/json

{
  "node_id": "node_a",
  "user_id": "alice",
  "upload_bytes": 1048576,
  "download_bytes": 5242880
}
```

响应：
- `200` - 流量充足，继续服务
- `403` - 流量不足，阻断连接

### 统计查询

#### 查询所有用户统计

```bash
GET /api/v1/stats/users
```

#### 查询节点统计

```bash
GET /api/v1/stats/nodes
```

## 数据库

使用 SQLite 存储数据，数据库文件：`metering.db`

### 表结构

**users** - 用户流量表
- `user_id` - 用户 ID（主键）
- `provider_id` - 服务商 ID
- `total_quota` - 总配额（字节）
- `used_upload` - 已用上传（字节）
- `used_download` - 已用下载（字节）
- `remaining` - 剩余流量（字节）
- `price_rate` - 价格比率（1 USDC = X MB）
- `purchased_at` - 购买时间
- `updated_at` - 更新时间

**traffic_reports** - 流量上报记录表
- `id` - 自增 ID
- `node_id` - 节点 ID
- `user_id` - 用户 ID
- `upload_bytes` - 上传字节数
- `download_bytes` - 下载字节数
- `reported_at` - 上报时间

## 日志

日志文件：`logs/metering.log`

查看日志：
```bash
tail -f metering-service/logs/metering.log
```

## 测试示例

```bash
# 1. 添加用户 alice（购买 500MB）
curl -X POST http://127.0.0.1:9000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"user_id":"alice","usdc_amount":5.0,"price_rate":100.0}'

# 2. 查询用户
curl http://127.0.0.1:9000/api/v1/users/alice

# 3. 上报流量（6MB）
curl -X POST http://127.0.0.1:9000/api/v1/metering/report \
  -H "Content-Type: application/json" \
  -d '{"node_id":"node_a","user_id":"alice","upload_bytes":1048576,"download_bytes":5242880}'

# 4. 充值 40MB
curl -X POST http://127.0.0.1:9000/api/v1/users/alice/recharge \
  -H "Content-Type: application/json" \
  -d '{"amount_mb":40}'

# 5. 查询统计
curl http://127.0.0.1:9000/api/v1/stats/users
```

## 架构说明

记账服务是 OpenMesh V2 流量统计验证的核心组件：

```
┌─────────────┐     上报流量      ┌──────────────────┐
│ sing-box    │ ───────────────> │  Metering        │
│ 节点 A/B/C  │                   │  Service         │
└─────────────┘                   │  - 流量汇总      │
                                  │  - 配额管理      │
                                  │  - 流量控制      │
                                  └──────────────────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │  SQLite DB  │
                                    └─────────────┘
```

## 注意事项

- 当前为测试原型，使用 SQLite 单机数据库
- 生产环境需要考虑：
  - 使用 PostgreSQL 或 MySQL
  - 添加认证和授权
  - 实现分布式锁
  - 添加监控和告警
- 暂不实现 x402 支付验证

## 下一步

P0.4 将实现节点流量采集和上报功能，自动从 sing-box 读取流量统计并上报到记账服务。
