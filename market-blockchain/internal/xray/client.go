package xray

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Client wraps Xray gRPC API client
type Client struct {
	conn    *grpc.ClientConn
	address string
}

// Config holds Xray client configuration
type Config struct {
	Address string // Xray API address (e.g., "127.0.0.1:10085")
	Timeout time.Duration
}

// NewClient creates a new Xray gRPC client
func NewClient(cfg Config) (*Client, error) {
	if cfg.Timeout == 0 {
		cfg.Timeout = 5 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), cfg.Timeout)
	defer cancel()

	conn, err := grpc.DialContext(ctx, cfg.Address,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Xray API at %s: %w", cfg.Address, err)
	}

	return &Client{
		conn:    conn,
		address: cfg.Address,
	}, nil
}

// Close closes the gRPC connection
func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// UserTraffic represents user traffic statistics
type UserTraffic struct {
	Email    string
	Uplink   int64
	Downlink int64
}

// AddUser adds a user to Xray
func (c *Client) AddUser(ctx context.Context, email, uuid string) error {
	// TODO: Implement using Xray HandlerService.AlterInbound
	return fmt.Errorf("not implemented yet")
}

// RemoveUser removes a user from Xray
func (c *Client) RemoveUser(ctx context.Context, email string) error {
	// TODO: Implement using Xray HandlerService.AlterInbound
	return fmt.Errorf("not implemented yet")
}

// QueryUserTraffic queries traffic statistics for a specific user
func (c *Client) QueryUserTraffic(ctx context.Context, email string) (*UserTraffic, error) {
	// TODO: Implement using Xray StatsService.QueryStats
	return nil, fmt.Errorf("not implemented yet")
}

// QueryAllUsersTraffic queries traffic statistics for all users
func (c *Client) QueryAllUsersTraffic(ctx context.Context) ([]*UserTraffic, error) {
	// TODO: Implement using Xray StatsService.QueryStats with pattern
	return nil, fmt.Errorf("not implemented yet")
}
