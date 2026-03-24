# 给新 AI 的提示词

请阅读以下项目上下文，然后开始协助我完成 OpenMesh V2 的开发工作。

---

## 项目背景

我正在开发 **OpenMesh V2**，目标是成为 VPN 行业的 OpenRouter，实现供应商快速切换和去中心化结算。

**核心挑战**：需要实现多用户多服务器的流量统计和配额管理系统，但有严格约束：
- ❌ 不能修改 sing-box 源码
- ❌ 虚拟网卡层不能改动
- ✅ 只能通过配置文件修改行为

**技术选型**：经过对比 Shadowsocks、VMess 和 Hysteria2，我们选择了 **Hysteria2**，因为：
1. 原生支持用户级流量统计（Traffic Stats API）
2. 基于 QUIC，性能优秀
3. HTTP REST API，集成简单
4. sing-box 原生支持，只需修改配置

**当前状态**：Phase 0 准备阶段，准备开始 Hysteria2 技术验证。

---

## 完整文档位置

所有详细文档都在 `openmesh-apple/docs/v2/` 目录：

1. **[AI_CONTEXT.md](openmesh-apple/docs/v2/AI_CONTEXT.md)** - 完整的项目上下文（请先阅读这个）
2. [01-核心需求与技术选型.md](openmesh-apple/docs/v2/01-核心需求与技术选型.md) - 为什么选择 Hysteria2
3. [02-系统架构设计.md](openmesh-apple/docs/v2/02-系统架构设计.md) - 完整架构和数据流
4. [03-数据模型设计.md](openmesh-apple/docs/v2/03-数据模型设计.md) - 数据结构和 API
5. [04-实施计划.md](openmesh-apple/docs/v2/04-实施计划.md) - Phase 0-4 实施计划
6. [05-测试验收方案.md](openmesh-apple/docs/v2/05-测试验收方案.md) - 测试策略
7. [06-开发进度.md](openmesh-apple/docs/v2/06-开发进度.md) - 当前进度跟踪
8. [07-风险与应对.md](openmesh-apple/docs/v2/07-风险与应对.md) - 风险和回滚方案

---

## 关键架构

```
客户端（MeshFluxMac）
  ↓ TUN 虚拟网卡（不变）
  ↓ sing-box（只改 outbound 配置）
  ↓ Hysteria2 协议
  ↓ Hysteria2 节点集群（Traffic Stats API）
  ↓ Metering Service（流量汇总 + 配额扣减）
```

**核心数据流**：
- 流量统计：Hysteria2 节点 → Traffic Stats API → Metering Service 定期拉取（10秒）→ 汇总扣减
- 支付流：用户 x402 签名 → Payment Service 验证 → 兑换配额（1 USDC = 100MB）
- 配置下发：用户选择供应商 → Config Service → 生成 Hysteria2 配置 → 客户端更新 outbound

---

## 下一步工作

**当前任务**：Phase 0.1 - 搭建 Hysteria2 测试环境

**关键验证点**：
- ✅ Traffic Stats API 返回用户级数据
- ✅ 流量统计准确度 > 99%
- ✅ 多节点流量汇总无重复计数

**如果验证失败**：回滚到 VMess + V2Ray API 方案

---

## 工作原则

1. **第一性原理 + 奥卡姆剃刀** - 最简方案
2. **优先验证** - Phase 0 技术验证是最关键的
3. **保持简单** - 避免过度设计
4. **文档同步** - 所有决策和进度更新到文档

---

**请先阅读 [AI_CONTEXT.md](openmesh-apple/docs/v2/AI_CONTEXT.md) 了解完整上下文，然后告诉我你准备好了，我们开始工作。**
