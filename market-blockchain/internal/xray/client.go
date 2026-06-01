package xray

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	proxymancommand "github.com/xtls/xray-core/app/proxyman/command"
	statscommand "github.com/xtls/xray-core/app/stats/command"
	"github.com/xtls/xray-core/common/protocol"
	"github.com/xtls/xray-core/common/serial"
	vless "github.com/xtls/xray-core/proxy/vless"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
)

// Client wraps Xray gRPC API client
type Client struct {
	conn       *grpc.ClientConn
	address    string
	inboundTag string
}

// Config holds Xray client configuration
type Config struct {
	Address    string // Xray API address (e.g., "127.0.0.1:10085")
	InboundTag string // Xray inbound tag used for user management
	Timeout    time.Duration
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
		conn:       conn,
		address:    cfg.Address,
		inboundTag: cfg.InboundTag,
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
	handlerClient := proxymancommand.NewHandlerServiceClient(c.conn)
	_, err := handlerClient.AlterInbound(ctx, &proxymancommand.AlterInboundRequest{
		Tag: c.inboundTag,
		Operation: serial.ToTypedMessage(&proxymancommand.AddUserOperation{
			User: &protocol.User{
				Level: 0,
				Email: email,
				Account: serial.ToTypedMessage(&vless.Account{
					Id: uuid,
				}),
			},
		}),
	})
	if err != nil {
		if isAlreadyExistsError(err) {
			return nil
		}
		return fmt.Errorf("add user %s to inbound %s: %w", email, c.inboundTag, err)
	}
	return nil
}

// RemoveUser removes a user from Xray
func (c *Client) RemoveUser(ctx context.Context, email string) error {
	handlerClient := proxymancommand.NewHandlerServiceClient(c.conn)
	_, err := handlerClient.AlterInbound(ctx, &proxymancommand.AlterInboundRequest{
		Tag: c.inboundTag,
		Operation: serial.ToTypedMessage(&proxymancommand.RemoveUserOperation{
			Email: email,
		}),
	})
	if err != nil {
		if isNotFoundError(err) {
			return nil
		}
		return fmt.Errorf("remove user %s from inbound %s: %w", email, c.inboundTag, err)
	}
	return nil
}

// QueryUserTraffic queries traffic statistics for a specific user
func (c *Client) QueryUserTraffic(ctx context.Context, email string) (*UserTraffic, error) {
	statsClient := statscommand.NewStatsServiceClient(c.conn)
	uplink, err := c.queryTrafficCounter(ctx, statsClient, fmt.Sprintf("user>>>%s>>>traffic>>>uplink", email))
	if err != nil {
		return nil, err
	}
	downlink, err := c.queryTrafficCounter(ctx, statsClient, fmt.Sprintf("user>>>%s>>>traffic>>>downlink", email))
	if err != nil {
		return nil, err
	}

	return &UserTraffic{
		Email:    email,
		Uplink:   uplink,
		Downlink: downlink,
	}, nil
}

// QueryAllUsersTraffic queries traffic statistics for all users
func (c *Client) QueryAllUsersTraffic(ctx context.Context) ([]*UserTraffic, error) {
	statsClient := statscommand.NewStatsServiceClient(c.conn)
	response, err := statsClient.QueryStats(ctx, &statscommand.QueryStatsRequest{
		Pattern: "user>>>.*>>>traffic>>>.*",
		Reset_:  false,
	})
	if err != nil {
		return nil, fmt.Errorf("query all user traffic: %w", err)
	}

	trafficByEmail := make(map[string]*UserTraffic)
	for _, stat := range response.GetStat() {
		parts := strings.Split(stat.GetName(), ">>>")
		if len(parts) != 4 || parts[0] != "user" || parts[2] != "traffic" {
			continue
		}

		email := parts[1]
		entry := trafficByEmail[email]
		if entry == nil {
			entry = &UserTraffic{Email: email}
			trafficByEmail[email] = entry
		}

		switch parts[3] {
		case "uplink":
			entry.Uplink = stat.GetValue()
		case "downlink":
			entry.Downlink = stat.GetValue()
		}
	}

	result := make([]*UserTraffic, 0, len(trafficByEmail))
	for _, traffic := range trafficByEmail {
		result = append(result, traffic)
	}

	return result, nil
}

func (c *Client) queryTrafficCounter(ctx context.Context, statsClient statscommand.StatsServiceClient, name string) (int64, error) {
	response, err := statsClient.GetStats(ctx, &statscommand.GetStatsRequest{
		Name:   name,
		Reset_: false,
	})
	if err != nil {
		if isNotFoundError(err) {
			return 0, nil
		}
		return 0, fmt.Errorf("query stat %s: %w", name, err)
	}
	if response.GetStat() == nil {
		return 0, nil
	}
	return response.GetStat().GetValue(), nil
}

func isAlreadyExistsError(err error) bool {
	st, ok := status.FromError(err)
	if ok && st.Code() == codes.AlreadyExists {
		return true
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "already exists") || strings.Contains(message, "already exist")
}

func isNotFoundError(err error) bool {
	st, ok := status.FromError(err)
	if ok && st.Code() == codes.NotFound {
		return true
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "not found") || strings.Contains(message, "user not found")
}

func generateUUIDFromAddress(address string) string {
	hash := sha256.Sum256([]byte(address))
	hashHex := hex.EncodeToString(hash[:])
	return fmt.Sprintf("%s-%s-%s-%s-%s",
		hashHex[0:8],
		hashHex[8:12],
		hashHex[12:16],
		hashHex[16:20],
		hashHex[20:32],
	)
}

func GetUserUUID(identityAddress string) string {
	return generateUUIDFromAddress(identityAddress)
}
