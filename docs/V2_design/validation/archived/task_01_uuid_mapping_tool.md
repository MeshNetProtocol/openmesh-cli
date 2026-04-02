---
task_id: 01
task_name: 实现 EVM 地址到 UUID 映射工具
priority: high
dependencies: []
status: pending
---

# 任务：实现 EVM 地址到 UUID 映射工具

## 目标
创建 Python 脚本 `gen_uuid.py`，实现 EVM 地址与 UUID v5 之间的双向转换。

## 技术要求
- 使用 UUID v5 (SHA-1) 算法，基于 NAMESPACE_DNS
- 支持正向转换：EVM 地址 → UUID
- 支持反向查找：UUID → EVM 地址（在已知列表中）
- 从 `allowed_ids.json` 加载已知地址列表

## 输入/输出
**输入：**
- EVM 地址格式：`0x` + 40 位十六进制字符（20 字节）
- UUID 格式：标准 UUID 字符串

**输出：**
- 正向：派生的 UUID 字符串
- 反向：匹配的 EVM 地址或 "未找到"

## 实现细节
```python
# 核心算法
UUID = uuid5(NAMESPACE_DNS, lowercase(evm_address))

# 示例地址
client_a: 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  # 在列表中
client_b: 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  # 初始不在列表
client_c: 0xcccccccccccccccccccccccccccccccccccccccc  # 始终不在列表
```

## 验证标准
- [ ] 同一 EVM 地址多次转换得到相同 UUID
- [ ] 不同 EVM 地址得到不同 UUID
- [ ] 反向查找能正确匹配 allowed_ids.json 中的地址
- [ ] 反向查找对不在列表中的 UUID 返回 None

## 文件位置
**代码输出目录：** `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code`

具体路径：`code/scripts/gen_uuid.py`
