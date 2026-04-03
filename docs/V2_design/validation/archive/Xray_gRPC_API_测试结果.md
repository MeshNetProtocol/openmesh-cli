# Xray gRPC API 测试结果

## 测试目标

验证 Xray 的 gRPC API `RemoveUser` 操作是否能阻止新连接。

## 关键发现

### 1. Xray gRPC API 可以正常工作

使用 Python 的 `xray-rpc` 包可以成功调用 Xray 的 gRPC API:
- ✅ `AddUser` 操作成功
- ✅ `RemoveUser` 操作成功

### 2. RemoveUser 的行为特性

**重要发现:**
- `RemoveUser` 调用成功后,**已有的 TCP 连接不会被断开**
- 但 `RemoveUser` **应该能阻止新连接**

这是 VMess 协议的设计特性,不是 bug。

### 3. 相关 GitHub Issues

这是一个已知的行为:
- [Issue #2894 - GRPC删除用户后,依然可用](https://github.com/v2ray/v2ray-core/issues/2894)
- [Issue #2497 - 通过API删除用户后立即强制关闭已连接的会话](https://github.com/v2ray/v2ray-core/issues/2497)

## Xray 拒绝连接的情况

根据 VMess 协议文档,Xray 在以下情况会拒绝连接:

1. **UUID 不匹配** - 客户端的 UUID 不在服务端用户列表中
2. **时间同步问题** - 服务端和客户端的 UTC 时间差超过 120 秒
3. **AEAD 认证失败** - 现代 Xray 默认强制使用 VMessAEAD 认证

## 核心结论

**如果 RemoveUser 能够阻止新连接,就已经满足我们的需求。**

已有连接不会被断开是可以接受的,因为:
- 用户的会话通常不会持续很长时间
- 新连接会被立即拒绝
- 不需要重启 Xray 服务端

## 验证结果

### ✅ 测试通过（2026-04-03）

**测试方法：**
使用 VLESS 协议进行验证测试（VMess 协议存在 AEAD 认证问题）

**测试步骤：**
1. 启动 Xray 服务端（带测试用户）
2. 客户端连接测试 → ✅ 连接成功
3. 通过 gRPC API 删除用户：`xray api rmu -tag=vless-in "test-validation@example.com"`
4. 客户端重新连接测试 → ✅ 连接被拒绝

**核心结论：**
- ✅ **RemoveUser 操作能够成功阻止新连接**
- ✅ 无需重启 Xray 服务端即可生效
- ✅ 满足动态用户管理的需求

**测试脚本：**
- [run_validation.sh](run_validation.sh) - 一键自动化测试脚本
- [xray_server_vless.json](xray_server_vless.json) - VLESS 服务端配置
- [vless_client.json](vless_client.json) - VLESS 客户端配置

**运行测试：**
```bash
cd docs/V2_design/validation
./run_validation.sh
```

## 使用方法

```bash
# 添加用户
python3 xray_api.py add client-a@test.com d3507f8a-d4eb-541a-a231-929c6237eee5

# 删除用户
python3 xray_api.py remove client-a@test.com
```

## 参考资料

- [VMess Protocol - Xray](https://xtls.github.io/en/development/protocols/vmess.html)
- [V2Ray 的认证和加密方式简介](https://github.com/v2ray/v2ray-core/issues/30)
- [VMessAEAD 强制执行](https://github.com/233boy/v2ray/issues/812)
