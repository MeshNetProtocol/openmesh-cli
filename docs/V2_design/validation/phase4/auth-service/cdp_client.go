package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// CDPClient handles interactions with Coinbase Developer Platform
type CDPClient struct {
	apiKey    string
	apiSecret string
	baseURL   string
	client    *http.Client
}

// NewCDPClient creates a new CDP client
func NewCDPClient() *CDPClient {
	return &CDPClient{
		apiKey:    os.Getenv("CDP_API_KEY_NAME"),
		apiSecret: os.Getenv("CDP_API_KEY_PRIVATE_KEY"),
		baseURL:   "https://api.developer.coinbase.com/rpc/v1",
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// VerifyX402Payment verifies an x402 payment transaction
func (c *CDPClient) VerifyX402Payment(txHash string, expectedAmount string, recipientAddress string) (bool, error) {
	// Build the request to get transaction details
	reqBody := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "eth_getTransactionByHash",
		"params":  []string{txHash},
		"id":      1,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return false, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return false, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.client.Do(req)
	if err != nil {
		return false, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Errorf("failed to read response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return false, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Check if transaction exists and is confirmed
	if result["result"] == nil {
		return false, fmt.Errorf("transaction not found")
	}

	tx := result["result"].(map[string]interface{})

	// Verify recipient address
	to := tx["to"].(string)
	if to != recipientAddress {
		return false, fmt.Errorf("recipient address mismatch")
	}

	// Verify amount (value is in wei, need to convert)
	value := tx["value"].(string)
	if value != expectedAmount {
		return false, fmt.Errorf("amount mismatch")
	}

	// Check if transaction is confirmed (has blockNumber)
	if tx["blockNumber"] == nil {
		return false, fmt.Errorf("transaction not confirmed yet")
	}

	return true, nil
}

// CreateSpendPermission creates a spend permission for auto-renewal
func (c *CDPClient) CreateSpendPermission(userAddress string, amount string, period int64) (string, error) {
	// Build the request to create spend permission
	reqBody := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "cdp_createSpendPermission",
		"params": map[string]interface{}{
			"account":  userAddress,
			"spender":  os.Getenv("SERVICE_WALLET_ADDRESS"),
			"token":    os.Getenv("USDC_CONTRACT_ADDRESS"),
			"allowance": amount,
			"period":   period, // in seconds
			"start":    time.Now().Unix(),
			"end":      time.Now().Add(365 * 24 * time.Hour).Unix(), // 1 year
		},
		"id": 1,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if result["error"] != nil {
		return "", fmt.Errorf("CDP API error: %v", result["error"])
	}

	// Extract spend permission ID
	permissionID := result["result"].(map[string]interface{})["permissionId"].(string)
	return permissionID, nil
}

// ExecuteSpendPermission executes a spend permission to charge the user
func (c *CDPClient) ExecuteSpendPermission(permissionID string, amount string) (string, error) {
	// Build the request to execute spend permission
	reqBody := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "cdp_executeSpendPermission",
		"params": map[string]interface{}{
			"permissionId": permissionID,
			"amount":       amount,
		},
		"id": 1,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if result["error"] != nil {
		return "", fmt.Errorf("CDP API error: %v", result["error"])
	}

	// Extract transaction hash
	txHash := result["result"].(map[string]interface{})["transactionHash"].(string)
	return txHash, nil
}

// GetSpendPermissionStatus checks the status of a spend permission
func (c *CDPClient) GetSpendPermissionStatus(permissionID string) (map[string]interface{}, error) {
	reqBody := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "cdp_getSpendPermission",
		"params":  []string{permissionID},
		"id":      1,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if result["error"] != nil {
		return nil, fmt.Errorf("CDP API error: %v", result["error"])
	}

	return result["result"].(map[string]interface{}), nil
}

// GetTransactionDetails gets detailed information about a transaction
func (c *CDPClient) GetTransactionDetails(txHash string) (map[string]interface{}, error) {
	reqBody := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "eth_getTransactionByHash",
		"params":  []string{txHash},
		"id":      1,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if result["error"] != nil {
		return nil, fmt.Errorf("CDP API error: %v", result["error"])
	}

	if result["result"] == nil {
		return nil, fmt.Errorf("transaction not found")
	}

	return result["result"].(map[string]interface{}), nil
}
