# Phase 2 验收指南

## 验收目标

验证 Sing-box 客户端 + Xray 服务端架构下，通过 Auth Service Web 界面实现动态用户管理（启用/禁用），无需重启服务端。

## 前提条件

1. 所有服务已启动（运行 `./start_all.sh`）
2. 两个 Sing-box 客户端正常运行
3. Auth Service Web 界面可访问

## 验收步骤

### 步骤 1: 验证初始状态

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase2

# 测试两个客户端的连接状态
./test_clients.sh
```

**预期结果：**
- ✅ Client 1 (user1@test.com): 本地和外网连接都成功
- ✅ Client 2 (user2@test.com): 本地和外网连接都成功

### 步骤 2: 禁用 user1

**方式 1: 通过 Web 界面**
1. 访问 http://localhost:8080
2. 找到 user1@test.com 行
3. 点击 "Disable" 按钮
4. 等待状态更新为 "✗ Disabled"

**方式 2: 通过 API**
```bash
curl -X POST http://localhost:8080/api/users/toggle \
  -H "Content-Type: application/json" \
  -d '{"email":"user1@test.com"}'
```

**验证禁用效果：**
```bash
./test_clients.sh
```

**预期结果：**
- ❌ Client 1 (user1@test.com): 外网连接失败
- ✅ Client 2 (user2@test.com): 外网连接成功

### 步骤 3: 重新启用 user1

**方式 1: 通过 Web 界面**
1. 访问 http://localhost:8080
2. 找到 user1@test.com 行
3. 点击 "Enable" 按钮
4. 等待状态更新为 "✓ Enabled"

**方式 2: 通过 API**
```bash
curl -X POST http://localhost:8080/api/users/toggle \
  -H "Content-Type: application/json" \
  -d '{"email":"user1@test.com"}'
```

**验证启用效果：**
```bash
./test_clients.sh
```

**预期结果：**
- ✅ Client 1 (user1@test.com): 本地和外网连接都成功
- ✅ Client 2 (user2@test.com): 本地和外网连接都成功

### 步骤 4: 验证无需重启

在整个测试过程中，验证以下服务**没有重启**：
```bash
# 查看 Xray 进程启动时间
ps -p $(lsof -ti :10086) -o etime=

# 查看 Sing-box 进程启动时间
ps -p $(lsof -ti :10801) -o etime=
ps -p $(lsof -ti :10802) -o etime=
```

**预期结果：**
- 所有进程的运行时间应该从测试开始就没有变化
- 证明启用/禁用操作无需重启任何服务

## 验收标准

### 必须通过的测试

- [x] **测试 1**: 初始状态下，两个客户端都能正常连接外网
- [x] **测试 2**: 禁用 user1 后，user1 无法连接外网，user2 仍然正常
- [x] **测试 3**: 重新启用 user1 后，两个客户端都能正常连接外网
- [x] **测试 4**: 整个过程中，Xray 和 Sing-box 进程没有重启

### 技术指标

- [x] **动态用户管理**: 通过 Web 界面或 API 实时控制用户访问权限
- [x] **无需重启**: 所有操作无需重启 Xray 服务端或客户端
- [x] **实时生效**: 禁用/启用操作立即生效（2-3 秒内）
- [x] **状态持久化**: 用户状态保存在 `users.json` 文件中

## 核心技术方案

### 问题与解决

**问题**: `xray api adu` 命令行工具不工作，返回 "Added 0 user(s)"

**解决方案**: 使用 [hiddify/xtlsapi](https://github.com/hiddify/xtlsapi) Python 库直接调用 Xray 的 gRPC API

### 实现细节

1. **添加用户**: 
   - 使用 `xtlsapi.XrayClient.add_client()` 方法
   - 通过 gRPC 调用 `HandlerService.AlterInbound`
   - 无需重启 Xray

2. **删除用户**:
   - 使用 `xray api rmu` 命令
   - 通过 gRPC 调用 `HandlerService.AlterInbound`
   - 无需重启 Xray

3. **Web 界面**:
   - Go HTTP 服务器（端口 8080）
   - 实时显示用户状态
   - 一键启用/禁用用户

## 验收结果

根据测试结果：

✅ **Phase 2 验收通过**

- 动态用户管理功能完全实现
- 无需重启服务端
- Web 界面实时控制
- 所有测试用例通过

## 已知限制

1. **用户状态同步**: 如果 Xray 重启，需要确保 `users.json` 中的状态与 Xray 中的实际状态一致
2. **错误处理**: 如果用户已存在，`xtlsapi` 会抛出 `EmailAlreadyExists` 异常，需要先删除再添加

## 下一步

Phase 2 验收通过后，可以考虑：
1. 将 Auth Service 集成到生产环境
2. 添加用户认证和权限管理
3. 实现批量用户管理功能
4. 添加用户流量统计和监控

## 参考资料

- [Phase 2 完整文档](README.md)
- [快速开始指南](QUICKSTART.md)
- [xtlsapi 库文档](https://github.com/hiddify/xtlsapi)
- [Xray API 文档](https://xtls.github.io/en/config/api.html)
