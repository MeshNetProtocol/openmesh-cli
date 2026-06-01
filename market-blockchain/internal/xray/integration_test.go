// +build integration

package xray

import (
	"context"
	"testing"
	"time"
)

// Integration tests require a running Xray instance with gRPC API enabled
// Run with: go test -tags=integration ./internal/xray/...

func TestXrayIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	client, err := NewClient(Config{
		Address: "127.0.0.1:10085",
		Timeout: 5 * time.Second,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	ctx := context.Background()

	t.Run("AddUser", func(t *testing.T) {
		email := "test@example.com"
		uuid := "550e8400-e29b-41d4-a716-446655440000"

		err := client.AddUser(ctx, email, uuid)
		if err != nil {
			t.Errorf("AddUser failed: %v", err)
		}
	})

	t.Run("QueryUserTraffic", func(t *testing.T) {
		email := "test@example.com"

		traffic, err := client.QueryUserTraffic(ctx, email)
		if err != nil {
			t.Errorf("QueryUserTraffic failed: %v", err)
		}
		if traffic == nil {
			t.Error("Expected traffic data, got nil")
		}
	})

	t.Run("QueryAllUsersTraffic", func(t *testing.T) {
		trafficList, err := client.QueryAllUsersTraffic(ctx)
		if err != nil {
			t.Errorf("QueryAllUsersTraffic failed: %v", err)
		}
		if trafficList == nil {
			t.Error("Expected traffic list, got nil")
		}
	})

	t.Run("RemoveUser", func(t *testing.T) {
		email := "test@example.com"

		err := client.RemoveUser(ctx, email)
		if err != nil {
			t.Errorf("RemoveUser failed: %v", err)
		}
	})
}

func TestTrafficStatsServiceIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// This test requires both Xray and database to be running
	// TODO: Implement full integration test with mock subscription repository
	t.Skip("Full integration test not yet implemented")
}
