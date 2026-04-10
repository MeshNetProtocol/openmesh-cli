package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/joho/godotenv"
)

// SubscriptionRequest 订阅请求
type SubscriptionRequest struct {
	OrderID         string    `json:"order_id"`
	IdentityAddress string    `json:"identity_address"`
	PlanID          string    `json:"plan_id"`
	Amount          string    `json:"amount"`
	Currency        string    `json:"currency"`
	Network         string    `json:"network"`
	Status          string    `json:"status"`
	CreatedAt       time.Time `json:"created_at"`
}

// Payment 支付记录
type Payment struct {
	OrderID          string    `json:"order_id"`
	IdentityAddress  string    `json:"identity_address"`
	PayerAddress     string    `json:"payer_address"`
	PlanID           string    `json:"plan_id"`
	Amount           string    `json:"amount"`
	Currency         string    `json:"currency"`
	Network          string    `json:"network"`
	PaymentMethod    string    `json:"payment_method"`
	TransactionHash  string    `json:"transaction_hash"`
	PaidAt           time.Time `json:"paid_at"`
	Status           string    `json:"status"`
}

// AutoRenewProfile 自动续费配置
type AutoRenewProfile struct {
	IdentityAddress string    `json:"identity_address"`
	BillingAccount  string    `json:"billing_account"`
	SpenderAddress  string    `json:"spender_address"`
	PermissionHash  string    `json:"permission_hash"`
	PeriodSeconds   int       `json:"period_seconds"`
	Status          string    `json:"status"`
	NextRenewAt     time.Time `json:"next_renew_at"`
	CreatedAt       time.Time `json:"created_at"`
}

var (
	mu                      sync.RWMutex
	subscriptionRequests    []SubscriptionRequest
	payments                []Payment
	autoRenewProfiles       []AutoRenewProfile
	subscriptionRequestPath string
	paymentsPath            string
	autoRenewProfilesPath   string
	orderCounter            int
	cdpClient               *CDPClient
)

func init() {
	// 加载环境变量
	if err := godotenv.Load("../.env"); err != nil {
		log.Println("Warning: .env file not found, using default values")
	}

	// 初始化 CDP 客户端
	cdpClient = NewCDPClient()
	log.Println("✅ CDP Client initialized")

	// 设置数据文件路径
	dir, _ := os.Getwd()
	subscriptionRequestPath = filepath.Join(dir, "../subscription_requests.json")
	paymentsPath = filepath.Join(dir, "../payments.json")
	autoRenewProfilesPath = filepath.Join(dir, "../auto_renew_profiles.json")

	// 加载数据
	loadData()
}

func main() {
	// 注册路由（注意顺序：更具体的路由要放在前面）
	http.HandleFunc("/", handleIndex)
	http.HandleFunc("/subscribe.html", handleSubscribePage)
	http.HandleFunc("/poc/config", handleGetConfig)
	http.HandleFunc("/poc/subscriptions/query", handleQuerySubscription)
	http.HandleFunc("/poc/subscriptions/cancel", handleCancelSubscription)
	http.HandleFunc("/poc/subscriptions/", handleActivateSubscription)
	http.HandleFunc("/poc/subscriptions", handleCreateSubscription)
	http.HandleFunc("/poc/auto-renew/setup", handleAutoRenewSetup)
	http.HandleFunc("/poc/auto-renew/", handleTriggerRenew)

	port := getEnv("PORT", "8080")
	addr := ":" + port
	log.Printf("🚀 Auth Service started at http://localhost%s", addr)
	log.Println("📋 Available endpoints:")
	log.Println("  GET  /subscribe.html - 订阅支付页面")
	log.Println("  POST /poc/subscriptions - 创建订阅请求")
	log.Println("  POST /poc/subscriptions/{order_id}/activate - 激活订阅")
	log.Println("  POST /poc/subscriptions/query - 查询订阅信息")
	log.Println("  POST /poc/subscriptions/cancel - 取消订阅")
	log.Println("  POST /poc/auto-renew/setup - 配置自动续费")
	log.Println("  POST /poc/auto-renew/{identity_address}/trigger - 触发续费")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// handleIndex 首页
func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	html := `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>CDP Subscription Payment POC</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .endpoint { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .method { color: #0066cc; font-weight: bold; }
        pre { background: #eee; padding: 10px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>CDP Subscription Payment POC</h1>
    <p>Phase 4: CDP 订阅支付能力验证</p>

    <h2>可用接口</h2>

    <div class="endpoint">
        <p><span class="method">GET</span> /subscribe.html</p>
        <p>订阅支付页面（通过 Mac 客户端打开）</p>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> /poc/subscriptions</p>
        <p>创建订阅请求</p>
        <pre>{
  "identity_address": "0xYourIdentityAddress",
  "plan_id": "monthly"
}</pre>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> /poc/subscriptions/{order_id}/activate</p>
        <p>激活订阅</p>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> /poc/auto-renew/setup</p>
        <p>配置自动续费</p>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> /poc/auto-renew/{identity_address}/trigger</p>
        <p>手动触发续费</p>
    </div>

    <h2>状态</h2>
    <p>订阅请求: ` + fmt.Sprintf("%d", len(subscriptionRequests)) + `</p>
    <p>支付记录: ` + fmt.Sprintf("%d", len(payments)) + `</p>
    <p>自动续费配置: ` + fmt.Sprintf("%d", len(autoRenewProfiles)) + `</p>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(html))
}

// handleSubscribePage 订阅支付页面
func handleSubscribePage(w http.ResponseWriter, r *http.Request) {
	// 读取 Web 页面文件
	dir, _ := os.Getwd()
	webPagePath := filepath.Join(dir, "../web/subscribe.html")
	content, err := os.ReadFile(webPagePath)
	if err != nil {
		log.Printf("Error reading subscribe.html: %v (path: %s)", err, webPagePath)
		http.Error(w, "Page not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(content)
}

// handleGetConfig 获取服务配置
func handleGetConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	config := map[string]interface{}{
		"service_wallet_address": getEnv("SERVICE_WALLET_ADDRESS", ""),
		"usdc_contract_address":  getEnv("USDC_CONTRACT_ADDRESS", "0x036CbD53842c5426634e7929541eC2318f3dCF7e"),
		"network":                getEnv("NETWORK", "base-sepolia"),
		"subscription_price":     getEnv("SUBSCRIPTION_PRICE_USDC", "1.00"),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(config)
}

// handleCreateSubscription 创建订阅请求
func handleCreateSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		IdentityAddress string `json:"identity_address"`
		PlanID          string `json:"plan_id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// 生成订单 ID
	mu.Lock()
	orderCounter++
	orderID := fmt.Sprintf("ord_%03d", orderCounter)
	mu.Unlock()

	// 创建订阅请求
	subscription := SubscriptionRequest{
		OrderID:         orderID,
		IdentityAddress: req.IdentityAddress,
		PlanID:          req.PlanID,
		Amount:          getEnv("SUBSCRIPTION_PRICE_USDC", "1.00"),
		Currency:        "USDC",
		Network:         getEnv("NETWORK", "base-sepolia"),
		Status:          "pending",
		CreatedAt:       time.Now(),
	}

	// 保存订阅请求
	mu.Lock()
	subscriptionRequests = append(subscriptionRequests, subscription)
	saveData()
	mu.Unlock()

	log.Printf("✅ Created subscription request: order_id=%s identity=%s plan=%s",
		orderID, req.IdentityAddress, req.PlanID)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(subscription)
}

// handleActivateSubscription x402 付费激活订阅
func handleActivateSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 从 URL 提取 order_id
	path := r.URL.Path
	orderID := path[len("/poc/subscriptions/"):]
	if idx := len(orderID) - len("/activate"); idx > 0 && orderID[idx:] == "/activate" {
		orderID = orderID[:idx]
	}

	// 解析请求体获取交易哈希
	var req struct {
		TransactionHash string `json:"transaction_hash"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.TransactionHash == "" {
		http.Error(w, "transaction_hash is required", http.StatusBadRequest)
		return
	}

	// 查找订阅请求
	mu.RLock()
	var subscription *SubscriptionRequest
	for i := range subscriptionRequests {
		if subscriptionRequests[i].OrderID == orderID {
			subscription = &subscriptionRequests[i]
			break
		}
	}
	mu.RUnlock()

	if subscription == nil {
		http.Error(w, "Subscription not found", http.StatusNotFound)
		return
	}

	// 验证支付交易
	// 注意：在真实实现中，这里应该通过 CDP API 或直接查询区块链来验证交易
	// 当前 POC 阶段，我们接受交易哈希并记录
	log.Printf("🔍 Received payment transaction: tx=%s", req.TransactionHash)

	// TODO: 实现真实的链上交易验证
	// 1. 查询交易详情
	// 2. 验证接收地址是否为服务钱包
	// 3. 验证金额是否正确（1 USDC）
	// 4. 验证交易已确认

	payerAddress := "pending_verification" // 从交易中提取

	// 创建支付记录
	payment := Payment{
		OrderID:         orderID,
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    payerAddress,
		PlanID:          subscription.PlanID,
		Amount:          subscription.Amount,
		Currency:        subscription.Currency,
		Network:         subscription.Network,
		PaymentMethod:   "x402",
		TransactionHash: req.TransactionHash,
		PaidAt:          time.Now(),
		Status:          "confirmed",
	}

	// 更新订阅状态
	mu.Lock()
	for i := range subscriptionRequests {
		if subscriptionRequests[i].OrderID == orderID {
			subscriptionRequests[i].Status = "active"
			break
		}
	}
	payments = append(payments, payment)
	saveData()
	mu.Unlock()

	// 打印成功日志
	log.Printf("[SUBSCRIPTION_ACTIVATED] order=%s identity=%s payer=%s amount=%s %s network=%s tx=%s",
		orderID, payment.IdentityAddress, payment.PayerAddress,
		payment.Amount, payment.Currency, payment.Network, payment.TransactionHash)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Subscription activated",
		"payment": payment,
	})
}

// handleAutoRenewSetup 配置自动续费
func handleAutoRenewSetup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req AutoRenewProfile
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// 设置默认值
	req.Status = "active"
	req.CreatedAt = time.Now()
	req.NextRenewAt = time.Now().Add(time.Duration(req.PeriodSeconds) * time.Second)

	// 保存配置
	mu.Lock()
	autoRenewProfiles = append(autoRenewProfiles, req)
	saveData()
	mu.Unlock()

	log.Printf("✅ Auto-renew profile created: identity=%s billing_account=%s permission=%s",
		req.IdentityAddress, req.BillingAccount, req.PermissionHash)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(req)
}

// handleTriggerRenew 手动触发续费
func handleTriggerRenew(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 从 URL 提取 identity_address
	path := r.URL.Path
	identityAddress := path[len("/poc/auto-renew/"):]
	if idx := len(identityAddress) - len("/trigger"); idx > 0 && identityAddress[idx:] == "/trigger" {
		identityAddress = identityAddress[:idx]
	}

	// 查找自动续费配置
	mu.RLock()
	var profile *AutoRenewProfile
	for i := range autoRenewProfiles {
		if autoRenewProfiles[i].IdentityAddress == identityAddress {
			profile = &autoRenewProfiles[i]
			break
		}
	}
	mu.RUnlock()

	if profile == nil {
		http.Error(w, "Auto-renew profile not found", http.StatusNotFound)
		return
	}

	// 使用 CDP 客户端执行 Spend Permission
	log.Printf("🔄 Executing Spend Permission: permission=%s", profile.PermissionHash)

	amount := getEnv("SUBSCRIPTION_PRICE_USDC", "1.00") + "000000" // Convert to wei (USDC has 6 decimals)

	txHash, err := cdpClient.ExecuteSpendPermission(profile.PermissionHash, amount)
	if err != nil {
		log.Printf("❌ Spend Permission execution failed: %v", err)
		http.Error(w, fmt.Sprintf("Spend Permission execution failed: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("✅ Spend Permission executed successfully: tx=%s", txHash)

	// 更新下次续费时间
	mu.Lock()
	for i := range autoRenewProfiles {
		if autoRenewProfiles[i].IdentityAddress == identityAddress {
			autoRenewProfiles[i].NextRenewAt = time.Now().Add(time.Duration(profile.PeriodSeconds) * time.Second)
			break
		}
	}
	saveData()
	mu.Unlock()

	// 打印成功日志
	log.Printf("[SUBSCRIPTION_RENEWED] identity=%s billing_account=%s amount=%s USDC period=%ds tx=%s",
		identityAddress, profile.BillingAccount,
		getEnv("SUBSCRIPTION_PRICE_USDC", "1.00"),
		profile.PeriodSeconds, txHash)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":          true,
		"message":          "Subscription renewed",
		"identity_address": identityAddress,
		"transaction_hash": txHash,
		"next_renew_at":    time.Now().Add(time.Duration(profile.PeriodSeconds) * time.Second),
	})
}

// handleQuerySubscription 查询订阅信息
func handleQuerySubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		IdentityAddress string `json:"identity_address"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.IdentityAddress == "" {
		http.Error(w, "identity_address is required", http.StatusBadRequest)
		return
	}

	// 查找订阅请求
	mu.RLock()
	var subscription *SubscriptionRequest
	for i := range subscriptionRequests {
		if subscriptionRequests[i].IdentityAddress == req.IdentityAddress {
			subscription = &subscriptionRequests[i]
			break
		}
	}

	// 查找自动续费配置
	var autoRenew *AutoRenewProfile
	for i := range autoRenewProfiles {
		if autoRenewProfiles[i].IdentityAddress == req.IdentityAddress {
			autoRenew = &autoRenewProfiles[i]
			break
		}
	}

	// 查找支付记录
	var userPayments []Payment
	for i := range payments {
		if payments[i].IdentityAddress == req.IdentityAddress {
			userPayments = append(userPayments, payments[i])
		}
	}
	mu.RUnlock()

	if subscription == nil {
		http.Error(w, "Subscription not found", http.StatusNotFound)
		return
	}

	log.Printf("📋 Query subscription: identity=%s status=%s", req.IdentityAddress, subscription.Status)

	response := map[string]interface{}{
		"subscription": subscription,
		"payments":     userPayments,
	}

	if autoRenew != nil {
		response["auto_renew"] = autoRenew
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// handleCancelSubscription 取消订阅
func handleCancelSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		IdentityAddress string `json:"identity_address"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.IdentityAddress == "" {
		http.Error(w, "identity_address is required", http.StatusBadRequest)
		return
	}

	// 查找并更新订阅状态
	mu.Lock()
	found := false
	for i := range subscriptionRequests {
		if subscriptionRequests[i].IdentityAddress == req.IdentityAddress {
			subscriptionRequests[i].Status = "cancelled"
			found = true
			break
		}
	}

	// 删除自动续费配置
	var newProfiles []AutoRenewProfile
	for i := range autoRenewProfiles {
		if autoRenewProfiles[i].IdentityAddress != req.IdentityAddress {
			newProfiles = append(newProfiles, autoRenewProfiles[i])
		}
	}
	autoRenewProfiles = newProfiles

	saveData()
	mu.Unlock()

	if !found {
		http.Error(w, "Subscription not found", http.StatusNotFound)
		return
	}

	log.Printf("[SUBSCRIPTION_CANCELLED] identity=%s", req.IdentityAddress)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Subscription cancelled",
	})
}

// loadData 加载数据
func loadData() {
	loadJSON(subscriptionRequestPath, &subscriptionRequests)
	loadJSON(paymentsPath, &payments)
	loadJSON(autoRenewProfilesPath, &autoRenewProfiles)
}

// saveData 保存数据
func saveData() {
	saveJSON(subscriptionRequestPath, subscriptionRequests)
	saveJSON(paymentsPath, payments)
	saveJSON(autoRenewProfilesPath, autoRenewProfiles)
}

// loadJSON 加载 JSON 文件
func loadJSON(path string, v interface{}) {
	data, err := os.ReadFile(path)
	if err != nil {
		log.Printf("Warning: Failed to read %s: %v", path, err)
		return
	}
	if err := json.Unmarshal(data, v); err != nil {
		log.Printf("Warning: Failed to parse %s: %v", path, err)
	}
}

// saveJSON 保存 JSON 文件
func saveJSON(path string, v interface{}) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		log.Printf("Error: Failed to marshal data: %v", err)
		return
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		log.Printf("Error: Failed to write %s: %v", path, err)
	}
}

// getEnv 获取环境变量
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
