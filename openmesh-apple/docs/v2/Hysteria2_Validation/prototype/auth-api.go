package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
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
	"test_blocked_token":  "user_blocked", // 用于测试认证拒绝
}

// 用户状态（实际应该查询数据库）
var userStatus = map[string]string{
	"user_001":     "active",
	"user_002":     "active",
	"user_003":     "active",
	"user_blocked": "blocked", // 被封禁的用户
}

// 用于保护 userStatus 的互斥锁
var userStatusMutex sync.RWMutex

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

	// 检查用户状态（加锁读取）
	userStatusMutex.RLock()
	status := userStatus[userID]
	userStatusMutex.RUnlock()

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

// SetStatusRequest 设置用户状态请求
type SetStatusRequest struct {
	UserID string `json:"user_id"`
	Status string `json:"status"` // "active" or "blocked"
}

// SetStatusResponse 设置用户状态响应
type SetStatusResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// 管理接口：设置用户状态（用于测试）
func setStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SetStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Failed to decode request: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	// 验证状态值
	if req.Status != "active" && req.Status != "blocked" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(SetStatusResponse{
			Success: false,
			Message: "Invalid status, must be 'active' or 'blocked'",
		})
		return
	}

	// 更新用户状态（加锁写入）
	userStatusMutex.Lock()
	userStatus[req.UserID] = req.Status
	userStatusMutex.Unlock()

	log.Printf("User status updated: %s -> %s", req.UserID, req.Status)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(SetStatusResponse{
		Success: true,
		Message: "Status updated successfully",
	})
}

// 管理接口：获取所有用户状态（用于测试）
func getStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	userStatusMutex.RLock()
	statusCopy := make(map[string]string)
	for k, v := range userStatus {
		statusCopy[k] = v
	}
	userStatusMutex.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(statusCopy)
}

func main() {
	http.HandleFunc("/api/v1/hysteria/auth", authHandler)
	http.HandleFunc("/api/v1/admin/set-status", setStatusHandler)
	http.HandleFunc("/api/v1/admin/get-status", getStatusHandler)

	addr := "127.0.0.1:8080"
	log.Printf("Starting auth API server on %s", addr)
	log.Printf("Test tokens:")
	log.Printf("  - test_user_token_123 -> user_001 (active)")
	log.Printf("  - test_user_token_456 -> user_002 (active)")
	log.Printf("  - test_user_token_789 -> user_003 (active)")
	log.Printf("  - test_blocked_token  -> user_blocked (blocked)")
	log.Printf("")
	log.Printf("Admin endpoints:")
	log.Printf("  - POST /api/v1/admin/set-status - Set user status")
	log.Printf("  - GET  /api/v1/admin/get-status - Get all user statuses")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}
