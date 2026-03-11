# MeshFlux V2 升级文档总览

> 本目录定义 `openmesh-apple/MeshFluxMac` 的 V2 升级方案。  
> 本轮升级不是重写一个新的 VPN 客户端，而是把现有客户端升级成“VPN 行业的 OpenRouter”。

---

## 核心定位

**MeshFlux V2 的目标是：把 VPN 服务访问体验，做成用户访问 AI 模型的体验。**

类比关系如下：

| AI 产品语义 | MeshFlux V2 对应 |
|---|---|
| 大模型供应商 | 商用流量供应商 |
| 本地模型 / 自托管模型 | 私人节点 / 私人流量供应商 |
| 当前使用的模型 | 当前路由供应商 |
| 模型切换 | 供应商切换 |
| 统一入口 | `OpenMesh` |
| 推理计费 | 流量授权支付 |
| 账户余额 / Credits | 流豆账户 |

### 产品结论

1. **OpenMesh 首先是供应商路由层。**  
   用户进入后首先看到的是“当前在用谁”和“我还能切到谁”，而不是安装向导。

2. **商用供应商要像云模型一样好用。**  
   浏览、比较、切换、授权支付、自动接入，整个过程应该尽量接近 AI 模型的选择体验。

3. **私人节点要像本地模型一样独立。**  
   用户可以像添加本地模型那样，把自己的节点或私有配置接入 MeshFlux，不依赖钱包、不依赖链上可用性。

4. **旧系统先保留，新体验以新增方式上线。**  
   当前 Dashboard / Market / Profiles / 连接管理能力全部保留，通过新增和重构 `OpenMesh` 相关界面完成升级；等新链路稳定后，再考虑淘汰旧界面。

---

## 用户侧术语

为了降低用户对区块链、USDC、Base、x402 的感知，本套文档统一采用以下用户侧命名：

| 底层概念 | 用户侧术语 | 说明 |
|---|---|---|
| USDC on Base | **流豆** | 面向用户展示的结算单位，英文可写作 `Flow Credits` |
| Wallet | **流豆账户** | 用户资产、授权和充值入口 |
| x402 Payment Authorization | **授权支付** | 商用供应商切换前的支付确认过程 |
| Self-hosted / private provider | **私人节点** | 用户自己的节点、团队节点或导入配置 |

### 为什么选择“流豆”

- 它保留了“Credits”式的产品感，适合做成 AI 式交互体验
- 它强调“流量 / 流动 / 使用量”而不是法币或稳定币本身
- 它可以与底层 USDC 结算解耦，便于主界面避免出现不必要的链上术语

---

## 产品边界

本轮文档和开发只覆盖：

- 仓库：`openmesh-cli`
- 工程：`openmesh-apple/MeshFluxMac`
- 目标：在现有 macOS 客户端能力之上，新增 OpenMesh 的商用供应商与私人节点体验

本轮明确不做：

- iOS 版本升级
- vendor-console 后台改造
- 智能合约部署说明
- 删除旧界面后的最终收口版本

---

## 升级策略

### 渐进式升级

当前系统已经具备基础 VPN、配置管理、安装和导入能力。  
因此 V2 采用以下策略：

1. 保留当前所有旧页面和旧能力
2. 继续使用已经存在的 `OpenMesh` 菜单栏入口
3. 在 `OpenMesh` 内重建新体验和新业务层
4. 商用供应商先走新增链路，旧 Market 继续保留作为回归基线
5. 私人节点优先复用现有本地配置导入能力
6. 新链路稳定后，再讨论删除或合并旧界面

### 不允许跑偏的信号

如果后续设计出现以下情况，说明已经偏离本轮目标：

- OpenMesh 被做成“安装中心”
- 钱包余额卡片取代“当前路由供应商”成为页面主体
- 私人节点路径被要求先创建流豆账户
- 商用供应商页面主按钮变成“安装”，而不是“使用 / 切换”
- 为了做新功能而直接破坏现有 VPN / Profiles / Market 核心流程

---

## 文档清单

### [00-README.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/00-README.md)
文档入口、定位、术语、阅读顺序。

### [01-V2-升级背景与范围说明.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/01-V2-升级背景与范围说明.md)
为什么升级、升到什么程度、哪些内容在本轮内、哪些不在。

### [02-V2-现状系统分析与差距评估.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/02-V2-现状系统分析与差距评估.md)
基于当前 `MeshFluxMac` 真实代码的事实审计，以及与目标之间的差距。

### [03-V2-需求规格说明书.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/03-V2-需求规格说明书.md)
完整功能需求、状态要求、业务规则和验收口径。

### [04-V2-总体架构设计.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/04-V2-总体架构设计.md)
系统边界、分层、数据流和与旧系统的共存方式。

### [05-V2-详细技术设计.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/05-V2-详细技术设计.md)
文件修改点、新增模块、状态模型和主要技术实现路线。

### [06-V2-数据模型与安全设计.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/06-V2-数据模型与安全设计.md)
流豆账户、支付授权、供应商元数据、私有配置和安全边界。

### [07-V2-实施计划与迁移步骤.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/07-V2-实施计划与迁移步骤.md)
渐进式实施阶段、里程碑、停止点和迁移策略。

### [08-V2-测试策略与验收标准.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/08-V2-测试策略与验收标准.md)
自动化测试、集成测试、人工验收和门禁策略。

### [09-V2-风险、兼容性与回滚方案.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/09-V2-风险、兼容性与回滚方案.md)
兼容性保护、产品跑偏风险、支付风险和回滚方案。

### [10-AI-执行约束与代码一致性规则.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/10-AI-执行约束与代码一致性规则.md)
AI 和人工协作开发时必须遵守的边界和实施纪律。

### [11-V2-开发进度跟踪.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/11-V2-开发进度跟踪.md)
当前阶段状态、下一步计划和实际开发进度记录。

---

## 推荐阅读顺序

### 产品 / 项目负责人

1. `00-README.md`
2. `01-V2-升级背景与范围说明.md`
3. `03-V2-需求规格说明书.md`
4. `07-V2-实施计划与迁移步骤.md`
5. `09-V2-风险、兼容性与回滚方案.md`

### 架构 / 技术负责人

1. `00-README.md`
2. `02-V2-现状系统分析与差距评估.md`
3. `03-V2-需求规格说明书.md`
4. `04-V2-总体架构设计.md`
5. `05-V2-详细技术设计.md`
6. `06-V2-数据模型与安全设计.md`

### 开发与 AI 协作

1. `00-README.md`
2. `02-V2-现状系统分析与差距评估.md`
3. `03-V2-需求规格说明书.md`
4. `04-V2-总体架构设计.md`
5. `05-V2-详细技术设计.md`
6. `06-V2-数据模型与安全设计.md`
7. `07-V2-实施计划与迁移步骤.md`
8. `08-V2-测试策略与验收标准.md`
9. `09-V2-风险、兼容性与回滚方案.md`
10. `10-AI-执行约束与代码一致性规则.md`

---

## 文档使用规则

1. **产品定位优先于局部实现。**
2. **真实代码优先于文档假设。**
3. **新增界面优先于破坏旧界面。**
4. **私人节点路径必须保持独立可用。**
5. **用户侧术语优先于链上底层术语。**
6. **支付、钱包、授权都是支撑“供应商切换”的过程，不是页面主体。**

---

## 结论

这套文档的中心不是“如何做区块链钱包”，也不是“如何再造一个 VPN 市场”。  
它要回答的是：

**如何在不破坏现有 MeshFluxMac 的前提下，把它升级成一个让用户像切换 AI 模型一样切换 VPN 供应商的产品。**
