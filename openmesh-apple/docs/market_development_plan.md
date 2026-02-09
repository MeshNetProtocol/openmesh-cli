# 流量市场开发实施计划

## 概述

本文档整合了 `market_design.md` 和 `market_sync_design.md` 的核心设计理念，形成一个完整的、可实施的开发计划。目标是构建一个支持供应商配置包版本同步、hash驱动更新、行为一致性保证的流量市场系统。

## 1. 核心设计原则

### 1.1 行为一致性定义
- **force_proxy 命中**：必须走 `proxy`（强制代理）
- **geoip/geosite 命中**：必须走 `direct`（直连）
- **未命中流量**：由本地开关 `SharedPreferences.unmatchedTrafficOutbound` 控制

### 1.2 同步策略
- **市场全量更新**：仅更新供应商基本信息列表（名称、描述、标签、价格、hash摘要）
- **供应商按需同步**：用户选择供应商时同步全部依赖文件
- **Hash驱动**：使用内容hash而非版本号作为一致性判断依据

### 1.3 失败处理原则
- 同步失败直接提示错误，不做兜底
- 用户可切换其他供应商或稍后重试

## 0. 当前已实现（2026-02-09）

### 0.1 双官方供应商
- **official-local**：本地保底配置（来自Xcode资源default_profile.json）
- **official-online**：在线市场版本（用于对照测试和未来替代）

### 0.2 客户端安装与落盘形态
- **Profile ↔ Provider 映射**（SharedPreferences）
  - `profile_id → provider_id`
  - `provider_id → installed_package_hash`
- **供应商目录结构（App Group）**
  - `AppGroup/MeshFlux/providers/<provider_id>/config.json`
  - `AppGroup/MeshFlux/providers/<provider_id>/routing_rules.json`
- **安装入口**
  - 市场列表操作按钮为 Install
  - 点击后弹出独立的前台安装窗口，逐步展示安装过程与失败原因

### 0.3 行为一致性与已验证点
- **force_proxy（routing_rules.json）**：按供应商隔离加载，不互相污染
- **rule-set（geoip/geosite）**：优先使用 sing-box `type: remote` + `url` 由内核在连接时下载
- **配置不兼容提示**：当 `includeAllNetworks` 启用且 `tun.stack=system/mixed` 时，启动会失败并给出明确错误，要求供应商修正配置

### 0.4 本地诊断工具
- `market_debug.py`：读取 settings.db/Profiles/映射关系与 provider 目录结构，并输出关键 startTunnel 日志尾部，便于定位安装与启动问题

## 2. 架构设计

### 2.1 服务端架构（D1 + R2 + Worker）
- **D1数据库**：存储供应商元数据
  - id、name、description、tags、price_per_gb_usd
  - provider_hash、package_hash、updated_at
  - visibility、status、package_json
- **R2存储**：配置文件包（config.json、routing_rules.json、*.srs）
- **Worker API**：提供市场清单、供应商详情、hash检查等接口

### 2.2 客户端架构
- **Profile ↔ Provider 映射**：
  - `profile_id → provider_id` 映射（SharedPreferences）
  - `provider_id → installed_package_hash` 映射
- **文件存储**：按供应商隔离的目录结构
  - `AppGroup/MeshFlux/providers/<provider_id>/config.json`
  - `AppGroup/MeshFlux/providers/<provider_id>/routing_rules.json`
  - `AppGroup/MeshFlux/providers/<provider_id>/rule-set/*`（仅在启用本地落盘策略时）
- **规则隔离**：force_proxy按供应商加载，避免互相污染

### 2.3 双官方供应商策略
- **official-local**：本地保底配置（来自Xcode资源default_profile.json）
- **official-online**：在线市场版本（用于对照测试和未来替代）

## 3. API设计

### 3.1 市场清单接口
`GET /api/v1/market/manifest`
```json
{
  "market_hash": "sha256:...",
  "market_updated_at": "2026-02-08T10:00:00Z",
  "providers": [
    {
      "id": "official-online",
      "name": "官方供应商在线版本",
      "provider_hash": "sha256:...",
      "package_hash": "sha256:..."
    }
  ]
}
```

### 3.2 供应商详情接口
`GET /api/v1/providers/:id`
```json
{
  "provider": { /* 元数据 */ },
  "package": {
    "package_hash": "sha256:...",
    "files": [
      { "type": "config", "url": "https://..." },
      { "type": "force_proxy", "url": "https://..." },
      { "type": "rule_set", "tag": "geoip-cn", "mode": "remote_url", "url": "https://..." }
    ]
  }
}
```

### 3.3 推荐供应商接口
`GET /api/v1/market/recommended?limit=6` - 用于菜单栏展示

### 3.4 市场浏览接口
`GET /api/v1/market/providers?page=1&sort=time&q=mesh` - 用于独立窗口Grid展示

## 4. 关键技术实现

### 4.1 Hash计算与验证
- **provider_hash**：供应商基本信息 + package_hash的hash
- **package_hash**：配置包全部依赖文件的hash
- 替代版本号作为更新判断的唯一依据

### 4.2 Rule-set处理策略
- **首选方案**：sing-box `type: remote` + `url`（由内核自行下载）
- **优势**：减少客户端代码复杂度，支持代理下载
- **URL指向**：自有Worker/R2镜像源，不依赖GitHub
 - **一致性要求**：客户端不改写供应商 config；发现不兼容配置应提示并要求服务端修正

### 4.3 文件同步机制
1. Dashboard切换时检查package_hash
2. 不一致则后台下载全部依赖文件
3. 下载成功提示"重连以立即生效"
4. 失败则提示错误，保持当前配置

### 4.4 路由规则隔离
- 从全局单文件改为按供应商加载
- 目录结构：`AppGroup/MeshFlux/providers/<provider_id>/routing_rules.json`
- Extension根据当前provider_id选择对应规则文件

## 5. UI/UX设计

### 5.1 菜单栏弹窗（轻量级）
- 展示推荐供应商列表（6个）
- "浏览更多"按钮打开独立窗口
- 空间有限，只展示核心信息

### 5.2 独立窗口（完整市场）
- Grid布局展示供应商卡片
- 排序：时间、价格
- 搜索：按名称模糊搜索
- 分页：支持分页浏览

### 5.3 供应商详情页
- 配置说明和规则摘要
- hash信息和价格展示
- "使用/安装/切换"操作按钮

## 6. 开发实施路线图

### Phase 0：前置条件准备（1-2周）
- [x] 固定provider_id命名规则（official-local / official-online）
- [x] 确定Profile ↔ Provider映射存储方案（SharedPreferences）
- [x] 设计force_proxy按供应商隔离的目录结构
- [ ] 确定hash计算口径和规范化规则
- [ ] 设计D1表结构并创建初始表

### Phase 1：服务端基础建设（2-3周）
- [ ] 实现D1数据库表结构
- [ ] 写入official-online初始记录
- [ ] 实现Worker API：
  - [ ] `/api/v1/market/manifest`（支持ETag缓存）
  - [ ] `/api/v1/providers/:id`（供应商详情）
  - [ ] `/api/v1/market/recommended`（推荐供应商）
  - [ ] `/api/v1/market/providers`（分页浏览）
- [ ] 配置R2存储桶和访问策略

### Phase 2：客户端核心功能（3-4周）
- [ ] 实现market manifest全量更新逻辑
- [ ] 实现provider包按需同步下载
- [ ] 实现hash驱动更新检查机制
- [ ] 实现force_proxy按供应商隔离加载
- [ ] 完善错误处理和用户提示

### Phase 2.1：安装向导验收项（补强）
- [ ] 安装窗口展示 provider_hash/package_hash 与文件清单
- [ ] 安装失败分步提示（网络失败/配置不兼容/落盘失败）并支持重试
- [ ] 安装阶段做基础配置校验（仅校验，不改写配置）

### Phase 3：UI界面开发（2-3周）
- [ ] 菜单栏推荐供应商列表
- [ ] 独立窗口市场浏览界面
- [ ] 供应商详情页面
- [ ] 安装/切换操作流程

### Phase 3.1：可观测性与复测清单
- [ ] official-local vs official-online 行为一致性对照用例
- [ ] 日志关键字与失败分类（DNS/拨号超时/rule-set下载失败/配置不兼容）

### Phase 4：测试验证（1-2周）
- [ ] 行为一致性测试（official-local vs official-online）
- [ ] 网络异常场景测试
- [ ] 并发更新冲突测试
- [ ] 性能压力测试

### Phase 5：运营功能扩展（后续）
- [ ] 私人供应商支持（visibility=private）
- [ ] 供应商紧急下线机制
- [ ] 文件级sha256校验
- [ ] 配置包签名校验
- [ ] 实名认证和押金体系

## 7. 风险与应对策略

### 7.1 技术风险
- **rule-set下载失败**：采用remote URL+代理下载，指向自有镜像源
- **hash计算不一致**：制定严格的规范化计算规则
- **并发更新冲突**：采用原子操作和事务处理

### 7.2 产品风险
- **市场链路不可用**：保留official-local作为保底配置
- **供应商配置错误**：建立配置包审核和签名机制
- **用户体验中断**：清晰的错误提示和恢复路径

### 7.3 运营风险
- **供应商质量参差不齐**：建立评级和推荐机制
- **安全风险**：后续实现签名校验和审计日志

## 8. 后续演进规划

### 8.1 短期优化（3个月内）
- 实现供应商配置包签名验证
- 添加供应商评级和评论功能
- 优化同步性能和缓存策略

### 8.2 中期规划（6个月内）
- 支持私人供应商和访问控制
- 实现配置包自动化测试框架
- 建立供应商信用体系

### 8.3 长期愿景（1年内）
- 完全去中心化的供应商市场
- 智能路由和负载均衡
- 跨平台供应商生态

## 9. 成功度量指标

### 9.1 技术指标
- 市场清单更新成功率 > 99.9%
- 供应商同步平均耗时 < 5s
- hash验证一致性100%

### 9.2 产品指标
- 用户从发现到使用供应商转化率 > 30%
- 平均每个用户使用供应商数量 > 2
- 用户满意度评分 > 4.5/5

### 9.3 运营指标
- 优质供应商数量每月增长20%
- 配置包更新频率每周1次以上
- 市场交易额月度增长30%

---

*本文档最后更新：2026年2月8日*
*本文档最后更新：2026年2月9日*
*基于 market_design.md 和 market_sync_design.md 整合*
