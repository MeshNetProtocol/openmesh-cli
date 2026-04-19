package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/joho/godotenv"
)

type Plan struct {
	PlanID            string `json:"plan_id"`
	Name              string `json:"name"`
	PeriodDays        int    `json:"period_days"`
	AmountUSDC        int    `json:"amount_usdc"`
	AllowancePeriods  int    `json:"allowance_periods"`
}

type PlansFile struct {
	Plans []Plan `json:"plans"`
}

type AllowanceSnapshot struct {
	ExpectedAllowance  int `json:"expected_allowance"`
	TargetAllowance    int `json:"target_allowance"`
	RemainingAllowance int `json:"remaining_allowance"`
	ExpectedAllowanceBaseUnits string `json:"expected_allowance_base_units,omitempty"`
	TargetAllowanceBaseUnits string `json:"target_allowance_base_units,omitempty"`
	RemainingAllowanceBaseUnits string `json:"remaining_allowance_base_units,omitempty"`
}

type Subscription struct {
	SubscriptionID      string            `json:"subscription_id"`
	IdentityAddress     string            `json:"identity_address"`
	PayerAddress        string            `json:"payer_address"`
	PlanID              string            `json:"plan_id"`
	PlanName            string            `json:"plan_name"`
	Status              string            `json:"status"`
	AutoRenew           bool              `json:"auto_renew"`
	AmountUSDC          int               `json:"amount_usdc"`
	CurrentPeriodStart  time.Time         `json:"current_period_start"`
	CurrentPeriodEnd    time.Time         `json:"current_period_end"`
	PendingPlanID       string            `json:"pending_plan_id,omitempty"`
	PendingPlanName     string            `json:"pending_plan_name,omitempty"`
	AllowanceSnapshot   AllowanceSnapshot `json:"allowance_snapshot"`
	LastChargeID        string            `json:"last_charge_id,omitempty"`
	CreatedAt           time.Time         `json:"created_at"`
	UpdatedAt           time.Time         `json:"updated_at"`
}

type Authorization struct {
	EventID             string    `json:"event_id"`
	EventType           string    `json:"event_type"`
	SubscriptionID      string    `json:"subscription_id,omitempty"`
	IdentityAddress     string    `json:"identity_address"`
	PayerAddress        string    `json:"payer_address"`
	ExpectedAllowance   int       `json:"expected_allowance"`
	TargetAllowance     int       `json:"target_allowance"`
	ExpectedAllowanceBaseUnits string `json:"expected_allowance_base_units,omitempty"`
	TargetAllowanceBaseUnits string `json:"target_allowance_base_units,omitempty"`
	PermitDeadline      time.Time `json:"permit_deadline"`
	PermitDeadlineUnix  int64     `json:"permit_deadline_unix,omitempty"`
	PermitNonce         string    `json:"permit_nonce,omitempty"`
	Signature           string    `json:"signature,omitempty"`
	SignatureV          uint8     `json:"signature_v,omitempty"`
	SignatureR          string    `json:"signature_r,omitempty"`
	SignatureS          string    `json:"signature_s,omitempty"`
	ChainID             int64     `json:"chain_id,omitempty"`
	TokenAddress        string    `json:"token_address,omitempty"`
	SpenderAddress      string    `json:"spender_address,omitempty"`
	OwnerAddress        string    `json:"owner_address,omitempty"`
	AuthorizationTxHash string    `json:"authorization_tx_hash,omitempty"`
	Status              string    `json:"status"`
	CreatedAt           time.Time `json:"created_at"`
}

type Charge struct {
	ChargeID            string    `json:"charge_id"`
	SubscriptionID      string    `json:"subscription_id"`
	IdentityAddress     string    `json:"identity_address"`
	AmountUSDC          int       `json:"amount_usdc"`
	AmountBaseUnits     string    `json:"amount_base_units,omitempty"`
	ChargeType          string    `json:"charge_type"`
	Status              string    `json:"status"`
	PeriodStart         time.Time `json:"period_start"`
	PeriodEnd           time.Time `json:"period_end"`
	TxHash              string    `json:"tx_hash,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

type EventRecord struct {
	EventID             string    `json:"event_id"`
	EventType           string    `json:"event_type"`
	ChargeID            string    `json:"charge_id,omitempty"`
	IdentityAddress     string    `json:"identity_address"`
	PayerAddress        string    `json:"payer_address,omitempty"`
	ExpectedAllowance   int       `json:"expected_allowance,omitempty"`
	TargetAllowance     int       `json:"target_allowance,omitempty"`
	AmountUSDC          int       `json:"amount_usdc,omitempty"`
	TxHash              string    `json:"tx_hash,omitempty"`
	Status              string    `json:"status"`
	CreatedAt           time.Time `json:"created_at"`
}

type CreateSubscriptionRequest struct {
	IdentityAddress string `json:"identity_address"`
	PayerAddress    string `json:"payer_address"`
	PlanID          string `json:"plan_id"`
}

type PreparePermitRequest struct {
	SubscriptionID  string `json:"subscription_id"`
	TargetAllowance int    `json:"target_allowance,omitempty"`
	DeadlineMinutes int    `json:"deadline_minutes,omitempty"`
}

type PermitRequest struct {
	SubscriptionID      string `json:"subscription_id"`
	ExpectedAllowance   int    `json:"expected_allowance"`
	TargetAllowance     int    `json:"target_allowance"`
	PermitDeadlineMins  int    `json:"permit_deadline_minutes,omitempty"`
	Deadline            int64  `json:"deadline,omitempty"`
	Signature           string `json:"signature,omitempty"`
	SignatureV          uint8  `json:"signature_v,omitempty"`
	SignatureR          string `json:"signature_r,omitempty"`
	SignatureS          string `json:"signature_s,omitempty"`
	PermitNonce         string `json:"permit_nonce,omitempty"`
	ChainID             int64  `json:"chain_id,omitempty"`
	TokenAddress        string `json:"token_address,omitempty"`
	SpenderAddress      string `json:"spender_address,omitempty"`
	OwnerAddress        string `json:"owner_address,omitempty"`
}

type ChargeRequest struct {
	SubscriptionID string `json:"subscription_id"`
}

type CancelRequest struct {
	SubscriptionID string `json:"subscription_id"`
}

type ChangePlanRequest struct {
	SubscriptionID string `json:"subscription_id"`
	PlanID         string `json:"plan_id"`
}

type QuerySubscriptionRequest struct {
	IdentityAddress string `json:"identity_address"`
	SubscriptionID  string `json:"subscription_id"`
}

type ExpireSubscriptionRequest struct {
	SubscriptionID string `json:"subscription_id"`
	ExpiredHoursAgo int   `json:"expired_hours_ago"`
}

var (
	mu                 sync.RWMutex
	plansFile          PlansFile
	subscriptions      []Subscription
	authorizations     []Authorization
	charges            []Charge
	events             []EventRecord
	plansPath          string
	subscriptionsPath  string
	authorizationsPath string
	chargesPath        string
	eventsPath         string
	relayerClient      *RelayerClient
)

func init() {
	if err := godotenv.Load("../.env"); err != nil {
		log.Println("Warning: .env file not found, using default values")
	}

	dir, _ := os.Getwd()
	plansPath = filepath.Join(dir, "../plans.json")
	subscriptionsPath = filepath.Join(dir, "../subscriptions.json")
	authorizationsPath = filepath.Join(dir, "../authorizations.json")
	chargesPath = filepath.Join(dir, "../charges.json")
	eventsPath = filepath.Join(dir, "../events.json")

	loadData()

	if os.Getenv("ENABLE_CHAIN_SUBMISSION") == "true" {
		client, err := NewRelayerClient()
		if err != nil {
			log.Printf("Warning: failed to initialize relayer client: %v", err)
			log.Println("Chain submission will be disabled")
		} else {
			relayerClient = client
			log.Println("✅ Relayer client initialized for on-chain submission")
		}
	}
}

func main() {
	http.HandleFunc("/", handleIndex)
	http.HandleFunc("/subscribe.html", handleSubscribePage)
	http.HandleFunc("/poc/config", handleGetConfig)
	http.HandleFunc("/poc/plans", handleGetPlans)
	http.HandleFunc("/poc/subscriptions", handleCreateSubscription)
	http.HandleFunc("/poc/subscriptions/query", handleQuerySubscription)
	http.HandleFunc("/poc/subscriptions/cancel", handleCancelSubscription)
	http.HandleFunc("/poc/subscriptions/upgrade", handleUpgradeSubscription)
	http.HandleFunc("/poc/subscriptions/downgrade", handleDowngradeSubscription)
	http.HandleFunc("/poc/authorizations/prepare", handlePreparePermitAuthorization)
	http.HandleFunc("/poc/authorizations/permit", handlePermitAuthorization)
	http.HandleFunc("/poc/charges/initial", handleInitialCharge)
	http.HandleFunc("/poc/charges/renew", handleRenewCharge)
	http.HandleFunc("/poc/test/expire", handleExpireSubscription)
	http.HandleFunc("/poc/debug/state", handleDebugState)

	port := getEnv("PORT", "8080")
	addr := ":" + port
	log.Printf("🚀 Phase 4 POC service started at http://localhost%s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	mu.RLock()
	subCount := len(subscriptions)
	authCount := len(authorizations)
	chargeCount := len(charges)
	eventCount := len(events)
	mu.RUnlock()

	html := `<!DOCTYPE html>
	<html>
	<head>
	    <meta charset="UTF-8">
	    <title>Phase 4 POC</title>
	    <style>
	        body { font-family: Arial, sans-serif; max-width: 920px; margin: 40px auto; padding: 20px; }
	        .box { background: #f6f6f6; padding: 16px; margin: 12px 0; border-radius: 8px; }
	        pre { background: #eee; padding: 12px; overflow-x: auto; }
	    </style>
	</head>
	<body>
	    <h1>Phase 4 文件型订阅 POC</h1>
	    <p>围绕 VPNCreditVaultV4 验证 subscription / authorization / charge 业务闭环。</p>
	    <div class="box">订阅数: ` + fmt.Sprintf("%d", subCount) + `</div>
	    <div class="box">授权数: ` + fmt.Sprintf("%d", authCount) + `</div>
	    <div class="box">扣费数: ` + fmt.Sprintf("%d", chargeCount) + `</div>
	    <div class="box">事件数: ` + fmt.Sprintf("%d", eventCount) + `</div>
	    <h2>主要接口</h2>
	    <pre>GET  /poc/plans
POST /poc/subscriptions
POST /poc/authorizations/permit
POST /poc/charges/initial
POST /poc/charges/renew
POST /poc/subscriptions/cancel
POST /poc/subscriptions/upgrade
POST /poc/subscriptions/downgrade
POST /poc/subscriptions/query</pre>
	</body>
	</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(html))
}

func handleSubscribePage(w http.ResponseWriter, r *http.Request) {
	dir, _ := os.Getwd()
	webPagePath := filepath.Join(dir, "../web/subscribe.html")
	content, err := os.ReadFile(webPagePath)
	if err != nil {
		http.Error(w, "Page not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(content)
}

func handleGetConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"service_wallet_address": getEnv("SERVICE_WALLET_ADDRESS", ""),
		"usdc_contract_address":  getEnv("USDC_CONTRACT_ADDRESS", "0x036CbD53842c5426634e7929541eC2318f3dCF7e"),
		"vault_contract_address": getEnv("VAULT_CONTRACT_ADDRESS", ""),
		"network":                getEnv("NETWORK", "base-sepolia"),
	})
}

func handleGetPlans(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	mu.RLock()
	defer mu.RUnlock()
	respondJSON(w, http.StatusOK, plansFile)
}

func handleCreateSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CreateSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.IdentityAddress == "" || req.PayerAddress == "" || req.PlanID == "" {
		http.Error(w, "identity_address, payer_address and plan_id are required", http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	plan, ok := findPlan(req.PlanID)
	if !ok {
		http.Error(w, "plan not found", http.StatusNotFound)
		return
	}

	subscriptionID := fmt.Sprintf("sub_%d", time.Now().UnixNano())
	now := time.Now().UTC()
	periodEnd := now.AddDate(0, 0, plan.PeriodDays)
	allowanceTarget := plan.AmountUSDC * plan.AllowancePeriods

	sub := Subscription{
		SubscriptionID:     subscriptionID,
		IdentityAddress:    req.IdentityAddress,
		PayerAddress:       req.PayerAddress,
		PlanID:             plan.PlanID,
		PlanName:           plan.Name,
		Status:             "pending",
		AutoRenew:          true,
		AmountUSDC:         plan.AmountUSDC,
		CurrentPeriodStart: now,
		CurrentPeriodEnd:   periodEnd,
		AllowanceSnapshot: AllowanceSnapshot{
			ExpectedAllowance:  0,
			TargetAllowance:    allowanceTarget,
			RemainingAllowance: allowanceTarget,
		},
		CreatedAt: now,
		UpdatedAt: now,
	}

	subscriptions = append(subscriptions, sub)
	saveData()
	respondJSON(w, http.StatusOK, sub)
}

func handlePreparePermitAuthorization(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req PreparePermitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.SubscriptionID == "" {
		http.Error(w, "subscription_id is required", http.StatusBadRequest)
		return
	}

	mu.RLock()
	sub, _ := findSubscriptionByID(req.SubscriptionID)
	mu.RUnlock()
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}

	targetAllowance := req.TargetAllowance
	if targetAllowance <= 0 {
		targetAllowance = sub.AllowanceSnapshot.TargetAllowance
		if targetAllowance <= 0 {
			targetAllowance = sub.AmountUSDC
		}
	}

	deadlineMinutes := req.DeadlineMinutes
	if deadlineMinutes <= 0 {
		deadlineMinutes = 30
	}

	now := time.Now().UTC()
	deadline := now.Add(time.Duration(deadlineMinutes) * time.Minute)
	chainID := int64(84532)
	if strings.EqualFold(getEnv("NETWORK", "base-sepolia"), "base-mainnet") || strings.EqualFold(getEnv("NETWORK", "base"), "base") {
		chainID = 8453
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"subscription_id":      sub.SubscriptionID,
		"identity_address":     sub.IdentityAddress,
		"payer_address":        sub.PayerAddress,
		"owner_address":        sub.PayerAddress,
		"spender_address":      getEnv("VAULT_CONTRACT_ADDRESS", ""),
		"token_address":        getEnv("USDC_CONTRACT_ADDRESS", "0x036CbD53842c5426634e7929541eC2318f3dCF7e"),
		"chain_id":             chainID,
		"permit_nonce":         fmt.Sprintf("poc-%d", now.UnixNano()),
		"expected_allowance":   sub.AllowanceSnapshot.ExpectedAllowance,
		"target_allowance":     targetAllowance,
		"deadline_minutes":     deadlineMinutes,
		"permit_deadline":      deadline.Format(time.RFC3339),
		"permit_deadline_unix": deadline.Unix(),
		"domain": map[string]interface{}{
			"name":              "USD Coin",
			"version":           "2",
			"chainId":           chainID,
			"verifyingContract": getEnv("USDC_CONTRACT_ADDRESS", "0x036CbD53842c5426634e7929541eC2318f3dCF7e"),
		},
		"types": map[string]interface{}{
			"Permit": []map[string]string{
				{"name": "owner", "type": "address"},
				{"name": "spender", "type": "address"},
				{"name": "value", "type": "uint256"},
				{"name": "nonce", "type": "uint256"},
				{"name": "deadline", "type": "uint256"},
			},
		},
		"message": map[string]interface{}{
			"owner":    sub.PayerAddress,
			"spender":  getEnv("VAULT_CONTRACT_ADDRESS", ""),
			"value":    targetAllowance,
			"nonce":    0,
			"deadline": deadline.Unix(),
		},
	})
}

func handlePermitAuthorization(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req PermitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	sub, idx := findSubscriptionByID(req.SubscriptionID)
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}

	expectedAllowance := req.ExpectedAllowance
	if expectedAllowance == 0 {
		expectedAllowance = sub.AllowanceSnapshot.ExpectedAllowance
	}

	targetAllowance := req.TargetAllowance
	if targetAllowance <= 0 {
		targetAllowance = sub.AllowanceSnapshot.TargetAllowance
	}
	if targetAllowance <= 0 {
		http.Error(w, "target_allowance must be greater than zero", http.StatusBadRequest)
		return
	}

	var permitDeadline time.Time
	if req.Deadline > 0 {
		permitDeadline = time.Unix(req.Deadline, 0).UTC()
	} else {
		deadlineMinutes := req.PermitDeadlineMins
		if deadlineMinutes <= 0 {
			deadlineMinutes = 30
		}
		permitDeadline = time.Now().UTC().Add(time.Duration(deadlineMinutes) * time.Minute)
	}

	if req.SignatureR == "" || req.SignatureS == "" {
		http.Error(w, "signature_r and signature_s are required", http.StatusBadRequest)
		return
	}

	chainID := req.ChainID
	if chainID == 0 {
		chainID = inferChainID()
	}
	ownerAddress := req.OwnerAddress
	if ownerAddress == "" {
		ownerAddress = sub.PayerAddress
	}
	tokenAddress := req.TokenAddress
	if tokenAddress == "" {
		tokenAddress = getEnv("USDC_CONTRACT_ADDRESS", "0x036CbD53842c5426634e7929541eC2318f3dCF7e")
	}
	spenderAddress := req.SpenderAddress
	if spenderAddress == "" {
		spenderAddress = getEnv("VAULT_CONTRACT_ADDRESS", "")
	}

	now := time.Now().UTC()
	authorizationStatus := "confirmed"
	authorizationTxHash := ""

	if relayerClient != nil {
		txHash, err := relayerClient.AuthorizeChargeWithPermit(AuthorizePermitChainRequest{
			UserAddress:       ownerAddress,
			IdentityAddress:   sub.IdentityAddress,
			ExpectedAllowance: expectedAllowance,
			TargetAllowance:   targetAllowance,
			Deadline:          permitDeadline.Unix(),
			SignatureV:        req.SignatureV,
			SignatureR:        req.SignatureR,
			SignatureS:        req.SignatureS,
		})
		if err != nil {
			http.Error(w, fmt.Sprintf("on-chain authorization failed: %v", err), http.StatusBadGateway)
			return
		}
		authorizationTxHash = txHash
		authorizationStatus = "submitted"
		log.Printf("✅ Authorization submitted on-chain: %s", txHash)
	} else {
		log.Println("⚠️  Relayer unavailable, storing authorization without chain submission")
	}

	auth := Authorization{
		EventID:            fmt.Sprintf("evt_auth_%d", now.UnixNano()),
		EventType:          "charge_authorized",
		SubscriptionID:     sub.SubscriptionID,
		IdentityAddress:    sub.IdentityAddress,
		PayerAddress:       sub.PayerAddress,
		ExpectedAllowance:  expectedAllowance,
		TargetAllowance:    targetAllowance,
		PermitDeadline:     permitDeadline,
		PermitDeadlineUnix: permitDeadline.Unix(),
		PermitNonce:        req.PermitNonce,
		Signature:          req.Signature,
		SignatureV:         req.SignatureV,
		SignatureR:         req.SignatureR,
		SignatureS:         req.SignatureS,
		ChainID:            chainID,
		TokenAddress:       tokenAddress,
		SpenderAddress:     spenderAddress,
		OwnerAddress:       ownerAddress,
		AuthorizationTxHash: authorizationTxHash,
		Status:             authorizationStatus,
		CreatedAt:          now,
	}

	authorizations = append(authorizations, auth)
	events = append(events, EventRecord{
		EventID:         fmt.Sprintf("evt_bind_%d", now.UnixNano()),
		EventType:       "identity_bound",
		IdentityAddress: sub.IdentityAddress,
		PayerAddress:    sub.PayerAddress,
		Status:          "confirmed",
		CreatedAt:       now,
	})
	events = append(events, EventRecord{
		EventID:           auth.EventID,
		EventType:         auth.EventType,
		IdentityAddress:   auth.IdentityAddress,
		PayerAddress:      auth.PayerAddress,
		ExpectedAllowance: auth.ExpectedAllowance,
		TargetAllowance:   auth.TargetAllowance,
		TxHash:            auth.AuthorizationTxHash,
		Status:            auth.Status,
		CreatedAt:         auth.CreatedAt,
	})

	sub.AllowanceSnapshot.ExpectedAllowance = expectedAllowance
	sub.AllowanceSnapshot.TargetAllowance = targetAllowance
	sub.AllowanceSnapshot.RemainingAllowance = targetAllowance
	sub.UpdatedAt = now
	subscriptions[idx] = *sub
	saveData()

	respondJSON(w, http.StatusOK, auth)
}

func handleInitialCharge(w http.ResponseWriter, r *http.Request) {
	handleCharge(w, r, "initial")
}

func handleRenewCharge(w http.ResponseWriter, r *http.Request) {
	handleCharge(w, r, "renewal")
}

func handleCharge(w http.ResponseWriter, r *http.Request, chargeType string) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ChargeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	sub, idx := findSubscriptionByID(req.SubscriptionID)
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}

	now := time.Now().UTC()
	if chargeType == "renewal" {
		if !sub.AutoRenew {
			http.Error(w, "subscription auto renew disabled", http.StatusBadRequest)
			return
		}
		if now.Before(sub.CurrentPeriodEnd) {
			http.Error(w, "subscription not due for renewal", http.StatusBadRequest)
			return
		}
	}

	chargeID := buildChargeID(sub.SubscriptionID, sub.CurrentPeriodStart, sub.CurrentPeriodEnd, chargeType)
	if chargeExists(chargeID) {
		respondJSON(w, http.StatusOK, map[string]interface{}{
			"success": true,
			"message": "charge already exists",
			"charge_id": chargeID,
		})
		return
	}

	charge := Charge{
		ChargeID:        chargeID,
		SubscriptionID:  sub.SubscriptionID,
		IdentityAddress: sub.IdentityAddress,
		AmountUSDC:      sub.AmountUSDC,
		ChargeType:      chargeType,
		Status:          "confirmed",
		PeriodStart:     sub.CurrentPeriodStart,
		PeriodEnd:       sub.CurrentPeriodEnd,
		TxHash:          fmt.Sprintf("0xmock_%d", now.UnixNano()),
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	charges = append(charges, charge)
	events = append(events, EventRecord{
		EventID:         fmt.Sprintf("evt_charge_%d", now.UnixNano()),
		EventType:       "identity_charged",
		ChargeID:        charge.ChargeID,
		IdentityAddress: sub.IdentityAddress,
		PayerAddress:    sub.PayerAddress,
		AmountUSDC:      charge.AmountUSDC,
		TxHash:          charge.TxHash,
		Status:          "confirmed",
		CreatedAt:       now,
	})

	sub.LastChargeID = charge.ChargeID
	if sub.AllowanceSnapshot.RemainingAllowance >= charge.AmountUSDC {
		sub.AllowanceSnapshot.RemainingAllowance -= charge.AmountUSDC
	}
	if chargeType == "initial" {
		sub.Status = "active"
	}
	if chargeType == "renewal" {
		plan, ok := findPlan(sub.PlanID)
		if ok {
			sub.CurrentPeriodStart = sub.CurrentPeriodEnd
			sub.CurrentPeriodEnd = sub.CurrentPeriodEnd.AddDate(0, 0, plan.PeriodDays)
		}
		if sub.PendingPlanID != "" {
			pendingPlan, found := findPlan(sub.PendingPlanID)
			if found {
				sub.PlanID = pendingPlan.PlanID
				sub.PlanName = pendingPlan.Name
				sub.AmountUSDC = pendingPlan.AmountUSDC
				sub.PendingPlanID = ""
				sub.PendingPlanName = ""
			}
		}
		sub.Status = "active"
	}
	sub.UpdatedAt = now
	subscriptions[idx] = *sub
	saveData()

	respondJSON(w, http.StatusOK, charge)
}

func handleCancelSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CancelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	sub, idx := findSubscriptionByID(req.SubscriptionID)
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}

	sub.AutoRenew = false
	sub.Status = "cancelled"
	sub.UpdatedAt = time.Now().UTC()
	subscriptions[idx] = *sub
	saveData()
	respondJSON(w, http.StatusOK, sub)
}

func handleUpgradeSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ChangePlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	sub, idx := findSubscriptionByID(req.SubscriptionID)
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}
	plan, ok := findPlan(req.PlanID)
	if !ok {
		http.Error(w, "plan not found", http.StatusNotFound)
		return
	}

	now := time.Now().UTC()
	diff := plan.AmountUSDC - sub.AmountUSDC
	if diff < 0 {
		diff = 0
	}
	chargeID := buildChargeID(sub.SubscriptionID, now, sub.CurrentPeriodEnd, "upgrade_proration")
	if !chargeExists(chargeID) {
		charges = append(charges, Charge{
			ChargeID:        chargeID,
			SubscriptionID:  sub.SubscriptionID,
			IdentityAddress: sub.IdentityAddress,
			AmountUSDC:      diff,
			ChargeType:      "upgrade_proration",
			Status:          "confirmed",
			PeriodStart:     now,
			PeriodEnd:       sub.CurrentPeriodEnd,
			TxHash:          fmt.Sprintf("0xmock_upgrade_%d", now.UnixNano()),
			CreatedAt:       now,
			UpdatedAt:       now,
		})
	}

	sub.PlanID = plan.PlanID
	sub.PlanName = plan.Name
	sub.AmountUSDC = plan.AmountUSDC
	sub.LastChargeID = chargeID
	sub.UpdatedAt = now
	subscriptions[idx] = *sub
	saveData()
	respondJSON(w, http.StatusOK, sub)
}

func handleDowngradeSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ChangePlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	sub, idx := findSubscriptionByID(req.SubscriptionID)
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}
	plan, ok := findPlan(req.PlanID)
	if !ok {
		http.Error(w, "plan not found", http.StatusNotFound)
		return
	}

	sub.PendingPlanID = plan.PlanID
	sub.PendingPlanName = plan.Name
	sub.UpdatedAt = time.Now().UTC()
	subscriptions[idx] = *sub
	saveData()
	respondJSON(w, http.StatusOK, sub)
}

func handleQuerySubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req QuerySubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	mu.RLock()
	defer mu.RUnlock()

	var found *Subscription
	for i := range subscriptions {
		if (req.SubscriptionID != "" && subscriptions[i].SubscriptionID == req.SubscriptionID) ||
			(req.IdentityAddress != "" && strings.EqualFold(subscriptions[i].IdentityAddress, req.IdentityAddress)) {
			copy := subscriptions[i]
			found = &copy
			break
		}
	}
	if found == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}

	var relatedCharges []Charge
	for i := range charges {
		if charges[i].SubscriptionID == found.SubscriptionID {
			relatedCharges = append(relatedCharges, charges[i])
		}
	}

	var relatedAuth []Authorization
	for i := range authorizations {
		if strings.EqualFold(authorizations[i].IdentityAddress, found.IdentityAddress) {
			relatedAuth = append(relatedAuth, authorizations[i])
		}
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"subscription":   found,
		"authorizations": relatedAuth,
		"charges":        relatedCharges,
	})
}

func handleExpireSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ExpireSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.SubscriptionID == "" {
		http.Error(w, "subscription_id is required", http.StatusBadRequest)
		return
	}

	hoursAgo := req.ExpiredHoursAgo
	if hoursAgo <= 0 {
		hoursAgo = 1
	}

	mu.Lock()
	defer mu.Unlock()

	sub, idx := findSubscriptionByID(req.SubscriptionID)
	if sub == nil {
		http.Error(w, "subscription not found", http.StatusNotFound)
		return
	}

	now := time.Now().UTC()
	expiredEnd := now.Add(-time.Duration(hoursAgo) * time.Hour)
	periodDuration := sub.CurrentPeriodEnd.Sub(sub.CurrentPeriodStart)
	if periodDuration <= 0 {
		periodDuration = 30 * 24 * time.Hour
	}
	sub.CurrentPeriodEnd = expiredEnd
	sub.CurrentPeriodStart = expiredEnd.Add(-periodDuration)
	if sub.AutoRenew {
		sub.Status = "active"
	} else {
		sub.Status = "cancelled"
	}
	sub.UpdatedAt = now
	subscriptions[idx] = *sub
	saveData()

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"success": true,
		"message": "subscription expiry simulated",
		"subscription": sub,
	})
}

func handleDebugState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	mu.RLock()
	defer mu.RUnlock()

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"plans":          plansFile.Plans,
		"subscriptions":  subscriptions,
		"authorizations": authorizations,
		"charges":        charges,
		"events":         events,
	})
}

func loadData() {
	loadJSON(plansPath, &plansFile)
	loadJSON(subscriptionsPath, &subscriptions)
	loadJSON(authorizationsPath, &authorizations)
	loadJSON(chargesPath, &charges)
	loadJSON(eventsPath, &events)
}

func saveData() {
	saveJSON(subscriptionsPath, subscriptions)
	saveJSON(authorizationsPath, authorizations)
	saveJSON(chargesPath, charges)
	saveJSON(eventsPath, events)
}

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

func findPlan(planID string) (Plan, bool) {
	for _, plan := range plansFile.Plans {
		if plan.PlanID == planID {
			return plan, true
		}
	}
	return Plan{}, false
}

func findSubscriptionByID(subscriptionID string) (*Subscription, int) {
	for i := range subscriptions {
		if subscriptions[i].SubscriptionID == subscriptionID {
			copy := subscriptions[i]
			return &copy, i
		}
	}
	return nil, -1
}

func inferChainID() int64 {
	network := strings.ToLower(getEnv("NETWORK", "base-sepolia"))
	switch network {
	case "base", "base-mainnet", "mainnet":
		return 8453
	default:
		return 84532
	}
}

func chargeExists(chargeID string) bool {
	for i := range charges {
		if charges[i].ChargeID == chargeID {
			return true
		}
	}
	return false
}

func buildChargeID(subscriptionID string, periodStart, periodEnd time.Time, chargeType string) string {
	return fmt.Sprintf("%s:%s:%s:%s", subscriptionID, periodStart.UTC().Format(time.RFC3339), periodEnd.UTC().Format(time.RFC3339), chargeType)
}

func respondJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
