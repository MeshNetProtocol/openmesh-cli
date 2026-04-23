# Phase 3: Xray Integration - Complete Implementation

## Overview

Phase 3 extends the subscription management system with Xray VPN integration, enabling:
- User access control based on subscription status
- Real-time traffic statistics collection
- Admin dashboard traffic monitoring

## Implementation Summary

### 1. Database Schema Extension

**Migration**: `0003_add_traffic_fields.sql`

Added traffic tracking fields to subscriptions table:
- `uplink` (BIGINT): Total bytes uploaded
- `downlink` (BIGINT): Total bytes downloaded  
- `total_traffic` (BIGINT): Combined traffic (uplink + downlink)
- Index on `total_traffic` for efficient queries

### 2. Domain Model Updates

**File**: [internal/domain/subscription.go](../../../market-blockchain/internal/domain/subscription.go)

Extended `Subscription` struct with traffic fields:
```go
type Subscription struct {
    // ... existing fields
    Uplink       int64
    Downlink     int64
    TotalTraffic int64
    // ...
}
```

### 3. Repository Layer Updates

**File**: [internal/store/postgres/subscription_repository.go](../../../market-blockchain/internal/store/postgres/subscription_repository.go)

Updated all repository methods to handle traffic fields:
- `Create()` - Insert with traffic fields
- `Update()` - Update traffic statistics
- `GetByID()` - Retrieve with traffic data
- `GetByIdentityAndPlan()` - Include traffic in queries
- `ListAll()`, `ListByStatus()`, `ListRenewable()` - All list methods include traffic
- `SearchByAddress()` - Search results include traffic

### 4. Xray Client Implementation

**File**: [internal/xray/client.go](../../../market-blockchain/internal/xray/client.go)

Implemented Xray gRPC client wrapper using CLI commands:
- `AddUser()` - Add user to Xray with UUID
- `RemoveUser()` - Remove user from Xray
- `QueryUserTraffic()` - Get traffic stats for specific user
- `QueryAllUsersTraffic()` - Batch query all users' traffic
- UUID generation using SHA256 hash of Ethereum address

**Technical Decision**: Used `xray api` CLI commands instead of direct gRPC to simplify implementation and avoid protobuf complexity.

### 5. Xray Sync Service

**File**: [internal/service/xray_sync_service.go](../../../market-blockchain/internal/service/xray_sync_service.go)

Synchronizes subscription status to Xray access control:
- `SyncSubscriptionToXray()` - Sync single subscription
  - Active → Add user to Xray
  - Cancelled/Expired → Remove user from Xray
- `SyncAllActiveSubscriptions()` - Batch sync all active subscriptions

### 6. Traffic Statistics Service

**File**: [internal/service/traffic_stats_service.go](../../../market-blockchain/internal/service/traffic_stats_service.go)

Background service for periodic traffic collection:
- Runs on configurable interval (default: 10s)
- Queries all users' traffic from Xray
- Updates subscription records in database
- Logs traffic in human-readable format (KB/MB/GB)

**Key Implementation**:
```go
func (s *TrafficStatsService) UpdateAllTrafficStats(ctx context.Context) error {
    trafficList, err := s.xrayClient.QueryAllUsersTraffic(ctx)
    // ... query traffic
    
    for _, traffic := range trafficList {
        subscription.Uplink = traffic.Uplink
        subscription.Downlink = traffic.Downlink
        subscription.TotalTraffic = traffic.Uplink + traffic.Downlink
        s.subscriptionRepo.Update(subscription)
    }
}
```

### 7. Configuration Extension

**File**: [internal/config/config.go](../../../market-blockchain/internal/config/config.go)

Added Xray-related configuration:
```go
type Config struct {
    XrayAPIAddress       string // Default: "127.0.0.1:10085"
    XrayInboundTag       string // Default: "vless-in"
    XrayEnabled          bool   // Default: false
    TrafficStatsInterval string // Default: "10s"
}
```

Environment variables:
- `XRAY_ENABLED` - Enable/disable Xray integration
- `XRAY_API_ADDRESS` - Xray gRPC API address
- `XRAY_INBOUND_TAG` - Inbound tag for user management
- `TRAFFIC_STATS_INTERVAL` - Traffic collection interval

### 8. Application Integration

**File**: [internal/app/app.go](../../../market-blockchain/internal/app/app.go)

Integrated Xray services into application lifecycle:

**Initialization**:
```go
if cfg.XrayEnabled {
    xrayClient, err = xray.NewClient(xray.Config{
        Address: cfg.XrayAPIAddress,
        Timeout: 5 * time.Second,
    })
    trafficStatsService = service.NewTrafficStatsService(
        xrayClient, 
        subscriptionRepo, 
        trafficStatsInterval,
    )
}
```

**Startup**:
```go
func (a *App) Run() error {
    // Start traffic stats service if enabled
    if a.trafficStatsService != nil {
        go a.trafficStatsService.Start(ctx)
    }
}
```

**Shutdown**:
```go
func (a *App) Shutdown() error {
    if a.xrayClient != nil {
        a.xrayClient.Close()
    }
}
```

### 9. Admin Interface Enhancement

**File**: [web/admin/index.html](../../../market-blockchain/web/admin/index.html)

Enhanced subscription list to display traffic data:

**UI Changes**:
- Added "Uplink" and "Downlink" columns to subscription table
- Implemented `formatBytes()` helper for human-readable display
- Traffic values displayed in amber color for visibility

**Display Format**:
- 0 B → 1023 B: Bytes
- 1 KB → 1023 KB: Kilobytes
- 1 MB → 1023 MB: Megabytes
- 1 GB+: Gigabytes

## Configuration Example

```bash
# Enable Xray integration
export XRAY_ENABLED=true
export XRAY_API_ADDRESS=127.0.0.1:10085
export XRAY_INBOUND_TAG=vless-in
export TRAFFIC_STATS_INTERVAL=10s

# Start server
./market-blockchain
```

## Testing Plan

### Unit Tests
- [x] Xray client methods (requires running Xray instance)
- [ ] Traffic stats service logic
- [ ] Sync service state transitions

### Integration Tests
- [ ] End-to-end subscription → Xray user flow
- [ ] Traffic collection and database updates
- [ ] Admin interface traffic display

### Manual Testing
1. Start Xray server with gRPC API enabled
2. Enable Xray integration in config
3. Create active subscription
4. Verify user added to Xray
5. Generate traffic through VPN
6. Check traffic stats in admin dashboard
7. Cancel subscription
8. Verify user removed from Xray

## Database Migration

Run migration to add traffic fields:

```bash
psql $DATABASE_URL -f internal/store/migrations/0003_add_traffic_fields.sql
```

## Architecture Decisions

### 1. CLI Wrapper vs Direct gRPC
**Decision**: Use `xray api` CLI commands
**Rationale**: 
- Faster implementation
- Avoids protobuf complexity
- Xray CLI is stable and well-documented

### 2. Deterministic UUID Generation
**Decision**: SHA256 hash of Ethereum address
**Rationale**:
- Same address always gets same UUID
- No need to store UUID mapping
- Reproducible across restarts

### 3. Background Traffic Collection
**Decision**: Separate service with configurable interval
**Rationale**:
- Decouples traffic collection from subscription logic
- Allows tuning collection frequency
- Graceful shutdown support

### 4. Traffic Storage in Subscription Table
**Decision**: Add fields to existing subscriptions table
**Rationale**:
- Simple schema design
- No additional joins needed
- Traffic is subscription-scoped data

## Next Steps

### Phase 3.1: Enhanced Admin Features
- [ ] Add "Restrict User" button in admin interface
- [ ] Implement manual user restriction/unrestriction
- [ ] Add traffic usage alerts/warnings
- [ ] Real-time traffic data refresh

### Phase 3.2: Traffic Limits
- [ ] Add traffic quota to plan configuration
- [ ] Implement traffic limit enforcement
- [ ] Auto-suspend subscriptions exceeding quota
- [ ] Traffic reset on renewal

### Phase 3.3: Monitoring & Alerts
- [ ] Prometheus metrics for traffic stats
- [ ] Alert on sync failures
- [ ] Dashboard for Xray health status
- [ ] Traffic anomaly detection

## Files Modified/Created

### New Files
- `internal/xray/client.go` - Xray API client
- `internal/xray/client_test.go` - Client tests
- `internal/service/xray_sync_service.go` - Subscription sync
- `internal/service/traffic_stats_service.go` - Traffic collection
- `internal/store/migrations/0003_add_traffic_fields.sql` - Schema migration
- `docs/V2_design/implementation/phase3_xray_integration.md` - Implementation docs

### Modified Files
- `internal/domain/subscription.go` - Added traffic fields
- `internal/config/config.go` - Added Xray config
- `internal/app/app.go` - Integrated Xray services
- `internal/store/postgres/subscription_repository.go` - Updated all queries
- `web/admin/index.html` - Enhanced UI with traffic display

## Dependencies

- Xray-core with gRPC API enabled
- PostgreSQL with migration applied
- Go 1.21+ for compilation

## Completion Status

✅ **Core Implementation Complete**
- Database schema extended
- Domain model updated
- Repository layer updated
- Xray client implemented
- Sync service implemented
- Traffic stats service implemented
- Application integrated
- Admin interface enhanced
- Documentation complete

🔄 **Pending Work**
- Unit test coverage
- Integration testing
- Manual testing with live Xray instance
- Traffic limit enforcement
- Enhanced admin features

---

**Implementation Date**: 2026-04-23
**Status**: Core functionality complete, ready for testing
