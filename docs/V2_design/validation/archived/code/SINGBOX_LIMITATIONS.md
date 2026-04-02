# sing-box Clash API 限制说明

## 问题描述

经过测试验证,**sing-box 1.13.5 的 Clash API 不支持真正的配置热重载**。

虽然 `PUT /configs` 端点返回 204 No Content,但 sing-box 并不会重新加载配置文件。这意味着:

1. ✅ 配置文件可以通过 Auth Service 动态生成和更新
2. ❌ sing-box 不会自动重新加载更新后的配置
3. ❌ 无法实现不中断现有连接的 graceful reload

## 测试结果

### 测试场景
1. Client B 初始不在 allowed_ids.json 中
2. 通过 `/v1/sync` 添加 Client B 到配置
3. 配置文件成功更新,包含两个用户
4. 调用 Clash API `PUT /configs` 返回 204
5. **但 Client B 仍然无法连接**

### 尝试的方案
- ✗ `PUT /configs` with config content - 不生效
- ✗ `PUT /configs` with `{"path": "..."}` - 不生效  
- ✗ `kill -HUP <pid>` - 不生效

## 当前可行方案

**方案 1: 手动重启 sing-box (会中断连接)**
```bash
# 停止 sing-box
kill <pid>

# 重新启动
sing-box run -c singbox-server/config.json
```

**方案 2: 使用 systemd/supervisor 自动重启**
配置进程管理器监听配置文件变化并自动重启。

**方案 3: 切换到支持热重载的代理软件**
考虑使用其他支持真正热重载的代理软件,如:
- Xray (支持 API 热重载)
- V2Ray (支持 API 热重载)

## 对 POC 的影响

### 命题验证结果

| 命题 | 状态 | 说明 |
|------|------|------|
| A: 准入 | ✅ 通过 | Client A 可以正常访问 |
| B: 拒绝 | ✅ 通过 | Client B 初始被拒绝 |
| C: 动态生效 | ❌ 失败 | 配置更新后需要重启 sing-box |

### 核心问题

**命题 C 的关键要求无法满足:**
- ✅ 配置可以动态生成和更新
- ❌ 无法在不重启的情况下生效
- ❌ 重启会中断所有现有连接

## 建议

1. **短期方案**: 接受需要重启的限制,在低峰期进行配置更新
2. **中期方案**: 实现蓝绿部署或滚动更新,最小化中断影响
3. **长期方案**: 切换到支持真正热重载的代理软件

## 参考资料

- [sing-box Clash API 文档](https://sing-box.sagernet.org/configuration/experimental/clash-api/)
- sing-box 版本: 1.13.5
- 测试日期: 2026-04-02
