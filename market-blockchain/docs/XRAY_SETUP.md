# Xray Integration Setup Guide

This guide explains how to set up and configure Xray integration for the Market Blockchain subscription system.

## Prerequisites

- Xray-core installed (v1.8.0 or later)
- PostgreSQL database running
- Go 1.21+ for building the service

## Xray Configuration

### 1. Enable gRPC API

Add the following to your Xray config.json:

```json
{
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "StatsService"
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "tag": "vless-in",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  }
}
```

### 2. Start Xray

```bash
xray run -c /path/to/config.json
```

Verify gRPC API is accessible:

```bash
xray api stats --server=127.0.0.1:10085
```

## Service Configuration

### Environment Variables

Create a `.env` file in the `market-blockchain` directory:

```bash
# Server Configuration
SERVER_PORT=8080
APP_ENV=development

# Database Configuration
DATABASE_URL=postgres://postgres@localhost:5432/market_blockchain?sslmode=disable

# Blockchain Configuration
BLOCKCHAIN_RPC_URL=https://sepolia.base.org
CONTRACT_ADDRESS=0x...
PRIVATE_KEY=

# Renewal Configuration
RENEWAL_CHECK_INTERVAL=1h

# Xray Integration
XRAY_ENABLED=true
XRAY_API_ADDRESS=127.0.0.1:10085
XRAY_INBOUND_TAG=vless-in
TRAFFIC_STATS_INTERVAL=10s
```

### Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `XRAY_ENABLED` | Enable/disable Xray integration | `false` |
| `XRAY_API_ADDRESS` | Xray gRPC API address | `127.0.0.1:10085` |
| `XRAY_INBOUND_TAG` | Inbound tag for user management | `vless-in` |
| `TRAFFIC_STATS_INTERVAL` | Traffic collection interval | `10s` |

## Database Migration

Run the traffic fields migration:

```bash
psql $DATABASE_URL -f internal/store/migrations/0003_add_traffic_fields.sql
```

Verify migration:

```bash
psql $DATABASE_URL -c "\d subscriptions"
```

You should see `uplink`, `downlink`, and `total_traffic` columns.

## Running the Service

### Development Mode

```bash
cd market-blockchain
go run cmd/server/main.go
```

### Production Mode

```bash
cd market-blockchain
go build -o market-blockchain cmd/server/main.go
./market-blockchain
```

## Testing

### Unit Tests

```bash
go test ./internal/xray/...
go test ./internal/service/...
```

### Integration Tests

Requires running Xray instance:

```bash
go test -tags=integration ./internal/xray/...
```

### Manual Testing

1. **Create a subscription** (via API or admin interface)
2. **Verify user added to Xray**:
   ```bash
   xray api stats --server=127.0.0.1:10085 | grep "user>>>test@example.com"
   ```
3. **Generate traffic** through VPN connection
4. **Check traffic stats**:
   ```bash
   xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>.*>>>traffic>>>(uplink|downlink)"
   ```
5. **Verify database update**:
   ```bash
   psql $DATABASE_URL -c "SELECT identity_address, uplink, downlink, total_traffic FROM subscriptions WHERE status='active';"
   ```
6. **Cancel subscription** and verify user removed from Xray

## Troubleshooting

### Xray gRPC Connection Failed

**Error**: `failed to connect to Xray API at 127.0.0.1:10085`

**Solutions**:
- Verify Xray is running: `ps aux | grep xray`
- Check gRPC API is enabled in config
- Verify port 10085 is listening: `lsof -i :10085`
- Check firewall rules

### User Not Added to Xray

**Error**: `Failed to add user to Xray`

**Solutions**:
- Check `XRAY_INBOUND_TAG` matches your config
- Verify inbound tag exists: `xray api stats --server=127.0.0.1:10085`
- Check Xray logs for errors
- Ensure user email format is valid

### Traffic Stats Not Updating

**Possible causes**:
- `XRAY_ENABLED=false` in config
- Traffic stats interval too long
- No actual traffic generated
- Database connection issues

**Debug steps**:
1. Check service logs for traffic update messages
2. Verify Xray stats are available:
   ```bash
   xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>.*>>>traffic>>>(uplink|downlink)"
   ```
3. Check database connection
4. Reduce `TRAFFIC_STATS_INTERVAL` to `5s` for testing

### Database Migration Failed

**Error**: `relation "subscriptions" does not exist`

**Solution**: Run Phase 2 migrations first:
```bash
psql $DATABASE_URL -f internal/store/migrations/0001_phase2_initial_schema.sql
psql $DATABASE_URL -f internal/store/migrations/0002_add_subscription_fields.sql
psql $DATABASE_URL -f internal/store/migrations/0003_add_traffic_fields.sql
```

## Multi-Server Setup

For managing multiple Xray servers (Phase 3.1+):

1. Configure multiple Xray instances with different ports
2. Update service to support server pool configuration
3. Implement load balancing logic
4. Add health checks for each server

Example configuration (future):
```bash
XRAY_SERVERS=127.0.0.1:10085,127.0.0.1:10086,127.0.0.1:10087
```

## Monitoring

### Key Metrics to Monitor

- Xray gRPC connection status
- Traffic stats collection success rate
- User sync success/failure rate
- Database write latency
- Active user count vs Xray user count

### Logs to Watch

```bash
# Service logs
tail -f /var/log/market-blockchain/app.log | grep -E "(Xray|traffic|sync)"

# Xray logs
tail -f /var/log/xray/access.log
tail -f /var/log/xray/error.log
```

## Security Considerations

1. **gRPC API Access**: Restrict to localhost or use TLS
2. **User Isolation**: Each user gets unique UUID
3. **Traffic Privacy**: Traffic stats stored securely in database
4. **API Authentication**: Protect admin endpoints

## Next Steps

- Implement traffic quota enforcement
- Add traffic usage alerts
- Set up Prometheus metrics
- Configure Grafana dashboards
- Implement multi-server load balancing

## References

- [Xray Documentation](https://xtls.github.io/)
- [Xray API Guide](https://xtls.github.io/config/api.html)
- [Phase 3 Implementation Doc](../docs/V2_design/implementation/phase3_traffic_integration_complete.md)
