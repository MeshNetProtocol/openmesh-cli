# Market Blockchain API Documentation

## Base URL
```
http://localhost:8080
```

## Endpoints

### Health Check
```
GET /health
```
Check database connectivity and service health.

**Response:**
```json
{
  "status": "healthy"
}
```

---

### Plans

#### List Active Plans
```
GET /api/v1/plans
```
Get all active subscription plans.

**Response:**
```json
{
  "plans": [
    {
      "plan_id": "plan_basic_monthly",
      "name": "Basic Monthly",
      "description": "Basic plan with monthly billing",
      "period_seconds": 2592000,
      "amount_usdc_base_units": 1000000,
      "amount_usdc_display": "1.00 USDC",
      "authorization_periods": 3,
      "total_authorization_amount": 3000000,
      "active": true,
      "created_at": 1234567890000,
      "updated_at": 1234567890000
    }
  ]
}
```

---

### Subscriptions

#### Create Subscription
```
POST /api/v1/subscriptions
```
Create a new subscription with authorization and initial charge.

**Request Body:**
```json
{
  "identity_address": "0x1234...",
  "payer_address": "0x5678...",
  "plan_id": "plan_basic_monthly",
  "permit_signature": {
    "v": 27,
    "r": "0x1234...",
    "s": "0x5678..."
  }
}
```

**Response:**
```json
{
  "subscription": {
    "id": "sub_1234567890",
    "identity_address": "0x1234...",
    "payer_address": "0x5678...",
    "plan_id": "plan_basic_monthly",
    "status": "pending",
    "auto_renew": true,
    "current_period_start": 0,
    "current_period_end": 0,
    "created_at": 1234567890000,
    "updated_at": 1234567890000
  },
  "authorization": {
    "id": "auth_1234567890",
    "identity_address": "0x1234...",
    "payer_address": "0x5678...",
    "plan_id": "plan_basic_monthly",
    "permit_status": "pending",
    "created_at": 1234567890000
  },
  "charge": {
    "id": "chg_1234567890",
    "charge_id": "chg_1234567890",
    "amount": 1000000,
    "status": "pending",
    "created_at": 1234567890000
  }
}
```

#### Get Subscription
```
GET /api/v1/subscriptions/{id}
```
Get subscription details by ID.

**Response:**
```json
{
  "subscription": {
    "id": "sub_1234567890",
    "identity_address": "0x1234...",
    "payer_address": "0x5678...",
    "plan_id": "plan_basic_monthly",
    "status": "active",
    "auto_renew": true,
    "current_period_start": 1234567890000,
    "current_period_end": 1237159890000,
    "created_at": 1234567890000,
    "updated_at": 1234567890000
  }
}
```

#### Cancel Subscription
```
DELETE /api/v1/subscriptions/{id}
```
Cancel an active subscription.

**Response:**
```json
{
  "message": "subscription cancelled successfully"
}
```

#### Upgrade Subscription
```
POST /api/v1/subscriptions/{id}/upgrade
```
Immediately upgrade subscription to a higher-priced plan with prorated charge.

**Request Body:**
```json
{
  "new_plan_id": "plan_premium_monthly"
}
```

**Response:**
```json
{
  "message": "subscription upgraded successfully"
}
```

**Notes:**
- Calculates prorated charge based on remaining time in current period
- Unused credit from old plan is applied to new plan cost
- Subscription switches to new plan immediately
- Creates a pending charge record for the prorated amount

#### Downgrade Subscription
```
POST /api/v1/subscriptions/{id}/downgrade
```
Schedule subscription downgrade to a lower-priced plan at period end.

**Request Body:**
```json
{
  "new_plan_id": "plan_basic_monthly"
}
```

**Response:**
```json
{
  "message": "subscription downgrade scheduled for period end"
}
```

**Notes:**
- Downgrade is scheduled, not immediate
- Sets `pending_plan_id` field on subscription
- Actual plan change happens during next renewal
- User continues with current plan until period ends

---

## Status Codes

- `200 OK` - Request succeeded
- `400 Bad Request` - Invalid request body or parameters
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error

---

## Background Services

### Automatic Renewal Scheduler
- Runs every hour (configurable via `RENEWAL_CHECK_INTERVAL`)
- Processes subscriptions with `auto_renew=true` and `current_period_end <= now`
- Applies pending downgrades during renewal
- Creates charge records and updates subscription periods
- Marks subscriptions as expired if insufficient allowance

---

## Environment Configuration

Required environment variables:
```bash
SERVER_PORT=8080
DATABASE_URL=postgres://user:password@localhost:5432/market_blockchain?sslmode=disable
BLOCKCHAIN_RPC_URL=https://sepolia.base.org
CONTRACT_ADDRESS=0x...
PRIVATE_KEY=...
RENEWAL_CHECK_INTERVAL=1h
```
