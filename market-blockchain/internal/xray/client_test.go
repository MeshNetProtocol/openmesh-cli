package xray

import (
	"context"
	"testing"
	"time"
)

func TestNewClient(t *testing.T) {
	// This test requires a running Xray instance with API enabled
	t.Skip("Requires running Xray instance")

	cfg := Config{
		Address: "127.0.0.1:10085",
		Timeout: 5 * time.Second,
	}

	client, err := NewClient(cfg)
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	if client.address != cfg.Address {
		t.Errorf("Expected address %s, got %s", cfg.Address, client.address)
	}
}

func TestQueryUserTraffic(t *testing.T) {
	t.Skip("Requires running Xray instance with test user")

	cfg := Config{
		Address: "127.0.0.1:10085",
		Timeout: 5 * time.Second,
	}

	client, err := NewClient(cfg)
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	ctx := context.Background()
	traffic, err := client.QueryUserTraffic(ctx, "test@example.com")
	if err != nil {
		t.Fatalf("Failed to query traffic: %v", err)
	}

	if traffic.Email != "test@example.com" {
		t.Errorf("Expected email test@example.com, got %s", traffic.Email)
	}
}
