# Phase 3 快速开始指南

## 一键启动测试

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase3

# 1. 编译 Auth Service
cd auth-service && go build -o auth-service && cd ..

# 2. 启动所有服务
./start_all.sh

# 3. 打开浏览器查看流量统计
open http://localhost:8080

# 4. 生成流量测试（使用流量生成脚本）
./generate_traffic.sh

# 或者为 Client 1 下载 20 次图片
./generate_traffic.sh -c1 -n 20

# 或者为两个客户端都生成流量
./generate_traffic.sh -c1 -c2

# 5. 停止所有服务
./stop_all.sh
```

## 流量生成工具

`generate_traffic.sh` 脚本通过下载图片来生成真实流量。

### 使用方法

```bash
# 为 Client 1 生成流量（默认）
./generate_traffic.sh

# 为 Client 1 下载 20 次图片
./generate_traffic.sh -c1 -n 20

# 为 Client 2 生成流量
./generate_traffic.sh -c2

# 为两个客户端都生成流量
./generate_traffic.sh -c1 -c2

# 查看帮助
./generate_traffic.sh -h
```

### 预期输出

```
使用 Client 1 (SOCKS5 代理端口 1080) 生成流量...
  下载图片 10 次...

  [1/10] ✅ 下载成功 (HTTP 200, 245678 bytes)
  [2/10] ✅ 下载成功 (HTTP 200, 243521 bytes)
  ...
  
  统计: 成功 10, 失败 0
```

## 预期效果

访问 http://localhost:8080 后，你会看到：

- 2 个用户的实时流量统计（每 3 秒自动刷新）
- 流量以人类可读格式显示（B/KB/MB/GB）
- 每个启用用户旁边有 "Disable" 和 "Restrict" 两个按钮
- 点击 "Restrict" 按钮可立即停止用户服务

## 详细文档

- [完整测试手册](TEST_MANUAL.md) - 包含 10 个详细测试场景
- [README](README.md) - 功能说明和技术细节
- [POC 文档](../phase3_traffic_stats_poc.md) - 实现方案

## 核心改进

相比 Phase 2，Phase 3 新增：
- ✅ 实时流量统计（上行/下行/总计）
- ✅ 流量可视化界面
- ✅ 快速限制按钮
- ✅ 自动刷新（3 秒间隔）
- ✅ 流量生成工具（下载图片生成真实流量）
