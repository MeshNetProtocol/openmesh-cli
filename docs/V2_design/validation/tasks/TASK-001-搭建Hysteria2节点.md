# TASK-001: 搭建 Hysteria2 节点

> **任务编号**: TASK-001  
> **所属原型**: 原型 1 - 流量统计验证  
> **任务类型**: 基础设施搭建  
> **优先级**: P0 (阻塞后续任务)  
> **预估工时**: 2-3 小时  
> **状态**: 待开始

---

## 1. 任务目标

搭建 2 个独立的 Hysteria2 节点 (node1, node2),启用流量统计 API,为后续的流量收集和统计验证提供基础设施。

## 2. 背景与上下文

### 2.1 为什么需要这个任务

- 流量统计验证需要真实的 Hysteria2 节点来产生流量数据
- 需要验证多节点场景下的流量统计准确性
- 需要测试节点切换时流量数据的累加逻辑

### 2.2 技术背景

**Hysteria2 协议**:
- 基于 QUIC 的高性能 VPN 协议
- 支持流量统计 API
- 本项目已有 Hysteria2 相关代码和配置

**参考资源**:
- 项目根目录下有 Hysteria2 源代码
- `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/Hysteria2_Validation` 目录下有现成的配置示例

### 2.3 架构位置

```
┌─────────────────────────────────────┐
│  sing-box 客户端                     │
│  (用户使用)                          │
└──────────┬──────────────────────────┘
           │ VPN 连接
           ▼
┌─────────────────────────────────────┐
│  Hysteria2 节点 (本任务)             │
│  ├── node1 (端口 8443)               │
│  └── node2 (端口 8444)               │
│                                     │
│  功能:                               │
│  - VPN 流量转发                      │
│  - 流量统计 API                      │
│  - 用户认证                          │
└──────────┬──────────────────────────┘
           │ 流量上报
           ▼
┌─────────────────────────────────────┐
│  流量收集服务 (后续任务)             │
└─────────────────────────────────────┘
```

---

## 3. 详细需求

### 3.1 功能需求

**节点 1 (node1)**:
- 监听端口: `8443`
- 协议: Hysteria2
- 认证方式: 密码认证 (用户名/密码)
- 流量统计: 启用 Traffic Stats API
- 日志级别: info

**节点 2 (node2)**:
- 监听端口: `8444`
- 协议: Hysteria2
- 认证方式: 密码认证 (用户名/密码)
- 流量统计: 启用 Traffic Stats API
- 日志级别: info

**流量统计 API 要求**:
- 提供 HTTP API 查询用户流量
- 支持按用户 ID 查询
- 返回上传/下载字节数
- 实时更新 (延迟 < 1 分钟)

### 3.2 非功能需求

- 节点可独立启动和停止
- 配置文件清晰易读
- 日志输出便于调试
- 本地运行,无需外部依赖

---

## 4. 实现方案

### 4.1 目录结构

```
/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/prototype-1-traffic/
├── hysteria2-node1/
│   ├── config.yaml           # node1 配置文件
│   ├── start.sh              # 启动脚本
│   ├── stop.sh               # 停止脚本
│   └── logs/                 # 日志目录
├── hysteria2-node2/
│   ├── config.yaml           # node2 配置文件
│   ├── start.sh              # 启动脚本
│   ├── stop.sh               # 停止脚本
│   └── logs/                 # 日志目录
└── README.md                 # 节点使用说明
```

### 4.2 配置文件设计

**node1 配置 (config.yaml)**:
```yaml
listen: :8443

tls:
  cert: /path/to/cert.pem
  key: /path/to/key.pem

auth:
  type: password
  password: test_password_node1

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true

bandwidth:
  up: 100 mbps
  down: 100 mbps

# 流量统计 API
trafficStats:
  listen: :9443
  secret: stats_secret_node1

log:
  level: info
  file: ./logs/hysteria2.log
```

**node2 配置 (config.yaml)**:
```yaml
listen: :8444

tls:
  cert: /path/to/cert.pem
  key: /path/to/key.pem

auth:
  type: password
  password: test_password_node2

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true

bandwidth:
  up: 100 mbps
  down: 100 mbps

# 流量统计 API
trafficStats:
  listen: :9444
  secret: stats_secret_node2

log:
  level: info
  file: ./logs/hysteria2.log
```

### 4.3 启动脚本设计

**start.sh**:
```bash
#!/bin/bash

# 检查 Hysteria2 可执行文件
if ! command -v hysteria2 &> /dev/null; then
    echo "Error: hysteria2 not found"
    exit 1
fi

# 创建日志目录
mkdir -p logs

# 启动节点
hysteria2 server -c config.yaml &

# 保存 PID
echo $! > hysteria2.pid

echo "Hysteria2 node started (PID: $!)"
```

**stop.sh**:
```bash
#!/bin/bash

if [ -f hysteria2.pid ]; then
    PID=$(cat hysteria2.pid)
    kill $PID
    rm hysteria2.pid
    echo "Hysteria2 node stopped (PID: $PID)"
else
    echo "No PID file found"
fi
```

### 4.4 流量统计 API 接口

**查询用户流量**:
```
GET http://localhost:9443/traffic/{user_id}
Headers:
  Authorization: Bearer stats_secret_node1

Response:
{
  "user_id": "user1",
  "tx": 1048576,      // 上传字节数
  "rx": 2097152,      // 下载字节数
  "start_time": "2026-03-31T10:00:00Z"
}
```

---

## 5. 实现步骤

### 步骤 1: 参考现有配置
- 阅读 `Hysteria2_Validation` 目录下的配置文件
- 了解 Hysteria2 的配置格式和选项
- 确认流量统计 API 的配置方式

### 步骤 2: 生成 TLS 证书
- 使用 openssl 生成自签名证书
- 证书用于 Hysteria2 的 TLS 加密
- 两个节点可共用同一证书

### 步骤 3: 创建目录结构
- 创建 `prototype-1-traffic` 目录
- 创建 `hysteria2-node1` 和 `hysteria2-node2` 子目录
- 创建日志目录

### 步骤 4: 编写配置文件
- 编写 node1 的 `config.yaml`
- 编写 node2 的 `config.yaml`
- 确保端口不冲突

### 步骤 5: 编写启动/停止脚本
- 编写 `start.sh` 和 `stop.sh`
- 添加执行权限 (`chmod +x`)
- 测试脚本可用性

### 步骤 6: 启动节点并验证
- 启动 node1 和 node2
- 检查进程是否运行
- 检查日志是否正常
- 测试流量统计 API 是否可访问

### 步骤 7: 编写 README
- 记录节点配置说明
- 记录启动/停止方法
- 记录流量统计 API 使用方法

---

## 6. 验收标准

### 6.1 功能验收

- [ ] node1 可正常启动,监听 8443 端口
- [ ] node2 可正常启动,监听 8444 端口
- [ ] 两个节点可同时运行,互不干扰
- [ ] 流量统计 API 可访问 (node1: 9443, node2: 9444)
- [ ] 可通过 API 查询用户流量 (即使流量为 0)
- [ ] 日志文件正常生成
- [ ] 启动/停止脚本工作正常

### 6.2 质量验收

- [ ] 配置文件格式正确,无语法错误
- [ ] 脚本有错误处理
- [ ] README 文档完整清晰
- [ ] 目录结构清晰,易于理解

### 6.3 测试方法

**测试 1: 启动节点**
```bash
cd prototype-1-traffic/hysteria2-node1
./start.sh
# 预期: 输出 "Hysteria2 node started (PID: xxx)"
```

**测试 2: 检查进程**
```bash
ps aux | grep hysteria2
# 预期: 看到 2 个 hysteria2 进程
```

**测试 3: 检查端口**
```bash
lsof -i :8443
lsof -i :8444
# 预期: 端口被 hysteria2 占用
```

**测试 4: 测试流量统计 API**
```bash
curl -H "Authorization: Bearer stats_secret_node1" \
     http://localhost:9443/traffic/test_user
# 预期: 返回 JSON 格式的流量数据
```

**测试 5: 停止节点**
```bash
./stop.sh
# 预期: 输出 "Hysteria2 node stopped (PID: xxx)"
```

---

## 7. 依赖与前置条件

### 7.1 依赖项

- Hysteria2 可执行文件 (需要编译或下载)
- OpenSSL (用于生成证书)
- curl (用于测试 API)

### 7.2 前置条件

- 端口 8443, 8444, 9443, 9444 未被占用
- 有权限监听这些端口
- 有权限创建文件和目录

---

## 8. 风险与注意事项

### 8.1 技术风险

**风险 1: Hysteria2 版本兼容性**
- 描述: 不同版本的 Hysteria2 配置格式可能不同
- 缓解: 参考 `Hysteria2_Validation` 目录下的配置,使用相同版本

**风险 2: 流量统计 API 配置**
- 描述: 流量统计 API 的配置方式可能不明确
- 缓解: 阅读 Hysteria2 源代码确认配置格式

**风险 3: TLS 证书问题**
- 描述: 自签名证书可能导致客户端连接失败
- 缓解: 客户端配置跳过证书验证 (仅测试环境)

### 8.2 注意事项

- 本任务仅搭建节点,不涉及客户端连接测试
- 流量统计 API 的具体实现需要查看 Hysteria2 源代码确认
- 如果 Hysteria2 不支持内置流量统计 API,需要调整方案

---

## 9. 参考资料

### 9.1 项目内资源

- Hysteria2 源代码: `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/hysteria` (如果存在)
- 现有配置: `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/Hysteria2_Validation/config/`
- 现有原型: `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/Hysteria2_Validation/prototype/`

### 9.2 外部资源

- Hysteria2 官方文档: https://v2.hysteria.network/
- Hysteria2 GitHub: https://github.com/apernet/hysteria

---

## 10. 后续任务

完成本任务后,可以进行:
- **TASK-002**: 实现流量收集服务 (接收节点上报)
- **TASK-005**: 配置 sing-box 客户端 (连接节点测试)

---

## 11. 任务日志

| 时间 | 操作 | 备注 |
|------|------|------|
| 2026-03-31 | 创建任务卡 | 初始版本 |

---

**任务负责人**: AI 架构师 + 开发工程师  
**审核人**: 项目负责人  
**创建时间**: 2026-03-31  
**最后更新**: 2026-03-31
