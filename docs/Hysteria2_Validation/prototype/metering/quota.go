package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// QuotaChecker 配额检查器
type QuotaChecker struct {
	db         *Database
	authAPIURL string
	client     *http.Client
}

// NewQuotaChecker 创建配额检查器
func NewQuotaChecker(db *Database, authAPIURL string) *QuotaChecker {
	return &QuotaChecker{
		db:         db,
		authAPIURL: authAPIURL,
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// setUserStatus 调用认证 API 设置用户状态
func (q *QuotaChecker) setUserStatus(userID, status string) error {
	url := fmt.Sprintf("%s/api/v1/admin/set-status", q.authAPIURL)

	payload := map[string]string{
		"user_id": userID,
		"status":  status,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := q.client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to set user status: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(bodyBytes))
	}

	return nil
}

// kickUser 从节点踢出用户
func (q *QuotaChecker) kickUser(node Node, userID string) error {
	url := fmt.Sprintf("%s/kick", node.TrafficAPIURL)

	payload := []string{userID}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", node.Secret)

	resp, err := q.client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to kick user: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(bodyBytes))
	}

	return nil
}

// CheckAndEnforce 检查配额并执行封禁
func (q *QuotaChecker) CheckAndEnforce(userID string) error {
	// 1. 获取用户信息
	user, err := q.db.GetUser(userID)
	if err != nil {
		return fmt.Errorf("failed to get user: %w", err)
	}

	// 2. 检查是否超额
	if user.Used <= user.Quota {
		return nil // 未超额
	}

	// 3. 用户超额，执行封禁流程
	log.Printf("User %s exceeded quota: used=%d, quota=%d", userID, user.Used, user.Quota)

	// 3.1 标记用户为 blocked
	if err := q.setUserStatus(userID, "blocked"); err != nil {
		return fmt.Errorf("failed to set user status: %w", err)
	}
	log.Printf("Marked user %s as blocked in auth API", userID)

	// 3.2 从所有节点踢出用户
	nodes, err := q.db.GetNodes()
	if err != nil {
		return fmt.Errorf("failed to get nodes: %w", err)
	}

	for _, node := range nodes {
		if err := q.kickUser(node, userID); err != nil {
			log.Printf("Failed to kick user %s from node %s: %v", userID, node.NodeID, err)
			// 继续踢出其他节点
		} else {
			log.Printf("Kicked user %s from node %s", userID, node.NodeID)
		}
	}

	// 3.3 更新数据库状态
	if err := q.db.UpdateUserStatus(userID, "blocked"); err != nil {
		return fmt.Errorf("failed to update user status in database: %w", err)
	}

	log.Printf("User %s has been blocked successfully", userID)
	return nil
}

// CheckAll 检查所有用户的配额
func (q *QuotaChecker) CheckAll() error {
	users, err := q.db.GetAllUsers()
	if err != nil {
		return fmt.Errorf("failed to get all users: %w", err)
	}

	for _, user := range users {
		// 只检查 active 用户
		if user.Status != "active" {
			continue
		}

		if err := q.CheckAndEnforce(user.UserID); err != nil {
			log.Printf("Failed to check quota for user %s: %v", user.UserID, err)
			// 继续检查其他用户
		}
	}

	return nil
}
