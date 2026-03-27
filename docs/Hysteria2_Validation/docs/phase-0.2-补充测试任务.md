# Phase 0.2 补充测试任务

**目标**: 完成 Phase 0.2 中因环境限制未完成的测试项

**执行者**: 新的 AI 实例

**前置条件**: Phase 0.1 环境已搭建完成，服务正常运行

---

## 一、任务背景

Phase 0.2 已完成核心验证：
- ✅ 流量统计准确度（100KB 文件，误差 0.24%）
- ✅ 增量采集功能（`?clear=true`）
- ✅ 上传下载分离统计
- ✅ API 性能（< 10ms）

但以下测试因环境限制未完成：
- ❌ 多文件大小测试（256KB, 512KB）
- ❌ 并发用户测试（3 个用户同时传输）

---

## 二、需要解决的问题

### 问题 1: 代理无法访问本地测试服务器

**现象**:
- 本地启动 HTTP 服务器（`python3 -m http.server 8888`）
- 通过代理访问 `http://localhost:8888/100kb.bin` 失败
- 直接访问（不通过代理）正常

**原因**:
- sing-box 可能有路由规则阻止访问 localhost
- 或者 Hysteria2 不转发本地流量

**解决方案**:
1. **方案 A**: 修改 sing-box 配置，允许代理访问 localhost
2. **方案 B**: 使用外部可访问的测试服务器（推荐）
3. **方案 C**: 在另一台机器上部署测试文件服务器

### 问题 2: 只有 1 个测试用户

**现象**:
- 认证 API 只配置了 3 个 token，但都映射到不同用户
- 无法测试多用户并发场景

**解决方案**:
- 配置多个测试用户的 token
- 启动多个 sing-box 客户端实例（不同端口）
- 或者修改认证 API 支持动态用户

---

## 三、具体任务

### 任务 1: 多文件大小测试

**目标**: 验证 256KB 和 512KB 文件的流量统计准确度

**步骤**:

1. **部署外部测试文件服务器**
   ```bash
   # 选项 A: 使用云服务器
   # 在云服务器上创建测试文件
   dd if=/dev/urandom of=/var/www/html/256kb.bin bs=1024 count=256
   dd if=/dev/urandom of=/var/www/html/512kb.bin bs=1024 count=512

   # 选项 B: 使用公共测试服务
   # 寻找可靠的文件下载测试服务（如 speed test 服务器）
   ```

2. **修改 sing-box 配置（如果需要）**
   ```json
   {
     "route": {
       "rules": [
         {
           "domain": ["localhost", "127.0.0.1"],
           "outbound": "direct"  // 允许访问本地
         }
       ]
     }
   }
   ```

3. **运行测试脚本**
   ```bash
   # 测试 256KB
   curl -s 'http://127.0.0.1:8081/traffic?clear=true' -H "Authorization: test_secret_key_12345" > /dev/null
   sleep 1
   curl -x socks5://127.0.0.1:10800 -s "http://your-server/256kb.bin" -o /dev/null
   sleep 2
   curl -s http://127.0.0.1:8081/traffic -H "Authorization: test_secret_key_12345" | jq .

   # 测试 512KB
   curl -s 'http://127.0.0.1:8081/traffic?clear=true' -H "Authorization: test_secret_key_12345" > /dev/null
   sleep 1
   curl -x socks5://127.0.0.1:10800 -s "http://your-server/512kb.bin" -o /dev/null
   sleep 2
   curl -s http://127.0.0.1:8081/traffic -H "Authorization: test_secret_key_12345" | jq .
   ```

4. **记录结果**
   - 预期大小 vs 实际大小
   - 计算误差百分比
   - 更新 `results/accuracy-data.csv`

**验收标准**:
- ✅ 256KB 文件流量统计误差 < 1%
- ✅ 512KB 文件流量统计误差 < 1%

---

### 任务 2: 并发用户测试

**目标**: 验证多用户同时传输时流量统计互不干扰

**步骤**:

1. **配置多个测试用户**

   修改 `prototype/auth-api.go`:
   ```go
   var tokenToUserID = map[string]string{
       "test_user_token_123": "user_001",
       "test_user_token_456": "user_002",
       "test_user_token_789": "user_003",
   }

   var userStatus = map[string]string{
       "user_001": "active",
       "user_002": "active",
       "user_003": "active",
   }
   ```

2. **创建多个 sing-box 客户端配置**

   复制 `config/sing-box-client.json` 为:
   - `config/sing-box-client-user1.json` (端口 10800, token: test_user_token_123)
   - `config/sing-box-client-user2.json` (端口 10801, token: test_user_token_456)
   - `config/sing-box-client-user3.json` (端口 10802, token: test_user_token_789)

3. **启动多个客户端**
   ```bash
   ./sing-box run -c config/sing-box-client-user1.json > logs/client-user1.log 2>&1 &
   ./sing-box run -c config/sing-box-client-user2.json > logs/client-user2.log 2>&1 &
   ./sing-box run -c config/sing-box-client-user3.json > logs/client-user3.log 2>&1 &
   ```

4. **并发测试**
   ```bash
   # 清零流量统计
   curl -s 'http://127.0.0.1:8081/traffic?clear=true' -H "Authorization: test_secret_key_12345" > /dev/null
   sleep 1

   # 三个用户同时下载
   curl -x socks5://127.0.0.1:10800 -s "http://httpbin.org/bytes/102400" -o /dev/null &
   curl -x socks5://127.0.0.1:10801 -s "http://httpbin.org/bytes/102400" -o /dev/null &
   curl -x socks5://127.0.0.1:10802 -s "http://httpbin.org/bytes/102400" -o /dev/null &

   wait
   sleep 2

   # 查看流量统计
   curl -s http://127.0.0.1:8081/traffic -H "Authorization: test_secret_key_12345" | jq .
   ```

5. **验证结果**
   - 检查是否有 3 个用户的流量记录
   - 验证每个用户的流量约为 100KB
   - 验证总流量 = 各用户流量之和

**验收标准**:
- ✅ 3 个用户的流量分别统计
- ✅ 各用户流量互不干扰
- ✅ 总流量 = user_001 + user_002 + user_003

---

## 四、测试脚本模板

创建 `tests/phase-0.2-补充测试.sh`:

```bash
#!/bin/bash

set -e

BASE_DIR="/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/Hysteria2_Validation"
STATS_API="http://127.0.0.1:8081/traffic"
AUTH_HEADER="Authorization: test_secret_key_12345"

echo "=========================================="
echo "Phase 0.2 补充测试"
echo "=========================================="
echo ""

# 测试 1: 多文件大小测试
echo "测试 1: 多文件大小测试"
echo "----------------------------------------"

# TODO: 实现 256KB 和 512KB 测试

# 测试 2: 并发用户测试
echo "测试 2: 并发用户测试"
echo "----------------------------------------"

# TODO: 实现并发用户测试

echo ""
echo "=========================================="
echo "所有补充测试完成！"
echo "=========================================="
```

---

## 五、输出要求

完成测试后，更新以下文件：

1. **`results/accuracy-data.csv`**
   ```csv
   测试项,预期大小(bytes),实际大小(bytes),误差(%),状态
   100KB,102400,102641,0.24,✅ 通过
   256KB,262144,<实际值>,<误差>,<状态>
   512KB,524288,<实际值>,<误差>,<状态>
   ```

2. **`results/phase-0.2-补充测试结果.md`**
   - 测试环境说明
   - 详细测试步骤
   - 测试结果数据
   - 问题解决方案
   - 结论和建议

3. **更新 `results/phase-0.2-results.md`**
   - 移除"测试限制"部分
   - 添加补充测试结果
   - 更新验收标准状态

---

## 六、需要用户配合的事项

### 选项 A: 使用云服务器部署测试文件

**需要提供**:
- 云服务器 IP 地址
- SSH 访问权限
- HTTP 服务器配置（nginx/apache）

**优点**:
- 外部可访问，代理转发正常
- 可控的测试环境

### 选项 B: 使用公共测试服务

**需要确认**:
- 可靠的文件下载测试服务 URL
- 服务稳定性和可用性

**优点**:
- 无需额外部署
- 快速开始测试

### 选项 C: 修改 sing-box 配置

**需要确认**:
- 是否允许修改 sing-box 路由规则
- 是否接受本地流量通过代理

**优点**:
- 使用现有本地测试服务器
- 无需外部依赖

---

## 七、预期时间

- 环境准备: 30 分钟
- 测试执行: 1 小时
- 结果整理: 30 分钟

**总计**: 约 2 小时

---

## 八、成功标准

完成后，Phase 0.2 应达到以下状态：

| 验收项 | 目标 | 状态 |
|--------|------|------|
| 流量统计误差（100KB） | < 1% | ✅ 0.24% |
| 流量统计误差（256KB） | < 1% | ✅ 待补充 |
| 流量统计误差（512KB） | < 1% | ✅ 待补充 |
| 多用户流量统计互不干扰 | 是 | ✅ 待补充 |
| API 响应时间 | < 100ms | ✅ < 10ms |
| 上传和下载流量分别统计 | 是 | ✅ 通过 |
| 增量采集功能 | 正常 | ✅ 通过 |

---

**准备好开始了吗？请告诉我你选择哪个方案（A/B/C），我会提供相应的支持。**
