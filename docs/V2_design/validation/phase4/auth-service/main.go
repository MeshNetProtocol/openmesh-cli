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
)

func init() {
	// 加载环境变量
	if err := godotenv.Load("../.env"); err != nil {
		log.Println("Warning: .env file not found, using default values")
	}

	// 设置数据文件路径
	dir, _ := os.Getwd()
	subscriptionRequestPath = filepath.Join(dir, "../subscription_requests.json")
	paymentsPath = filepath.Join(dir, "../payments.json")
	autoRenewProfilesPath = filepath.Join(dir, "../auto_renew_profiles.json")

	// 加载数据
	loadData()
}

func main() {
	// 注册路由
	http.HandleFunc("/", handleIndex)
	http.HandleFunc("/poc/subscriptions", handleCreateSubscription)
	http.HandleFunc("/poc/subscriptions/", handleActivateSubscription)
	http.HandleFunc("/poc/auto-renew/setup", handleAutoRenewSetup)
	http.HandleFunc("/poc/auto-renew/", handleTriggerRenew)

	port := getEnv("PORT", "8080")
	addr := ":" + port
	log.Printf("🚀 Auth Service started at http://localhost%s", addr)
	log.Println("📋 Available endpoints:")
	log.Println("  POST /poc/subscriptions - 创建订阅请求")
	log.Println("  POST /poc/subscriptions/{order_id}/activate - 激活订阅")
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
        <p><span class="method">POST</span> /poc/subscriptions</p>
        <p>创建订阅请求</p>
        <pre>{
  "identity_address": "0xYourIdentityAddress",
  "plan_id": "weekly_test"
}</pre>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> /poc/subscriptions/{order_id}/activate</p>
        <p>x402 付费激活订阅</p>
    </div>

    <div class="endpoint">
        <p><span class="method">POST</span> /poc/auto-renew/setup</p>
        <p>配置自动续费</p>
        <pre>{
  "identity_address": "0xIdentityAddr",
  "billing_account": "0xBillingSmartAccount",
  "spender_address": "0xAuthSpender",
  "permission_hash": "0xPermissionHash",
  "period_seconds": 604800
}</pre>
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

	// TODO: 这里应该实现真实的 x402 支付验证
	// 目前为了 POC 验证，我们模拟支付成功
	log.Println("⚠️  POC Mode: Simulating x402 payment verification...")

	// 模拟支付记录
	payment := Payment{
		OrderID:         orderID,
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    "0xSimulatedPayerAddress", // TODO: 从 x402 获取真实付款地址
		PlanID:          subscription.PlanID,
		Amount:          subscription.Amount,
		Currency:        subscription.Currency,
		Network:         subscription.Network,
		PaymentMethod:   "x402",
		TransactionHash: fmt.Sprintf("0xsimulated_tx_%d", time.Now().Unix()),
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

	// TODO: 这里应该实现真实的 Spend Permission 扣费
	// 目前为了 POC 验证，我们模拟扣费成功
	log.Println("⚠️  POC Mode: Simulating Spend Permission charge...")

	txHash := fmt.Sprintf("0xrenew_tx_%d", time.Now().Unix())

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
		"next_renew_at":    profile.NextRenewAt,
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
