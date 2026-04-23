# Quick Start Guide

## Prerequisites

- Go 1.24 or higher
- PostgreSQL 12 or higher
- Git

## Installation

### 1. Clone the repository

```bash
git clone <repository-url>
cd openmesh-cli/market-blockchain
```

### 2. Install dependencies

```bash
go mod download
```

### 3. Setup database

```bash
# Start PostgreSQL (if not already running)
# macOS with Homebrew:
brew services start postgresql

# Create database and run migrations
./scripts/setup-db.sh

# Or manually:
createdb market_blockchain
psql -d market_blockchain -f internal/store/migrations/0001_phase2_initial_schema.sql
psql -d market_blockchain -f internal/store/migrations/0002_add_subscription_fields.sql
```

### 4. Configure environment

```bash
# Copy example env file
cp .env .env.local

# Edit .env.local with your settings
nano .env.local
```

Required configuration:
```bash
SERVER_PORT=8080
DATABASE_URL=postgres://postgres@localhost:5432/market_blockchain?sslmode=disable
BLOCKCHAIN_RPC_URL=https://sepolia.base.org
CONTRACT_ADDRESS=0x...  # Your VPNCreditVaultV4 contract address
PRIVATE_KEY=...         # Service wallet private key (without 0x prefix)
RENEWAL_CHECK_INTERVAL=1h
```

### 5. Build and run

```bash
# Build
go build -o bin/server cmd/server/main.go

# Run
./bin/server
```

The server will start on `http://localhost:8080`

## Quick Test

### Check health
```bash
curl http://localhost:8080/health
```

### List plans
```bash
curl http://localhost:8080/api/v1/plans | jq
```

### Create subscription
```bash
curl -X POST http://localhost:8080/api/v1/subscriptions \
  -H "Content-Type: application/json" \
  -d '{
    "identity_address": "0x1234...",
    "payer_address": "0x5678...",
    "plan_id": "plan_basic_monthly",
    "permit_signature": {
      "v": 27,
      "r": "0x...",
      "s": "0x..."
    }
  }' | jq
```

## Development

### Run tests
```bash
go test ./...
```

### Run smoke tests
```bash
./scripts/smoke-test.sh
```

### Database migrations

Migrations are located in `internal/store/migrations/` and are applied in order:
- `0001_phase2_initial_schema.sql` - Initial tables
- `0002_add_subscription_fields.sql` - Upgrade/downgrade support

To add a new migration:
1. Create `000X_description.sql` in migrations folder
2. Run `./scripts/setup-db.sh` to apply

## Architecture

```
market-blockchain/
├── cmd/server/          # Application entry point
├── internal/
│   ├── api/            # HTTP handlers and routing
│   ├── app/            # Application initialization
│   ├── blockchain/     # Smart contract interaction
│   ├── config/         # Configuration management
│   ├── domain/         # Business entities
│   ├── repository/     # Data access interfaces
│   ├── service/        # Business logic
│   └── store/          # Database implementation
├── scripts/            # Utility scripts
└── docs/              # Documentation
```

## Key Features

### Subscription Management
- Create subscriptions with ERC20 Permit authorization
- Automatic renewal via background scheduler
- Cancel subscriptions
- Upgrade (immediate with prorated charge)
- Downgrade (scheduled for period end)

### Background Services
- **Renewal Scheduler**: Runs every hour (configurable)
  - Processes expired subscriptions
  - Applies pending downgrades
  - Creates charge records
  - Updates subscription periods

### Blockchain Integration
- VPNCreditVaultV4 contract binding
- ERC20 Permit support for gasless approvals
- Transaction tracking and status updates

## API Documentation

See [API.md](API.md) for complete API reference.

## Troubleshooting

### Database connection failed
```bash
# Check PostgreSQL is running
pg_isready

# Verify connection string
psql "postgres://postgres@localhost:5432/market_blockchain?sslmode=disable"
```

### Contract interaction failed
- Verify `BLOCKCHAIN_RPC_URL` is accessible
- Check `CONTRACT_ADDRESS` is correct
- Ensure `PRIVATE_KEY` has sufficient gas

### Compilation errors
```bash
# Clean and rebuild
go clean -cache
go mod tidy
go build -o bin/server cmd/server/main.go
```

## Next Steps

1. Review [API.md](API.md) for endpoint details
2. Check [README.md](README.md) for project overview
3. Explore the codebase starting from [cmd/server/main.go](cmd/server/main.go)

## Support

For issues or questions, please check:
- Project documentation in `docs/`
- Code comments in source files
- Git commit history for context
