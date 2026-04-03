# Xray RemoveUser 验证测试

## 测试目的

验证 Xray 的 gRPC API `RemoveUser` 操作是否能阻止新连接。

## 前提条件

### 1. 安装 Xray

```bash
# macOS
brew install xray

# 或从官网下载
# https://github.com/XTLS/Xray-core/releases
```

### 2. 配置 Xray 服务端

创建服务端配置文件 `xray_server.json`:

```json
{
  "log": {
    "loglevel": "info"
  },
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "StatsService"
    ]
  },
  "stats": {},
  "policy": {
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "vmess-in",
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": []
      }
    },
    {
      "tag": "api",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  }
}
```

### 3. 启动 Xray 服务端

```bash
xray -c xray_server.json
```

服务端会监听：
- VMess 端口: `10086`
- gRPC API 端口: `10085`

## 运行测试

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation

# 运行自动化测试
./test_xray_remove_user.sh
```

## 测试流程

测试脚本会自动执行以下步骤：

1. **检查环境** - 验证 Xray 服务端是否运行
2. **添加用户** - 使用 `xray api adi` 添加测试用户
3. **测试初始连接** - 启动客户端并通过代理访问网站（预期：成功）
4. **删除用户** - 使用 `xray api rmi` 删除测试用户
5. **等待连接关闭** - 等待 5 秒确保所有连接关闭
6. **测试新连接** - 重新启动客户端并尝试连接（预期：失败）

## 预期结果

如果测试通过，说明：
- ✅ RemoveUser 操作能够成功阻止新连接
- ✅ 已有连接不会被断开（这是预期行为）
- ✅ 满足需求：无需重启服务端即可禁用用户

## 手动测试

如果需要手动测试，可以使用以下命令：

```bash
# 添加用户
xray api adi --server=127.0.0.1:10085 vmess-in test@example.com <uuid>

# 删除用户
xray api rmi --server=127.0.0.1:10085 vmess-in test@example.com

# 查看用户列表
xray api stats --server=127.0.0.1:10085
```

## 故障排查

### 测试失败：初始连接应该成功但失败了

可能原因：
- Xray 服务端未运行
- 服务端配置不正确
- 防火墙阻止连接
- 网络连接问题

解决方法：
```bash
# 检查 Xray 是否运行
ps aux | grep xray

# 检查端口是否监听
lsof -i :10086
lsof -i :10085

# 查看 Xray 日志
# 检查服务端终端输出
```

### 测试失败：RemoveUser 后新连接仍然成功

这意味着 RemoveUser 没有阻止新连接，可能需要：
- 检查 Xray 版本是否支持动态用户管理
- 验证 gRPC API 配置是否正确
- 考虑使用其他方法（如重启服务端）

## 参考资料

- [Xray 官方文档](https://xtls.github.io/)
- [VMess 协议说明](https://xtls.github.io/en/development/protocols/vmess.html)
- [Xray API 使用指南](https://xtls.github.io/en/config/api.html)
