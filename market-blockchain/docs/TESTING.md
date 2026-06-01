# Testing Guide

Comprehensive testing guide for the Market Blockchain subscription system.

## Test Categories

### 1. Unit Tests

Test individual components in isolation.

```bash
# Run all unit tests
go test ./...

# Run with coverage
go test -cover ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### 2. Integration Tests

Test component interactions with external systems (Xray, database).

```bash
# Run integration tests (requires Xray + PostgreSQL)
go test -tags=integration ./...

# Run specific integration test
go test -tags=integration ./internal/xray/...
```

### 3. API Tests

Test HTTP endpoints.

```bash
# Start server in test mode
APP_ENV=test go run cmd/server/main.go

# Run API tests (in another terminal)
go test ./internal/api/...
```

### 4. End-to-End Tests

Test complete user flows.

## Test Structure

```
market-blockchain/
├── internal/
│   ├── xray/
│   │   ├── client.go
│   │   ├── client_test.go          # Unit tests
│   │   └── integration_test.go     # Integration tests
│   ├── service/
│   │   ├── traffic_stats_service.go
│   │   └── traffic_stats_service_test.go
│   └── api/
│       └── handlers/
│           └── subscription_handler_test.go
└── tests/
    └── e2e/
        └── subscription_flow_test.go
```

## Phase 3 Test Checklist

### Xray Client Tests

- [x] Client initialization
- [x] Connection timeout handling
- [ ] AddUser success
- [ ] AddUser with invalid parameters
- [ ] RemoveUser success
- [ ] RemoveUser non-existent user
- [ ] QueryUserTraffic success
- [ ] QueryUserTraffic non-existent user
- [ ] QueryAllUsersTraffic success
- [ ] Connection failure handling

### Traffic Stats Service Tests

- [ ] Service initialization
- [ ] Periodic traffic collection
- [ ] Database update on traffic change
- [ ] Handle Xray connection failure
- [ ] Handle database write failure
- [ ] Graceful shutdown

### Xray Sync Service Tests

- [ ] Sync active subscription to Xray
- [ ] Sync cancelled subscription (remove user)
- [ ] Sync expired subscription (remove user)
- [ ] Handle Xray API failure
- [ ] Batch sync all active subscriptions
- [ ] UUID generation consistency

### Integration Tests

- [ ] Full subscription → Xray user flow
- [ ] Traffic collection → database update
- [ ] Subscription cancellation → user removal
- [ ] Multiple users traffic collection
- [ ] Service restart with existing users

## Manual Testing Scenarios

### Scenario 1: New Subscription

1. Create subscription via API
2. Verify user added to Xray:
   ```bash
   xray api stats --server=127.0.0.1:10085 | grep "user>>>"
   ```
3. Connect VPN client
4. Generate traffic
5. Wait for traffic stats interval
6. Check database:
   ```sql
   SELECT identity_address, uplink, downlink, total_traffic 
   FROM subscriptions 
   WHERE identity_address = 'test@example.com';
   ```

### Scenario 2: Subscription Cancellation

1. Cancel active subscription
2. Verify user removed from Xray
3. Attempt VPN connection (should fail)
4. Verify traffic stats no longer update

### Scenario 3: Service Restart

1. Stop service
2. Verify Xray users remain
3. Start service
4. Verify traffic collection resumes
5. Check no duplicate users created

### Scenario 4: Xray Failure Recovery

1. Stop Xray
2. Observe service logs (should show connection errors)
3. Start Xray
4. Verify service reconnects
5. Verify traffic collection resumes

### Scenario 5: High Traffic Load

1. Create 10+ active subscriptions
2. Generate traffic on all connections
3. Monitor traffic stats collection
4. Verify all users updated correctly
5. Check database performance

## Performance Testing

### Traffic Stats Collection Performance

```bash
# Measure collection time for N users
time xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>.*>>>traffic>>>(uplink|downlink)"
```

Target: < 100ms for 100 users

### Database Write Performance

```sql
-- Measure bulk update time
EXPLAIN ANALYZE 
UPDATE subscriptions 
SET uplink = 1000000, downlink = 2000000, total_traffic = 3000000 
WHERE status = 'active';
```

Target: < 50ms for 100 subscriptions

## Test Data Setup

### Create Test Subscriptions

```sql
-- Insert test subscription
INSERT INTO subscriptions (
    id, identity_address, payer_address, plan_id, status, auto_renew,
    current_period_start, current_period_end, uplink, downlink, total_traffic,
    created_at, updated_at
) VALUES (
    'test-sub-001',
    'test1@example.com',
    '0x1234567890123456789012345678901234567890',
    'basic-monthly',
    'active',
    true,
    extract(epoch from now()) * 1000,
    extract(epoch from now() + interval '30 days') * 1000,
    0, 0, 0,
    extract(epoch from now()) * 1000,
    extract(epoch from now()) * 1000
);
```

### Add Test User to Xray

```bash
xray api adi --server=127.0.0.1:10085 \
    --tag=vless-in \
    --email=test1@example.com \
    --uuid=550e8400-e29b-41d4-a716-446655440000
```

## Continuous Integration

### GitHub Actions Workflow

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: market_blockchain_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Run migrations
        run: |
          psql $DATABASE_URL -f internal/store/migrations/0001_phase2_initial_schema.sql
          psql $DATABASE_URL -f internal/store/migrations/0003_add_traffic_fields.sql
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/market_blockchain_test?sslmode=disable
      
      - name: Run unit tests
        run: go test -v -cover ./...
      
      - name: Run integration tests
        run: go test -v -tags=integration ./...
        if: false  # Skip until Xray setup in CI
```

## Test Coverage Goals

- Unit tests: > 80% coverage
- Integration tests: Critical paths covered
- API tests: All endpoints tested
- E2E tests: Main user flows covered

## Known Test Limitations

1. Integration tests require manual Xray setup
2. Traffic generation requires actual VPN connections
3. Multi-server tests not yet implemented
4. Performance tests need production-like load

## Next Steps

1. Implement missing unit tests
2. Set up CI/CD pipeline
3. Add performance benchmarks
4. Create load testing scripts
5. Implement chaos testing

## References

- [Go Testing Documentation](https://golang.org/pkg/testing/)
- [Testify Framework](https://github.com/stretchr/testify)
- [Phase 3 Implementation](../docs/V2_design/implementation/phase3_traffic_integration_complete.md)
