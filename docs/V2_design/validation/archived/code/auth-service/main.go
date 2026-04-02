package main

import (
	"bytes"
	"crypto/sha1"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// AllowedIDsConfig 配置文件结构
type AllowedIDsConfig struct {
	Version     string   `json:"version"`
	Description string   `json:"description"`
	AllowedIDs  []string `json:"allowed_ids"`
}

// User 用户信息
type User struct {
	EVMAddress string `json:"evm_address"`
	UUID       string `json:"uuid"`
}

// SyncResponse /v1/sync 响应
type SyncResponse struct {
	Status    string `json:"status"`
	UserCount int    `json:"user_count"`
	Users     []User `json:"users"`
}

// CheckResponse /v1/check 响应
type CheckResponse struct {
	EVMAddress string `json:"evm_address"`
	UUID       string `json:"uuid"`
	Allowed    bool   `json:"allowed"`
}

// HealthResponse /health 响应
type HealthResponse struct {
	Status    string `json:"status"`
	UserCount int    `json:"user_count"`
	Timestamp string `json:"timestamp"`
}

// SingBoxConfig sing-box 配置结构
type SingBoxConfig struct {
	Log          LogConfig          `json:"log"`
	Inbounds     []Inbound          `json:"inbounds"`
	Outbounds    []Outbound         `json:"outbounds"`
	Experimental ExperimentalConfig `json:"experimental"`
}

type LogConfig struct {
	Level string `json:"level"`
}

type Inbound struct {
	Type       string       `json:"type"`
	Tag        string       `json:"tag"`
	Listen     string       `json:"listen"`
	ListenPort int          `json:"listen_port"`
	Users      []VMessUser  `json:"users"`
}

type VMessUser struct {
	Name string `json:"name"`
	UUID string `json:"uuid"`
}

type Outbound struct {
	Type string `json:"type"`
	Tag  string `json:"tag"`
}

type ExperimentalConfig struct {
	ClashAPI ClashAPIConfig `json:"clash_api"`
}

type ClashAPIConfig struct {
	ExternalController string `json:"external_controller"`
	Secret             string `json:"secret"`
}

// AuthService 认证服务
type AuthService struct {
	allowedIDsPath string
	configPath     string
	clashAPIURL    string
	clashAPISecret string
	users          []User
}

// NewAuthService 创建认证服务
func NewAuthService() *AuthService {
	// 获取配置文件路径
	allowedIDsPath := os.Getenv("ALLOWED_IDS_PATH")
	if allowedIDsPath == "" {
		// 默认路径：相对于可执行文件的上级目录
		execPath, _ := os.Executable()
		allowedIDsPath = filepath.Join(filepath.Dir(execPath), "..", "allowed_ids.json")
	}

	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		execPath, _ := os.Executable()
		configPath = filepath.Join(filepath.Dir(execPath), "..", "singbox-server", "config.json")
	}

	clashAPIURL := os.Getenv("CLASH_API_URL")
	if clashAPIURL == "" {
		clashAPIURL = "http://127.0.0.1:9090"
	}

	clashAPISecret := os.Getenv("CLASH_API_SECRET")
	if clashAPISecret == "" {
		clashAPISecret = "poc-secret"
	}

	return &AuthService{
		allowedIDsPath: allowedIDsPath,
		configPath:     configPath,
		clashAPIURL:    clashAPIURL,
		clashAPISecret: clashAPISecret,
		users:          []User{},
	}
}

// evmToUUID 将 EVM 地址转换为 UUID v5
// 使用 NAMESPACE_DNS: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
func evmToUUID(evmAddress string) string {
	// NAMESPACE_DNS 的字节表示
	namespace := []byte{
		0x6b, 0xa7, 0xb8, 0x10,
		0x9d, 0xad,
		0x11, 0xd1,
		0x80, 0xb4,
		0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
	}

	// 转换为小写
	evmAddress = strings.ToLower(evmAddress)

	// 计算 SHA-1
	h := sha1.New()
	h.Write(namespace)
	h.Write([]byte(evmAddress))
	hash := h.Sum(nil)

	// 设置版本位 (version 5)
	hash[6] = (hash[6] & 0x0f) | 0x50

	// 设置变体位
	hash[8] = (hash[8] & 0x3f) | 0x80

	// 格式化为 UUID 字符串
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		binary.BigEndian.Uint32(hash[0:4]),
		binary.BigEndian.Uint16(hash[4:6]),
		binary.BigEndian.Uint16(hash[6:8]),
		binary.BigEndian.Uint16(hash[8:10]),
		hash[10:16])
}

// loadAllowedIDs 加载允许列表
func (s *AuthService) loadAllowedIDs() error {
	data, err := os.ReadFile(s.allowedIDsPath)
	if err != nil {
		return fmt.Errorf("读取配置文件失败: %w", err)
	}

	var config AllowedIDsConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("解析配置文件失败: %w", err)
	}

	// 生成用户列表
	s.users = make([]User, 0, len(config.AllowedIDs))
	for _, evmAddr := range config.AllowedIDs {
		s.users = append(s.users, User{
			EVMAddress: evmAddr,
			UUID:       evmToUUID(evmAddr),
		})
	}

	return nil
}

// generateSingBoxConfig 生成 sing-box 配置
func (s *AuthService) generateSingBoxConfig() *SingBoxConfig {
	// 构建用户列表
	vmessUsers := make([]VMessUser, 0, len(s.users))
	for _, user := range s.users {
		vmessUsers = append(vmessUsers, VMessUser{
			Name: user.EVMAddress,
			UUID: user.UUID,
		})
	}

	return &SingBoxConfig{
		Log: LogConfig{
			Level: "info",
		},
		Inbounds: []Inbound{
			{
				Type:       "vmess",
				Tag:        "vmess-in",
				Listen:     "0.0.0.0",
				ListenPort: 10086,
				Users:      vmessUsers,
			},
		},
		Outbounds: []Outbound{
			{
				Type: "direct",
				Tag:  "direct",
			},
		},
		Experimental: ExperimentalConfig{
			ClashAPI: ClashAPIConfig{
				ExternalController: "127.0.0.1:9090",
				Secret:             s.clashAPISecret,
			},
		},
	}
}

// reloadSingBox 通过 Clash API 重载配置
func (s *AuthService) reloadSingBox(config *SingBoxConfig) error {
	// 获取配置文件的绝对路径
	absPath, err := filepath.Abs(s.configPath)
	if err != nil {
		return fmt.Errorf("获取配置文件绝对路径失败: %w", err)
	}

	// 构造 Clash API 请求体
	reloadPayload := map[string]string{
		"path": absPath,
	}
	payloadJSON, err := json.Marshal(reloadPayload)
	if err != nil {
		return fmt.Errorf("序列化 reload 请求失败: %w", err)
	}

	url := fmt.Sprintf("%s/configs", s.clashAPIURL)
	req, err := http.NewRequest("PUT", url, bytes.NewBuffer(payloadJSON))
	if err != nil {
		return fmt.Errorf("创建请求失败: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if s.clashAPISecret != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", s.clashAPISecret))
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("Clash API 返回错误: %d, %s", resp.StatusCode, string(body))
	}

	return nil
}

// handleSync 处理 /v1/sync 请求
func (s *AuthService) handleSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 加载允许列表
	if err := s.loadAllowedIDs(); err != nil {
		log.Printf("加载允许列表失败: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// 生成配置
	config := s.generateSingBoxConfig()

	// 保存配置到文件
	configJSON, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		log.Printf("序列化配置失败: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if err := os.WriteFile(s.configPath, configJSON, 0644); err != nil {
		log.Printf("保存配置文件失败: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	log.Printf("配置已保存到: %s", s.configPath)

	// 重载 sing-box (可选,如果失败不影响配置保存)
	startTime := time.Now()
	reloadErr := s.reloadSingBox(config)
	reloadDuration := time.Since(startTime)

	status := "synced_and_reloaded"
	if reloadErr != nil {
		log.Printf("重载 sing-box 失败 (配置已保存): %v", reloadErr)
		status = "synced_only"
	}

	log.Printf("同步完成: %d 个用户, reload 耗时: %v", len(s.users), reloadDuration)

	// 返回响应
	response := SyncResponse{
		Status:    status,
		UserCount: len(s.users),
		Users:     s.users,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// handleCheck 处理 /v1/check 请求
func (s *AuthService) handleCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	evmAddress := r.URL.Query().Get("id")
	if evmAddress == "" {
		http.Error(w, "Missing id parameter", http.StatusBadRequest)
		return
	}

	evmAddress = strings.ToLower(evmAddress)
	uuid := evmToUUID(evmAddress)

	// 检查是否在允许列表中
	allowed := false
	for _, user := range s.users {
		if user.EVMAddress == evmAddress {
			allowed = true
			break
		}
	}

	response := CheckResponse{
		EVMAddress: evmAddress,
		UUID:       uuid,
		Allowed:    allowed,
	}

	statusCode := http.StatusOK
	if !allowed {
		statusCode = http.StatusForbidden
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(response)
}

// handleHealth 处理 /health 请求
func (s *AuthService) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	response := HealthResponse{
		Status:    "healthy",
		UserCount: len(s.users),
		Timestamp: time.Now().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	service := NewAuthService()

	// 初始加载配置
	if err := service.loadAllowedIDs(); err != nil {
		log.Printf("警告: 初始加载配置失败: %v", err)
	}

	// 注册路由
	http.HandleFunc("/v1/sync", service.handleSync)
	http.HandleFunc("/v1/check", service.handleCheck)
	http.HandleFunc("/health", service.handleHealth)

	// 获取端口
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := fmt.Sprintf(":%s", port)
	log.Printf("Auth Service 启动在 %s", addr)
	log.Printf("配置文件路径: %s", service.allowedIDsPath)
	log.Printf("Clash API: %s", service.clashAPIURL)
	log.Printf("当前用户数: %d", len(service.users))

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("服务启动失败: %v", err)
	}
}
