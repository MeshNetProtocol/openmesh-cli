# Coinbase Commerce 集成 POC 验证方案

## 文档信息

**文档类型**: 技术验证方案  
**创建日期**: 2026-04-06  
**验证目标**: 验证 Coinbase Commerce 零 Gas 费订阅支付的可行性  
**预计时间**: 3-5 天  
**状态**: 待开始

## 一、验证目标

### 1.1 核心目标

**验证 Coinbase Commerce 零 Gas 费支付通知机制**

只验证一个核心流程:

```
用户支付 (零 Gas) → Coinbase Commerce Webhook → Auth 服务器接收通知
```

**验证成功标准**:
1. ✅ 用户通过 Coinbase Commerce 支付 USDC,零 Gas 费
2. ✅ Auth 服务器收到 Webhook 通知
3. ✅ 通知包含完整信息:
   - 用户区块链地址
   - 支付金额
   - 支付时间
   - 交易哈希
4. ✅ Auth 服务器成功记录支付信息到文件

### 1.2 非验证范围

本次 POC **不验证**以下内容:
- ❌ 订阅管理逻辑
- ❌ Xray 用户添加
- ❌ VPN 连接测试
- ❌ 自动续费
- ❌ 智能合约托管
- ❌ 完整用户界面

**原因**: 这些是 Auth 服务器的内部业务逻辑,与支付通知无关

## 二、技术方案

### 2.1 架构设计 (简化版)

```
┌─────────────────────────────────────────────────────────┐
│  用户 (任何钱包)                                         │
│  - Coinbase 账户                                         │
│  - MetaMask                                              │
│  - 其他 Web3 钱包                                        │
└────────────────────────┬────────────────────────────────┘
                         │ 支付 USDC (零 Gas)
                         ↓
┌─────────────────────────────────────────────────────────┐
│  Coinbase Commerce                                       │
│  - 生成支付链接                                          │
│  - 处理支付                                              │
│  - 发送 Webhook 通知                                     │
└────────────────────────┬────────────────────────────────┘
                         │ Webhook 回调
                         ↓
┌─────────────────────────────────────────────────────────┐
│  Auth Service (Go) - 最小化实现                          │
│  - 接收 Webhook                                          │
│  - 验证签名                                              │
│  - 记录支付信息到 payments.json                          │
└─────────────────────────────────────────────────────────┘
```

**验证范围**: 只到 Auth Service 记录支付信息为止

### 2.2 数据流程 (简化版)

**步骤 1: 生成支付链接**
```
调用 Coinbase Commerce API
→ 创建 Charge (指定金额和用户地址)
→ 获得支付链接
```

**步骤 2: 用户支付**
```
用户打开支付链接
→ 选择钱包支付
→ 完成支付 (零 Gas)
```

**步骤 3: 接收支付通知 (核心验证点)**
```
Coinbase Commerce 发送 Webhook
→ Auth Service 接收 HTTP POST
→ 验证签名
→ 解析支付信息:
   - 用户地址
   - 支付金额
   - 支付时间
   - 交易哈希
→ 保存到 payments.json
→ 返回 200 OK
```

**验证完成**: 确认 payments.json 中有正确的支付记录

### 2.3 核心技术组件 (最小化)

| 组件 | 技术选型 | 用途 |
|------|---------|------|
| 支付网关 | Coinbase Commerce | 零 Gas 费支付 |
| 后端服务 | Go + Gin | Webhook 接收 |
| 数据存储 | JSON 文件 | 支付记录持久化 |

## 三、实施步骤 (简化版)

### Phase 1: Coinbase Commerce 账户设置 (半天)

#### 任务 1.1: 注册 Coinbase Commerce 账户
- [ ] 访问 https://commerce.coinbase.com/
- [ ] 注册商家账户
- [ ] 完成 KYC 验证(如需要)
- [ ] 获取 API Key

#### 任务 1.2: 配置支付设置
- [ ] 设置接收 USDC 的钱包地址
- [ ] 配置 Webhook URL (测试环境)
- [ ] 选择 Base 网络作为支付网络
- [ ] 测试 Webhook 连接

**交付物**:
- Coinbase Commerce API Key
- Webhook Secret
- 测试钱包地址

### Phase 2: 最小化 Webhook 服务开发 (1 天)

#### 任务 2.1: Webhook 处理 (核心)

**文件**: `poc/webhook_server.go`

```go
package main

import (
    "crypto/hmac"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "io"
    "log"
    "os"
    "time"
    
    "github.com/gin-gonic/gin"
)

// Coinbase Commerce Webhook 事件
type WebhookEvent struct {
    Type string `json:"type"`
    Data struct {
        Code     string `json:"code"`
        Metadata map[string]string `json:"metadata"`
        Payments []struct {
            Value struct {
                Local struct {
                    Amount   string `json:"amount"`
                    Currency string `json:"currency"`
                } `json:"local"`
            } `json:"value"`
            TransactionID string `json:"transaction_id"`
        } `json:"payments"`
        Timeline []struct {
            Status string    `json:"status"`
            Time   time.Time `json:"time"`
        } `json:"timeline"`
    } `json:"data"`
}

// 支付记录
type PaymentRecord struct {
    UserAddress   string    `json:"user_address"`
    Amount        string    `json:"amount"`
    Currency      string    `json:"currency"`
    TransactionID string    `json:"transaction_id"`
    PaymentTime   time.Time `json:"payment_time"`
    ChargeCode    string    `json:"charge_code"`
}

var webhookSecret = os.Getenv("COINBASE_WEBHOOK_SECRET")

func main() {
    r := gin.Default()
    
    // Webhook 端点
    r.POST("/webhook/coinbase", handleWebhook)
    
    log.Println("Webhook server starting on :8080")
    r.Run(":8080")
}

func handleWebhook(c *gin.Context) {
    // 1. 读取请求体
    body, err := io.ReadAll(c.Request.Body)
    if err != nil {
        c.JSON(400, gin.H{"error": "Cannot read body"})
        return
    }
    
    // 2. 验证签名
    signature := c.GetHeader("X-CC-Webhook-Signature")
    if !verifySignature(signature, body) {
        log.Println("Invalid signature")
        c.JSON(401, gin.H{"error": "Invalid signature"})
        return
    }
    
    // 3. 解析事件
    var event WebhookEvent
    if err := json.Unmarshal(body, &event); err != nil {
        c.JSON(400, gin.H{"error": "Invalid JSON"})
        return
    }
    
    log.Printf("Received event: %s", event.Type)
    
    // 4. 处理支付确认事件
    if event.Type == "charge:confirmed" {
        savePaymentRecord(event)
    }
    
    c.JSON(200, gin.H{"status": "ok"})
}

func verifySignature(signature string, body []byte) bool {
    mac := hmac.New(sha256.New, []byte(webhookSecret))
    mac.Write(body)
    expectedSignature := hex.EncodeToString(mac.Sum(nil))
    return hmac.Equal([]byte(signature), []byte(expectedSignature))
}

func savePaymentRecord(event WebhookEvent) {
    if len(event.Data.Payments) == 0 {
        log.Println("No payment data")
        return
    }
    
    payment := event.Data.Payments[0]
    
    record := PaymentRecord{
        UserAddress:   event.Data.Metadata["user_address"],
        Amount:        payment.Value.Local.Amount,
        Currency:      payment.Value.Local.Currency,
        TransactionID: payment.TransactionID,
        PaymentTime:   time.Now(),
        ChargeCode:    event.Data.Code,
    }
    
    // 保存到文件
    file, err := os.OpenFile("payments.json", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
    if err != nil {
        log.Printf("Failed to open file: %v", err)
        return
    }
    defer file.Close()
    
    data, _ := json.MarshalIndent(record, "", "  ")
    file.Write(data)
    file.WriteString("\n")
    
    log.Printf("Payment recorded: %s paid %s %s", 
        record.UserAddress, record.Amount, record.Currency)
}
```

#### 任务 2.2: 创建支付链接脚本

**文件**: `poc/create_charge.go`

```go
package main

import (
    "bytes"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
    "os"
)

func main() {
    apiKey := os.Getenv("COINBASE_API_KEY")
    userAddress := os.Args[1] // 从命令行参数获取
    
    // 创建 Charge 请求
    payload := map[string]interface{}{
        "name":         "VPN Subscription Test",
        "description":  "POC Test Payment",
        "pricing_type": "fixed_price",
        "local_price": map[string]string{
            "amount":   "1",
            "currency": "USDC",
        },
        "metadata": map[string]string{
            "user_address": userAddress,
        },
    }
    
    data, _ := json.Marshal(payload)
    
    req, _ := http.NewRequest("POST", 
        "https://api.commerce.coinbase.com/charges", 
        bytes.NewBuffer(data))
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("X-CC-Api-Key", apiKey)
    
    client := &http.Client{}
    resp, err := client.Do(req)
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    defer resp.Body.Close()
    
    body, _ := io.ReadAll(resp.Body)
    
    var result map[string]interface{}
    json.Unmarshal(body, &result)
    
    data, _ := result["data"].(map[string]interface{})
    hostedURL := data["hosted_url"].(string)
    
    fmt.Printf("Payment URL: %s\n", hostedURL)
}
```

**交付物**:
- 最小化 Webhook 服务器
- 支付链接生成脚本
- payments.json 记录文件

### Phase 3: 测试 (半天)

**不需要前端**,直接使用命令行测试

### Phase 4: 端到端测试 (第 4 天)

#### 任务 4.1: 测试环境准备

- [ ] 部署 Auth Service 到测试服务器
- [ ] 配置 Xray 测试服务器
- [ ] 设置 Coinbase Commerce Webhook URL
- [ ] 准备测试钱包(含少量 USDC)

#### 任务 4.2: 测试用例

**测试用例 1: 完整支付流程**
```
1. 用户访问订阅页面
2. 输入钱包地址: 0x1234...
3. 选择 Monthly 套餐
4. 点击支付按钮
5. 在 Coinbase Commerce 页面完成支付
6. 等待 Webhook 回调
7. 验证订阅状态变为 active
8. 验证 UUID 已生成
9. 验证用户已添加到 Xray
```

**预期结果**:
- ✅ 用户无需支付 Gas 费
- ✅ 支付确认时间 < 30 秒
- ✅ 订阅自动激活
- ✅ 用户可以连接 VPN

**测试用例 2: Webhook 验证**
```
1. 模拟 Coinbase Commerce Webhook 请求
2. 使用正确的签名
3. 验证 Webhook 处理成功
4. 验证订阅记录创建
```

**预期结果**:
- ✅ 签名验证通过
- ✅ 订阅记录正确创建
- ✅ 用户添加到 Xray

**测试用例 3: 错误处理**
```
1. 测试无效的签名
2. 测试重复的 Webhook
3. 测试 Xray 添加用户失败
```

**预期结果**:
- ✅ 无效签名被拒绝
- ✅ 重复 Webhook 被忽略
- ✅ 错误被正确记录

#### 任务 4.3: VPN 连接测试

**Sing-box 配置**:
```json
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "test-server-ip",
      "server_port": 10086,
      "uuid": "从订阅获得的 UUID",
      "flow": "",
      "network": "tcp"
    }
  ]
}
```

**测试步骤**:
1. 使用获得的 UUID 配置 Sing-box
2. 启动 Sing-box 客户端
3. 测试网络连接
4. 验证流量统计

**预期结果**:
- ✅ VPN 连接成功
- ✅ 网络流量正常
- ✅ 流量统计正确

**交付物**:
- 测试报告
- 测试用例执行记录
- 问题列表(如有)

### Phase 5: 文档和总结 (第 5 天)

#### 任务 5.1: 编写技术文档

- [ ] API 文档
- [ ] Webhook 集成指南
- [ ] 部署文档
- [ ] 故障排查指南

#### 任务 5.2: POC 验证报告

**报告内容**:
1. 验证目标达成情况
2. 技术可行性分析
3. 性能指标
4. 成本分析
5. 风险评估
6. 下一步建议

**交付物**:
- 完整的技术文档
- POC 验证报告
- 代码仓库

## 四、验收标准

### 4.1 功能验收

- [ ] 用户可以通过 Coinbase Commerce 支付,零 Gas 费
- [ ] 支付成功后自动创建订阅记录
- [ ] 自动生成 UUID 并绑定到用户地址
- [ ] 自动将用户添加到 Xray 服务器
- [ ] 用户可以使用 UUID 连接 VPN
- [ ] 支付确认时间 < 30 秒

### 4.2 技术验收

- [ ] Webhook 签名验证正确
- [ ] 支持幂等性(重复 Webhook 不会重复创建订阅)
- [ ] 错误处理完善
- [ ] 日志记录完整
- [ ] 代码质量良好

### 4.3 用户体验验收

- [ ] 支付流程简单直观
- [ ] 支持多种钱包(Coinbase、MetaMask 等)
- [ ] 支付状态实时反馈
- [ ] 错误提示友好

## 五、成本分析

### 5.1 开发成本

| 项目 | 时间 | 说明 |
|------|------|------|
| Coinbase Commerce 集成 | 1 天 | SDK 集成和测试 |
| 后端开发 | 2 天 | Webhook 处理和订阅管理 |
| 前端开发 | 1 天 | 支付页面 |
| 测试 | 1 天 | 端到端测试 |
| **总计** | **5 天** | |

### 5.2 运营成本

| 项目 | 成本 | 说明 |
|------|------|------|
| Coinbase Commerce 手续费 | 1% | 每笔交易 |
| 服务器 | $50/月 | Auth Service |
| 测试 USDC | $50 | 一次性 |

### 5.3 用户成本

| 项目 | 成本 | 说明 |
|------|------|------|
| 订阅费 | 6 USDC/月 | 用户支付 |
| Gas 费 | **$0** | Coinbase 承担 |

## 六、风险评估

### 6.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| Coinbase Commerce 不可用 | 高 | 低 | 保留 MetaMask 备选方案 |
| Webhook 延迟 | 中 | 中 | 实现轮询备用机制 |
| Xray 添加用户失败 | 中 | 低 | 重试机制 + 告警 |

### 6.2 业务风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 用户支付后未激活 | 高 | 低 | 手动激活机制 |
| 重复支付 | 中 | 低 | 幂等性保证 |
| 欺诈支付 | 中 | 低 | Coinbase 风控 |

## 七、下一步计划

### 7.1 Phase 2 功能

POC 验证通过后,进入 Phase 2 开发:

1. **自动续费**: 集成 Coinbase Commerce 订阅模式
2. **智能合约托管**: 实现供应商资金托管
3. **多服务器支持**: 支持用户选择不同地区服务器
4. **完整 UI**: 开发完整的用户界面
5. **监控告警**: 添加 Prometheus 监控

### 7.2 生产环境部署

1. 安全加固
2. 性能优化
3. 负载测试
4. 灰度发布

## 八、参考资料

### 8.1 Coinbase Commerce

- [Coinbase Commerce 文档](https://docs.cdp.coinbase.com/commerce/docs/)
- [Coinbase Commerce API](https://docs.cdp.coinbase.com/commerce/reference/)
- [Webhook 集成指南](https://docs.cdp.coinbase.com/commerce/docs/webhooks/)

### 8.2 相关文档

- [支付与结算技术方案](../archive/1.1支付与结算技术方案.md)
- [项目总览](../0.项目总览.md)
- [模块 2: 区块链支付模块](../modules/module2_blockchain_payment.md)

---

**文档维护者**: [待填写]  
**最后更新**: 2026-04-06  
**状态**: 待审查
