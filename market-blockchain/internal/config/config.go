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
