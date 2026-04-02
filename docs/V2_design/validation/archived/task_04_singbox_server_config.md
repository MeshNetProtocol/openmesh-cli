---
task_id: 04
task_name: 配置 sing-box 服务端
priority: medium
dependencies: [03]
status: pending
---

# 任务：配置 sing-box 服务端

## 目标
创建 sing-box 服务端配置模板，由 Auth Service 动态生成实际配置。

## 配置要点

### VMess Inbound
- 监听端口：10086
- 监听地址：0.0.0.0（接受所有来源）
- 用户列表：由 Auth Service 动态生成
- 每个用户的 `name` 字段携带 EVM 地址（便于日志分析）

### Clash API（关键新增）
```json
"experimental": {
  "clash_api": {
    "external_controller": "127.0.0.1:9090",
    "secret": "poc-secret"
  }
}
```

**环境差异：**
| 环境 | external_controller | secret |
|------|---------------------|--------|
| POC（本机） | 127.0.0.1:9090 | poc-secret |
| 生产（远程） | 0.0.0.0:9090 | 强随机字符串 |

### Direct Outbound
- 类型：direct
- 标签：direct
- 直接转发流量到目标

## 启动流程
1. Auth Service 启动
2. 调用 `POST /v1/sync` 生成初始配置
3. 启动 sing-box：`sing-box run -c singbox-server/config.json`
4. Clash API 在 127.0.0.1:9090 可用
5. 后续所有配置更新通过 Clash API 推送，无需重启

## 验证标准
- [ ] sing-box 成功启动并监听 10086 端口
- [ ] Clash API 在 9090 端口可访问
- [ ] 接受 Client A 的 VMess 连接
- [ ] 拒绝 Client B 的 VMess 连接（初始状态）
- [ ] 日志中可见 EVM 地址（通过 name 字段）

## 文件位置
**代码输出目录：** `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code`

具体路径：`code/singbox-server/config.json`（由 Auth Service 生成）

## 注意事项
- 首次启动前必须先调用 `/v1/sync` 生成配置
- 配置文件由 Auth Service 完全控制，不应手动编辑
- Clash API secret 在生产环境必须使用强随机字符串
