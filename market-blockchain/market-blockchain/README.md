# Market Blockchain Service

Phase 2 subscription management service for VPN credit marketplace with blockchain integration.

## Overview

This service provides a complete subscription management system with:
- RESTful API for subscription lifecycle management
- Blockchain integration with VPNCreditVaultV4 smart contract
- Automatic renewal processing via background scheduler
- Support for subscription upgrades and downgrades
- PostgreSQL persistence layer

## Features

### Core Functionality
- **Subscription Management**: Create, query, cancel subscriptions
- **Plan Management**: Multiple subscription tiers with configurable pricing
- **Authorization**: ERC20 Permit-based gasless approvals
- **Charging**: Automated charging with blockchain transaction tracking
- **Events**: Complete audit trail of all subscription activities

### Advanced Features
- **Automatic Renewal**: Background scheduler processes renewals hourly
- **Upgrade**: Immediate plan upgrade with prorated charging
- **Downgrade**: Scheduled downgrade at period end
- **Allowance Tracking**: Monitor remaining authorized amounts

## Architecture

```
┌─────────────────┐
│   HTTP API      │  REST endpoints
└────────┬────────┘
         │
┌────────▼────────┐
│   Handlers      │  Request/response mapping
└────────┬────────┘
         │
┌────────▼────────┐
│   Services      │  Business logic
└────┬───────┬────┘
     │       │
     │       └──────────────┐
     │                      │
┌────▼────────┐    ┌───────▼────────┐
│ Repository  │    │   Blockchain   │
│  (Postgres) │    │     Client     │
└─────────────┘    └────────────────┘
```

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for detailed setup instructions.

```bash
# Setup database
./scripts/setup-db.sh

# Configure environment
cp .env .env.local
# Edit .env.local with your settings

# Build and run
go build -o bin/server cmd/server/main.go
./bin/server
```

## API Documentation

See [API.md](API.md) for complete API reference.

### Key Endpoints

- `GET /health` - Health check
- `GET /api/v1/plans` - List subscription plans
- `POST /api/v1/subscriptions` - Create subscription
- `GET /api/v1/subscriptions/{id}` - Get subscription details
- `DELETE /api/v1/subscriptions/{id}` - Cancel subscription
- `POST /api/v1/subscriptions/{id}/upgrade` - Upgrade plan
- `POST /api/v1/subscriptions/{id}/downgrade` - Downgrade plan

## Technology Stack

- **Language**: Go 1.24
- **Database**: PostgreSQL 12+
- **Blockchain**: Ethereum (Base Sepolia/Mainnet)
- **Smart Contract**: VPNCreditVaultV4
- **Libraries**: 
  - go-ethereum v1.17.2 (blockchain interaction)
  - lib/pq (PostgreSQL driver)
  - Standard library HTTP server

## Project Structure

```
market-blockchain/
├── cmd/server/              # Application entry point
├── internal/
│   ├── api/                # HTTP layer
│   │   ├── handlers/       # Request handlers
│   │   └── middleware/     # HTTP middleware
│   ├── app/                # Application bootstrap
│   ├── blockchain/         # Smart contract bindings
│   ├── config/             # Configuration
│   ├── domain/             # Business entities
│   ├── repository/         # Data access interfaces
│   ├── scheduler/          # Background jobs
│   ├── service/            # Business logic
│   └── store/              # Database implementation
│       ├── migrations/     # SQL migrations
│       └── postgres/       # PostgreSQL repositories
├── scripts/                # Utility scripts
├── API.md                  # API documentation
├── QUICKSTART.md           # Setup guide
└── README.md               # This file
```

## Development

### Prerequisites
- Go 1.24+
- PostgreSQL 12+
- Git

### Running Tests
```bash
go test ./...
```

### Running Smoke Tests
```bash
./scripts/smoke-test.sh
```

### Database Migrations

Migrations are in `internal/store/migrations/`:
- `0001_phase2_initial_schema.sql` - Core tables
- `0002_add_subscription_fields.sql` - Upgrade/downgrade support

Apply migrations:
```bash
./scripts/setup-db.sh
```

### Environment Variables

Required:
- `DATABASE_URL` - PostgreSQL connection string
- `SERVER_PORT` - HTTP server port (default: 8080)

Optional (for blockchain features):
- `BLOCKCHAIN_RPC_URL` - Ethereum RPC endpoint
- `CONTRACT_ADDRESS` - VPNCreditVaultV4 contract address
- `PRIVATE_KEY` - Service wallet private key
- `RENEWAL_CHECK_INTERVAL` - Renewal check frequency (default: 1h)

## Deployment

### Testnet (Base Sepolia)
Use configuration from `docs/V2_design/validation/phase4/contracts/testnet.env`

### Mainnet (Base)
Use configuration from `docs/V2_design/validation/phase4/contracts/mainnet.env`

**Important**: Never commit private keys or sensitive credentials to version control.

## Background Services

### Renewal Scheduler
- Runs at configured interval (default: 1 hour)
- Processes subscriptions with `auto_renew=true` and expired periods
- Applies pending downgrades during renewal
- Creates charge records and updates subscription state
- Marks subscriptions as expired if insufficient allowance

## Security Considerations

- Private keys are loaded from environment variables only
- Database connections use parameterized queries (SQL injection protection)
- Input validation on all API endpoints
- Transaction signing happens server-side with service wallet
- Permit signatures enable gasless user approvals

## Monitoring

Key metrics to monitor:
- Renewal processing success rate
- Failed charge attempts
- Database connection pool health
- Blockchain RPC latency
- Subscription state distribution

## Troubleshooting

See [QUICKSTART.md](QUICKSTART.md#troubleshooting) for common issues and solutions.

## Contributing

1. Create feature branch from `main`
2. Make changes with tests
3. Run smoke tests: `./scripts/smoke-test.sh`
4. Submit pull request

## License

[Add license information]

## Support

For issues or questions:
- Check documentation in `docs/`
- Review code comments
- Check git history for context
