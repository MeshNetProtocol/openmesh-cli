# 模块 5: Sing-box 客户端模块

## 模块状态

**当前状态**: ⏳ 待开发  
**最后更新**: 2026-04-06

## 1. 模块概述

本模块负责开发用户端 VPN 客户端,基于 Sing-box 实现,支持区块链钱包集成、订阅购买和多平台部署。

### 1.1 核心功能

- **区块链钱包集成**: 支持连接 MetaMask、WalletConnect 等主流钱包
- **订阅购买**: 用户可以选择订阅套餐并完成支付
- **VPN 连接**: 基于 Sing-box 实现 VPN 连接功能
- **服务器选择**: 支持选择不同地区的 Xray 服务器
- **流量监控**: 实时显示用户的流量使用情况
- **订阅管理**: 查看订阅状态、到期时间、续费等
- **多平台支持**: 支持 macOS、Windows、Linux、iOS、Android

## 2. 技术方案

### 2.1 核心技术选型

**桌面端 (macOS/Windows/Linux)**:
- **框架**: Electron + React + TypeScript
- **VPN 核心**: Sing-box (Go 编译的二进制)
- **钱包集成**: ethers.js + WalletConnect
- **UI 库**: Ant Design / Tailwind CSS

**移动端 (iOS/Android)**:
- **框架**: React Native + TypeScript
- **VPN 核心**: 
  - iOS: NetworkExtension + Sing-box
  - Android: VpnService + Sing-box
- **钱包集成**: WalletConnect Mobile SDK

### 2.2 Sing-box 集成

**桌面端方案**:
```
Electron 主进程 → 启动 Sing-box 子进程 → 配置 VLESS 连接
                → 监听 Sing-box 日志
                → 管理连接状态
```

**移动端方案**:
- iOS: 使用 NetworkExtension 框架创建 VPN 扩展,集成 Sing-box
- Android: 使用 VpnService 创建 VPN 服务,集成 Sing-box

## 3. 开发任务

### 3.1 任务分解

#### 阶段 1: 桌面端基础框架 (待开始)
- [ ] 搭建 Electron + React + TypeScript 项目
- [ ] 配置开发环境和构建流程
- [ ] 实现主进程和渲染进程通信
- [ ] 集成 Sing-box 二进制

#### 阶段 2: 钱包集成 (待开始)
- [ ] 集成 MetaMask
- [ ] 集成 WalletConnect
- [ ] 实现钱包连接/断开
- [ ] 实现支付交易发起

#### 阶段 3: VPN 核心功能 (待开始)
- [ ] 实现 Sing-box 配置生成
- [ ] 实现 Sing-box 进程管理
- [ ] 实现 VPN 连接/断开
- [ ] 实现连接状态监控

#### 阶段 4: UI/UX (待开始)
- [ ] 设计 UI 界面
- [ ] 实现主界面
- [ ] 实现设置界面
- [ ] 实现服务器选择界面

#### 阶段 5: 移动端开发 (待开始)
- [ ] 搭建 React Native 项目
- [ ] 实现 iOS NetworkExtension
- [ ] 实现 Android VpnService
- [ ] 移植桌面端功能到移动端

## 4. 验收标准

- [ ] 支持 MetaMask 连接
- [ ] 支持 WalletConnect 连接
- [ ] VPN 连接成功率 > 95%
- [ ] 连接建立时间 < 5 秒
- [ ] 支持 macOS、Windows、Linux
- [ ] iOS 版本通过 App Store 审核
- [ ] Android 版本通过 Google Play 审核

## 5. 相关文档

- [项目总览](../0.项目总览.md)
- [技术方案](../1.技术方案.md)

---

**文档维护者**: [待填写]  
**最后更新**: 2026-04-06
