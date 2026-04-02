---
task_id: 06
task_name: 实现自动化测试脚本
priority: high
dependencies: [01, 02, 03, 04, 05]
status: pending
---

# 任务：实现自动化测试脚本

## 目标
创建 `test_all.sh` 脚本，一键执行三个核心命题的完整验证。

## 测试命题

### 命题 A：准入
**验证内容：** EVM 地址在列表中的客户端可以正常使用流量转发
**测试方法：** Client A 通过 SOCKS :1080 访问 http://httpbin.org/ip
**预期结果：** 请求成功

### 命题 B：拒绝
**验证内容：** EVM 地址不在列表中的客户端连接被拒绝
**测试方法：** Client B 通过 SOCKS :1081 访问 http://httpbin.org/ip
**预期结果：** 请求失败

### 命题 C：动态生效
**验证内容：** 运行时修改列表并 reload，变更立即生效，不中断其他已连接用户
**测试步骤：**
1. 将 Client B 的 EVM 地址加入 `allowed_ids.json`
2. 调用 `POST /v1/sync` 触发 reload
3. 等待 2 秒
4. Client B 重新尝试访问
5. 验证 Client A 仍然可以访问（不中断性）

**预期结果：** Client B 访问成功，Client A 持续可用

## 脚本功能

### 前置检查
- Auth Service 健康状态
- 两个客户端的 EVM 地址准入状态

### 测试执行
- 自动执行三个命题的测试
- 实时显示测试进度
- 统计通过/失败数量

### 状态恢复
- 测试完成后将 `allowed_ids.json` 还原到初始状态
- 再次调用 `/v1/sync` 同步

## 技术要求

### curl 测试
```bash
try_curl() {
  local socks="$1"
  if curl -sS --max-time 8 --socks5 "$socks" "$TEST_URL" > /dev/null 2>&1; then
    echo "ok"
  else
    echo "fail"
  fi
}
```

### JSON 操作
使用 Python 内联脚本修改 `allowed_ids.json`：
```bash
python3 - <<PYEOF
import json
with open("$ALLOWED_IDS") as f:
    data = json.load(f)
# 添加或移除地址
PYEOF
```

### 结果验证
```bash
check() {
  local label="$1"; local expect_ok="$2"; local result="$3"
  if [ "$expect_ok" = "true" ] && [ "$result" = "ok" ]; then
    echo "  ✅ PASS: $label"
  elif [ "$expect_ok" = "false" ] && [ "$result" = "fail" ]; then
    echo "  ✅ PASS: $label（正确被拒绝）"
  else
    echo "  ❌ FAIL: $label"
  fi
}
```

## 验证标准
- [ ] 命题 A 测试通过
- [ ] 命题 B 测试通过
- [ ] 命题 C 测试通过
- [ ] Client A 在 reload 后仍然可用
- [ ] 测试完成后配置自动还原

## 预期输出
```
================================================
  OpenMesh V2 准入控制 POC 验证
================================================

▶ 命题 A：Client A（ID 在列表中）可以访问
  ✅ PASS: Client A 通过 SOCKS :1080 访问

▶ 命题 B：Client B（ID 不在列表中）被拒绝
  ✅ PASS: Client B 通过 SOCKS :1081 访问（期望失败）

▶ 命题 C：动态添加 Client B，reload 后立即生效
  ✅ PASS: Client B 动态加入列表后可以访问

▶ 附加验证：Client A 在 reload 后仍然可以访问
  ✅ PASS: Client A reload 后仍然正常访问

================================================
  验证结果：通过 4 个，失败 0 个
  🎉 所有命题验证通过
================================================
```

## 文件位置
**代码输出目录：** `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code`

具体路径：`code/scripts/test_all.sh`

## 使用方法
```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code
bash scripts/test_all.sh
```
