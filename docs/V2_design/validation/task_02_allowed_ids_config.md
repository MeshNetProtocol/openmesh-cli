---
task_id: 02
task_name: 创建允许列表配置文件
priority: high
dependencies: []
status: pending
---

# 任务：创建允许列表配置文件

## 目标
创建 `allowed_ids.json` 配置文件，存储允许接入的 EVM 地址列表。

## 配置结构
```json
{
  "version": "1.0",
  "description": "允许接入的 EVM 地址列表（单组，上限 1 万）",
  "allowed_ids": [
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  ]
}
```

## 技术要求
- JSON 格式，支持标准 JSON 解析
- `allowed_ids` 数组初始只包含 Client A 的地址
- Client B 的地址 (`0xbbb...`) 初始不在列表中，用于动态添加测试
- Client C 的地址 (`0xccc...`) 始终不在列表中，用于持续验证拒绝逻辑

## 约束条件
- 单组上限：10,000 个地址
- 所有地址必须是小写格式
- 地址格式：`0x` + 40 位十六进制字符

## 验证标准
- [ ] JSON 格式正确，可被标准解析器解析
- [ ] 初始状态只包含 Client A 地址
- [ ] 文件可被 Auth Service 正确读取

## 文件位置
**代码输出目录：** `/Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/code`

具体路径：`code/allowed_ids.json`
