# 流量收集服务

流量收集服务定期从 Hysteria2 节点采集用户流量数据,并聚合存储到 JSON 文件中。

## 功能特性

- 定期采集多个 Hysteria2 节点的流量数据
- 按用户聚合流量统计 (上传/下载)
- 按节点记录流量明细
- JSON 文件持久化存储
- 实时日志输出

## 目录结构

```
traffic-collector/
├── main.go              # 主程序
├── collector.go         # 流量采集器
├── storage.go           # 数据存储层
├── go.mod               # Go 模块文件
├── traffic-collector    # 编译后的可执行文件
├── start.sh             # 启动脚本
├── stop.sh              # 停止脚本
└── logs/                # 日志目录
```

## 使用方法

### 启动服务

```bash
cd traffic-collector
./start.sh
```

服务将在后台运行,日志输出到 `logs/collector.log`。

### 停止服务

```bash
./stop.sh
```

### 手动运行 (前台)

```bash
./traffic-collector
```

可选参数:
- `-data`: 数据文件路径 (默认: `../data/traffic.json`)
- `-interval`: 采集间隔 (默认: `10s`)

示例:
```bash
./traffic-collector -data=/path/to/data.json -interval=30s
```

## 配置

节点配置在 [main.go:18-29](main.go#L18-L29) 中:

```go
nodes := []Node{
    {
        NodeID:        "node1",
        TrafficAPIURL: "http://127.0.0.1:9443",
        Secret:        "stats_secret_node1",
    },
    {
        NodeID:        "node2",
        TrafficAPIURL: "http://127.0.0.1:9444",
        Secret:        "stats_secret_node2",
    },
}
```

## 数据格式

流量数据存储在 JSON 文件中:

```json
{
  "users": {
    "user1": {
      "user_id": "user1",
      "total_tx": 1048576,
      "total_rx": 2097152,
      "by_node": {
        "node1": 1572864,
        "node2": 1572864
      },
      "last_updated": "2026-03-31T15:30:00Z"
    }
  }
}
```

字段说明:
- `total_tx`: 总上传字节数
- `total_rx`: 总下载字节数
- `by_node`: 各节点的流量总和 (上传+下载)
- `last_updated`: 最后更新时间

## 工作原理

1. **定时采集**: 每 10 秒 (可配置) 执行一次采集周期
2. **并发请求**: 同时向所有节点发送 `GET /traffic?clear=true` 请求
3. **数据聚合**: 将各节点返回的流量数据按用户 ID 聚合
4. **持久化**: 更新 JSON 文件,累加流量数据
5. **日志输出**: 记录采集过程和统计信息

## API 调用

服务调用 Hysteria2 节点的流量统计 API:

```bash
GET http://127.0.0.1:9443/traffic?clear=true
Headers:
  Authorization: stats_secret_node1
```

`clear=true` 参数表示获取增量流量并清零节点的计数器,避免重复统计。

## 日志示例

```
2026/03/31 15:57:40 Traffic collector started
2026/03/31 15:57:40 Data file: ../data/traffic.json
2026/03/31 15:57:40 Collection interval: 10s
2026/03/31 15:57:40 Monitoring nodes:
2026/03/31 15:57:40   - node1: http://127.0.0.1:9443
2026/03/31 15:57:40   - node2: http://127.0.0.1:9444
2026/03/31 15:57:40 
2026/03/31 15:57:40 ========================================
2026/03/31 15:57:40 Starting traffic collection cycle
2026/03/31 15:57:40 ========================================
2026/03/31 15:57:40 Collecting from node: node1
2026/03/31 15:57:40 Recorded traffic for user user1 on node node1: tx=524288, rx=1048576
2026/03/31 15:57:40 Collecting from node: node2
2026/03/31 15:57:40 Recorded traffic for user user1 on node node2: tx=262144, rx=524288
2026/03/31 15:57:40 Collection completed, updated 2 user records
2026/03/31 15:57:40 User traffic statistics:
2026/03/31 15:57:40   - user1: tx=786432, rx=1572864, total=2359296 bytes
2026/03/31 15:57:40     - node node1: 1572864 bytes
2026/03/31 15:57:40     - node node2: 786432 bytes
```

## 故障排查

### 服务无法启动

1. 检查端口是否可访问:
   ```bash
   curl -H "Authorization: stats_secret_node1" http://127.0.0.1:9443/traffic
   ```

2. 检查节点是否运行:
   ```bash
   ps aux | grep hysteria2
   ```

### 无流量数据

- 确认有客户端连接到节点
- 检查节点的流量统计 API 是否返回数据
- 查看日志: `tail -f logs/collector.log`

### 数据文件损坏

如果 JSON 文件损坏,删除后服务会自动创建新文件:
```bash
rm ../data/traffic.json
```

## 开发

### 重新编译

```bash
go build -o traffic-collector
```

### 运行测试

```bash
go test ./...
```

## 相关文档

- [Hysteria2 节点 README](../README.md)
- [预验证开发计划](../../预验证开发计划.md)
- [TASK-001 完成报告](../../tasks/TASK-001-完成报告.md)
