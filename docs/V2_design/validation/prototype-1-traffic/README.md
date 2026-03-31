# Hysteria2 双节点测试环境

本目录包含两个独立的 Hysteria2 节点,用于流量统计验证测试。

## 目录结构

```
prototype-1-traffic/
├── hysteria2                    # Hysteria2 可执行文件
├── server.crt                   # TLS 证书
├── server.key                   # TLS 私钥
├── hysteria2-node1/             # 节点 1
│   ├── config.yaml              # 配置文件
│   ├── start.sh                 # 启动脚本
│   ├── stop.sh                  # 停止脚本
│   └── logs/                    # 日志目录
├── hysteria2-node2/             # 节点 2
│   ├── config.yaml              # 配置文件
│   ├── start.sh                 # 启动脚本
│   ├── stop.sh                  # 停止脚本
│   └── logs/                    # 日志目录
└── README.md                    # 本文件
```

## 节点配置

### Node1
- **监听端口**: 8443
- **流量统计 API**: 127.0.0.1:9443
- **认证密码**: test_password_node1
- **API Secret**: stats_secret_node1

### Node2
- **监听端口**: 8444
- **流量统计 API**: 127.0.0.1:9444
- **认证密码**: test_password_node2
- **API Secret**: stats_secret_node2

## 使用方法

### 启动节点

```bash
# 启动 node1
cd hysteria2-node1
./start.sh

# 启动 node2
cd hysteria2-node2
./start.sh
```

### 停止节点

```bash
# 停止 node1
cd hysteria2-node1
./stop.sh

# 停止 node2
cd hysteria2-node2
./stop.sh
```

### 检查节点状态

```bash
# 检查进程
ps aux | grep hysteria2

# 检查端口
lsof -i :8443
lsof -i :8444
lsof -i :9443
lsof -i :9444
```

## 流量统计 API

### 查询所有用户流量

```bash
# Node1
curl -H "Authorization: stats_secret_node1" http://127.0.0.1:9443/traffic

# Node2
curl -H "Authorization: stats_secret_node2" http://127.0.0.1:9444/traffic
```

**响应示例**:
```json
{
  "user1": {
    "tx": 1048576,
    "rx": 2097152
  },
  "user2": {
    "tx": 524288,
    "rx": 1048576
  }
}
```

### 查询在线用户

```bash
# Node1
curl -H "Authorization: stats_secret_node1" http://127.0.0.1:9443/online

# Node2
curl -H "Authorization: stats_secret_node2" http://127.0.0.1:9444/online
```

**响应示例**:
```json
{
  "user1": 2,
  "user2": 1
}
```

### 踢出用户

```bash
# Node1
curl -X POST -H "Authorization: stats_secret_node1" \
     -H "Content-Type: application/json" \
     -d '["user1", "user2"]' \
     http://127.0.0.1:9443/kick

# Node2
curl -X POST -H "Authorization: stats_secret_node2" \
     -H "Content-Type: application/json" \
     -d '["user1", "user2"]' \
     http://127.0.0.1:9444/kick
```

## 日志查看

```bash
# 查看 node1 日志
tail -f hysteria2-node1/logs/hysteria2.log
tail -f hysteria2-node1/logs/stdout.log

# 查看 node2 日志
tail -f hysteria2-node2/logs/hysteria2.log
tail -f hysteria2-node2/logs/stdout.log
```

## 注意事项

1. 两个节点使用相同的 TLS 证书(自签名证书)
2. 客户端连接时需要配置跳过证书验证(仅测试环境)
3. 流量统计 API 需要使用正确的 Authorization header
4. 节点使用密码认证方式,不需要外部认证服务

## 故障排查

### 节点启动失败

1. 检查端口是否被占用: `lsof -i :8443`
2. 检查日志: `cat hysteria2-node1/logs/stdout.log`
3. 检查证书文件是否存在: `ls -la server.crt server.key`

### API 返回 unauthorized

确保使用正确的 Authorization header:
```bash
# 正确方式
curl -H "Authorization: stats_secret_node1" http://127.0.0.1:9443/traffic

# 错误方式(不要使用 Bearer)
curl -H "Authorization: Bearer stats_secret_node1" http://127.0.0.1:9443/traffic
```

## 相关文档

- [任务卡 TASK-001](../tasks/TASK-001-搭建Hysteria2节点.md)
- [Hysteria2 官方文档](https://v2.hysteria.network/)
- [Hysteria2 验证计划](../Hysteria2_Validation/README.md)
