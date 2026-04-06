# Phase 3 多服务器流量汇总测试手册

## 概述

本手册指导如何测试和验证多 Xray 服务器的流量汇总功能。

## 测试环境

- **Server 1**: API 端口 10085, VLESS 端口 10086
- **Server 2**: API 端口 10086, VLESS 端口 10087
- **Client 1**: 连接到 Server 1 (代理端口 10801)
- **Client 3**: 连接到 Server 2 (代理端口 10803)

## 测试步骤

### 步骤 1: 启动多服务器环境

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase3

# 启动所有服务（包括两个 Xray 服务器）
./start_multi_xray.sh
```

**预期输出**:
```
✅ 所有服务启动成功

服务地址：
  - Auth Service:  http://localhost:8080
  - Xray Server 1: 127.0.0.1:10086 (API: 10085)
  - Xray Server 2: 127.0.0.1:10087 (API: 10086)
  - Sing-box 1:    127.0.0.1:10801 (→ Server 1)
  - Sing-box 3:    127.0.0.1:10803 (→ Server 2)
```

### 步骤 2: 验证 Web 界面

访问 http://localhost:8080

**预期界面**:
- 表头应该显示: Email | UUID | Status | Server-1 | Server-2 | Total Traffic | Actions
- 两个用户的所有流量初始值应该为 0 B

### 步骤 3: 为 Server 1 生成流量

```bash
./generate_traffic.sh -c1 -n 10
```

**预期结果**:
- 下载成功 10 次，总流量约 515 KB
- 等待 5-8 秒后刷新浏览器
- Server-1 列应该显示约 517 KB
- Server-2 列应该显示 0 B
- Total Traffic 列应该显示约 517 KB

### 步骤 4: 为 Server 2 生成流量

```bash
./generate_traffic_server2.sh 10
```

**预期结果**:
- 下载成功 10 次，总流量约 515 KB
- 等待 5-8 秒后刷新浏览器
- Server-1 列应该显示约 517 KB (不变)
- Server-2 列应该显示约 517 KB (新增)
- Total Traffic 列应该显示约 1.01 MB (517 + 517)

### 步骤 5: 验证流量持久化

```bash
# 查看 users.json 文件
cat users.json | jq '.users[0].servers'
```

**预期输出**:
```json
{
  "Server-1": {
    "total_uplink": 830,
    "total_downlink": 529946,
    "last_xray_uplink": 830,
    "last_xray_downlink": 529946
  },
  "Server-2": {
    "total_uplink": 830,
    "total_downlink": 529946,
    "last_xray_uplink": 830,
    "last_xray_downlink": 529946
  }
}
```

### 步骤 6: 测试 Xray 重启后的流量保留

```bash
# 重启所有服务
./stop_all.sh
sleep 2
./start_multi_xray.sh

# 等待 10 秒让定时任务运行
sleep 10

# 查看流量是否保留
cat users.json | jq '.users[0] | {total_uplink, total_downlink}'
```

**预期结果**:
- total_uplink 和 total_downlink 应该保留重启前的值
- 即使 Xray 重启，历史流量也不会丢失

### 步骤 7: 继续生成流量验证累加

```bash
# 为 Server 1 再生成 10 次流量
./generate_traffic.sh -c1 -n 10

# 等待 8 秒
sleep 8

# 查看流量累加
cat users.json | jq '.users[0].servers["Server-1"]'
```

**预期结果**:
- Server-1 的流量应该在原有基础上增加约 517 KB
- Total Traffic 应该正确累加

## 验证检查清单

完成以下所有测试项后，多服务器流量汇总功能验证通过：

- [ ] 两个 Xray 服务器成功启动
- [ ] Web 界面显示两个服务器的流量列
- [ ] Server 1 流量统计正常
- [ ] Server 2 流量统计正常
- [ ] 总流量正确汇总 (Server 1 + Server 2)
- [ ] 流量数据持久化到 users.json
- [ ] 每个服务器的流量独立记录
- [ ] Xray 重启后流量不丢失
- [ ] 流量持续累加正确
- [ ] Restrict 按钮在所有服务器上生效

## 预期界面效果

```
┌──────────────┬──────────┬─────────┬────────────┬────────────┬────────────┬─────────┐
│ Email        │ UUID     │ Status  │ Server-1   │ Server-2   │ Total      │ Actions │
├──────────────┼──────────┼─────────┼────────────┼────────────┼────────────┼─────────┤
│ 0x1234...    │ 11111... │ Enabled │ ↑ 1.62 KB  │ ↑ 1.62 KB  │ ↑ 3.24 KB  │ [Dis]   │
│              │          │         │ ↓ 517 KB   │ ↓ 517 KB   │ ↓ 1.01 MB  │ [Res]   │
└──────────────┴──────────┴─────────┴────────────┴────────────┴────────────┴─────────┘
```

## 故障排查

### 问题 1: Server 2 无法启动

**可能原因**: 端口冲突

**解决方法**:
```bash
# 检查端口占用
lsof -i :10086
lsof -i :10087

# 清理端口
./stop_all.sh
```

### 问题 2: Server 2 流量显示为 0

**可能原因**: Client 3 未连接到 Server 2

**解决方法**:
```bash
# 检查 Sing-box Client 3 是否运行
ps aux | grep sing-box

# 检查日志
tail -20 logs/singbox3.log

# 手动测试连接
curl -x http://127.0.0.1:10803 http://httpbin.org/ip
```

### 问题 3: 总流量计算错误

**可能原因**: 定时任务未运行或计算逻辑错误

**解决方法**:
```bash
# 检查 Auth Service 日志
tail -50 logs/auth-service.log

# 手动查询两个服务器的流量
xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>"
xray api statsquery --server=127.0.0.1:10086 --pattern="user>>>"
```

## 清理环境

测试完成后，停止所有服务：

```bash
./stop_all.sh
```

## 下一步扩展

1. **添加更多服务器** - 支持 3 个或更多 Xray 服务器
2. **服务器健康检查** - 检测服务器是否在线
3. **流量配额管理** - 为每个用户设置总流量限制
4. **按服务器限制** - 允许禁用用户在特定服务器上的访问
5. **流量图表** - 可视化每个服务器的流量趋势

## 总结

多服务器流量汇总功能实现了：
- ✅ 支持多个 Xray 服务器
- ✅ 独立统计每个服务器的流量
- ✅ 自动汇总所有服务器的总流量
- ✅ 流量持久化，重启不丢失
- ✅ Web 界面清晰显示每个服务器的流量
- ✅ 用户可以在不同服务器之间切换使用
