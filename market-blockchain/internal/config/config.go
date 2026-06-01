package config

import (
	"fmt"
	"os"
)

type Config struct {
	AppEnv string

	ServerPort string

	DatabaseURL string

	BlockchainRPCURL      string
	ContractAddress       string
	PrivateKey            string

	RenewalCheckInterval string

	// Xray integration
	XrayAPIAddress       string
	XrayInboundTag       string
	XrayEnabled          bool
	TrafficStatsInterval string
}

func Load() (*Config, error) {
	cfg := &Config{
		AppEnv:                getEnv("APP_ENV", "development"),
		ServerPort:            getEnv("SERVER_PORT", "8080"),
		DatabaseURL:           getEnv("DATABASE_URL", ""),
		BlockchainRPCURL:      getEnv("BLOCKCHAIN_RPC_URL", ""),
		ContractAddress:       getEnv("CONTRACT_ADDRESS", ""),
		PrivateKey:            getEnv("PRIVATE_KEY", ""),
		RenewalCheckInterval:  getEnv("RENEWAL_CHECK_INTERVAL", "1h"),
		XrayAPIAddress:        getEnv("XRAY_API_ADDRESS", "127.0.0.1:10085"),
		XrayInboundTag:        getEnv("XRAY_INBOUND_TAG", "vless-in"),
		XrayEnabled:           getEnv("XRAY_ENABLED", "false") == "true",
		TrafficStatsInterval:  getEnv("TRAFFIC_STATS_INTERVAL", "10s"),
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}

	return cfg, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
