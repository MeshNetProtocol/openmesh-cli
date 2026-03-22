# MeshFlux V2 升级文档总览

> 本目录定义 `openmesh-apple/MeshFluxMac` 的 V2 升级方案。  
> 当前版本的中心思想已经调整为：**OpenMesh 要成为 VPN 行业的 OpenRouter，并且商用场景要同时成立“快速切换”和“去中心化结算”。**

---

## 核心定位

MeshFlux V2 不是传统 VPN 客户端升级，也不是中心化流量市场后台。  
它的目标是：

**让用户像切换 AI 模型一样切换 VPN 供应商，同时让供应商直接收取 USDC，并把平台价值沉淀在协议、客户端和后续 token 经济上。**

类比关系如下：

| AI 产品语义 | MeshFlux V2 对应 |
|---|---|
| 模型目录 / 聚合入口 | `OpenMesh` |
| 大模型供应商 | 商用流量供应商 |
| 平台内置免费模型 / 限额模型 | 官方临时受限访问 |
| 本地模型 / 自托管模型 | 私人节点 / DIY 配置 |
| Credits / Wallet | 流豆账户（用户自己的链上钱包） |
| 请求结算 | x402 小额自动支付 |
| 模型切换 | 供应商切换 |

---

## 四种场景

V2 必须同时覆盖四种场景：

1. **无路由状态**  
   用户第一次启动，还没有任何商用供应商、私人节点或已安装配置。

2. **官方临时受限访问**  
   平台官方提供的第一个供应商，用于冷启动和兜底。它可以继续使用当前简单的 sing-box 服务端安装方式。

3. **商用供应商**  
   用户已有钱包与 USDC，通过链上发现供应商、通过 x402 自动完成小额支付、通过流量桶续费继续使用。

4. **私人节点 / DIY**  
   用户导入自己的配置或自建节点，不依赖流豆账户，不走商用结算。

---

## 本轮最重要的产品结论

1. **OpenMesh 首先是供应商路由层。**  
   页面第一主体永远是“当前在用谁”和“还能切到谁”。

2. **商用场景必须像 OpenRouter 一样快速切换。**  
   不能把体验做成“先注册、再下单、再人工安装”的传统 VPN 购买流程。

3. **商用结算必须去中心化。**  
   用户直接向供应商合约支付 USDC；平台不做中心化账本，不托管用户余额。

4. **x402 用于预付费购买流量。**
   用户通过 x402 向供应商预付 USDC，直接兑换成流量配额。不同供应商价格不同（如 1 USDC = 100MB）。

5. **商用场景的关键不是“下载配置”，而是“开启一个可验证、可续费、可切换的流量会话”。**

6. **官方临时受限访问和私人节点仍然必须保持无钱包可用。**

---

## 用户侧术语

本套文档统一采用以下用户侧命名：

| 底层概念 | 用户侧术语 | 说明 |
|---|---|---|
| Base 上的 USDC | **流豆** | 主界面展示名，底层仍是 USDC |
| User wallet | **流豆账户** | 用户自己持有助记词的钱包，不是平台账户 |
| x402 payment | **预付费支付** | 用于预付 USDC 购买流量配额 |
| Official provider | **官方临时受限访问** | 第一个官方供应商，负责冷启动 |
| Provider registry | **供应商目录** | 来自链上注册合约 |
| Traffic quota | **流量配额** | 预付费购买的流量额度，永久有效直到用完 |

---

## 商用场景的核心架构前提

1. **供应商发现来自链上注册合约。**
2. **供应商元数据和配置入口由供应商自己维护。**
3. **每个供应商拥有自己的收款合约。**
4. **支付直接进入供应商合约，平台只在供应商提现时收取手续费。**
5. **流量统计采用中心化扣减，无需双向签名和凭条备份。**
6. **每个供应商独立运营记账服务，供应商之间互不感知。**
7. **平台提供开源记账服务代码，供应商可自行部署或使用平台提供的服务。**

---

## 钱包与安全前提

流豆账户是用户自己的钱包，不是平台账号。  
本轮设计统一采用以下安全原则：

1. 助记词和私钥不得明文持久化。
2. 钱包材料允许以加密 blob 形式落盘，但必须使用设备绑定能力保护。
3. 私钥明文只在解锁后的 signer session 内存在于内存中。
4. 自动支付必须受两层限制：
   - 单次最大自动支付额度
   - 每日最大自动支付额度
5. 用户在解锁一次钱包后，可以在一段受控时间内自动签名后续小额支付，不必每次切换供应商或续费都重新输入口令。

---

## 升级策略

### 1. 保留简单路径

当前简单的 sing-box 单节点脚本继续保留，用于：

- 官方临时受限访问
- 自建节点快速部署
- 低门槛试用场景

### 2. 商用路径另起架构

商用供应商不再沿用“共享密码单节点”的服务端模型。  
它必须升级为：

- 链上发现
- 多用户 / 多会话数据平面
- x402 小额自动支付
- 流量桶续费
- 供应商签名凭条
- 会话级快速切换

### 3. 不以当前客户端代码束缚商业架构

本轮文档不再把“少改当前代码”作为最高约束。  
当前 `MeshFluxMac` 仍然是唯一客户端改造目标，但商业架构将按第一性原理重新设计。

---

## 文档清单

- [00-README.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/00-README.md)
- [01-V2-升级背景与范围说明.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/01-V2-升级背景与范围说明.md)
- [02-V2-现状系统分析与差距评估.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/02-V2-现状系统分析与差距评估.md)
- [03-V2-需求规格说明书.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/03-V2-需求规格说明书.md)
- [04-V2-总体架构设计.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/04-V2-总体架构设计.md)
- [05-V2-详细技术设计.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/05-V2-详细技术设计.md)
- [06-V2-数据模型与安全设计.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/06-V2-数据模型与安全设计.md)
- [07-V2-实施计划与迁移步骤.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/07-V2-实施计划与迁移步骤.md)
- [08-V2-测试策略与验收标准.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/08-V2-测试策略与验收标准.md)
- [09-V2-风险、兼容性与回滚方案.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/09-V2-风险、兼容性与回滚方案.md)
- [10-AI-执行约束与代码一致性规则.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/10-AI-执行约束与代码一致性规则.md)
- [11-V2-开发进度跟踪.md](/Users/wesley/MeshNetProtocol/openmesh-cli/openmesh-apple/docs/v2/11-V2-开发进度跟踪.md)
