package main

import (
	"encoding/json"
	"log"
	"net/http"
)

// AuthRequest 认证请求（来自 Hysteria2）
type AuthRequest struct {
	Addr string `json:"addr"` // 客户端地址
	Auth string `json:"auth"` // 认证凭证（token）
	Tx   uint64 `json:"tx"`   // 客户端带宽速率（bytes/sec），不是累计流量
}

// AuthResponse 认证响应
type AuthResponse struct {
	OK bool   `json:"ok"` // 是否允许连接
	ID string `json:"id"` // 用户 ID
}

// 简单的 token 到 user_id 映射（实际应该查询数据库）
var tokenToUserID = map[string]string{
	"test_user_token_123": "user_001",
	"test_user_token_456": "user_002",
	"test_user_token_789": "user_003",
}

// 用户状态（实际应该查询数据库）
var userStatus = map[string]string{
	"user_001": "active",
	"user_002": "active",
	"user_003": "blocked", // 模拟超额用户
}

func authHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Failed to decode request: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	log.Printf("Auth request: addr=%s, auth=%s, tx=%d (bytes/sec)", req.Addr, req.Auth, req.Tx)

	// 验证 token
	userID, exists := tokenToUserID[req.Auth]
	if !exists {
		log.Printf("Invalid token: %s", req.Auth)
		json.NewEncoder(w).Encode(AuthResponse{OK: false, ID: ""})
		return
	}

	// 检查用户状态
	status := userStatus[userID]
	if status == "blocked" {
		log.Printf("User blocked: %s", userID)
		json.NewEncoder(w).Encode(AuthResponse{OK: false, ID: ""})
		return
	}

	// 认证成功
	log.Printf("Auth success: user_id=%s", userID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(AuthResponse{OK: true, ID: userID})
}

func main() {
	http.HandleFunc("/api/v1/hysteria/auth", authHandler)

	addr := "127.0.0.1:8080"
	log.Printf("Starting auth API server on %s", addr)
	log.Printf("Test tokens:")
	log.Printf("  - test_user_token_123 -> user_001 (active)")
	log.Printf("  - test_user_token_456 -> user_002 (active)")
	log.Printf("  - test_user_token_789 -> user_003 (blocked)")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}
