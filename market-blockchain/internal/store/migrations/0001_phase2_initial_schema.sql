-- Phase 2 initial schema
-- Core entities frozen from phase4 validated business model

CREATE TABLE IF NOT EXISTS plans (
    plan_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    period_seconds BIGINT NOT NULL,
    amount_usdc_base_units BIGINT NOT NULL,
    amount_usdc_display TEXT NOT NULL DEFAULT '',
    authorization_periods INTEGER NOT NULL,
    total_authorization_amount BIGINT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY,
    identity_address TEXT NOT NULL,
    payer_address TEXT NOT NULL,
    plan_id TEXT NOT NULL REFERENCES plans(plan_id),
    status TEXT NOT NULL,
    auto_renew BOOLEAN NOT NULL DEFAULT TRUE,
    current_period_start BIGINT NOT NULL DEFAULT 0,
    current_period_end BIGINT NOT NULL DEFAULT 0,
    next_plan_id TEXT NOT NULL DEFAULT '',
    last_charge_id TEXT NOT NULL DEFAULT '',
    last_charge_at BIGINT NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'first_subscribe',
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_identity_address
    ON subscriptions(identity_address);

CREATE INDEX IF NOT EXISTS idx_subscriptions_payer_address
    ON subscriptions(payer_address);

CREATE INDEX IF NOT EXISTS idx_subscriptions_status
    ON subscriptions(status);

CREATE TABLE IF NOT EXISTS authorizations (
    id TEXT PRIMARY KEY,
    identity_address TEXT NOT NULL,
    payer_address TEXT NOT NULL,
    plan_id TEXT NOT NULL REFERENCES plans(plan_id),
    expected_allowance BIGINT NOT NULL DEFAULT 0,
    target_allowance BIGINT NOT NULL DEFAULT 0,
    authorized_allowance BIGINT NOT NULL DEFAULT 0,
    remaining_allowance BIGINT NOT NULL DEFAULT 0,
    permit_status TEXT NOT NULL,
    permit_tx_hash TEXT NOT NULL DEFAULT '',
    permit_deadline BIGINT NOT NULL DEFAULT 0,
    authorization_periods INTEGER NOT NULL DEFAULT 0,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_authorizations_identity_plan
    ON authorizations(identity_address, plan_id);

CREATE INDEX IF NOT EXISTS idx_authorizations_payer_identity
    ON authorizations(payer_address, identity_address);

CREATE TABLE IF NOT EXISTS charges (
    id TEXT PRIMARY KEY,
    charge_id TEXT NOT NULL UNIQUE,
    identity_address TEXT NOT NULL,
    payer_address TEXT NOT NULL,
    plan_id TEXT NOT NULL REFERENCES plans(plan_id),
    amount BIGINT NOT NULL,
    status TEXT NOT NULL,
    tx_hash TEXT NOT NULL DEFAULT '',
    reason TEXT NOT NULL DEFAULT '',
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_charges_identity_address
    ON charges(identity_address);

CREATE INDEX IF NOT EXISTS idx_charges_plan_id
    ON charges(plan_id);

CREATE INDEX IF NOT EXISTS idx_charges_status
    ON charges(status);

CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,
    identity_address TEXT NOT NULL,
    payer_address TEXT NOT NULL,
    plan_id TEXT NOT NULL REFERENCES plans(plan_id),
    charge_id TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    metadata TEXT NOT NULL DEFAULT '',
    created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_identity_address
    ON events(identity_address);

CREATE INDEX IF NOT EXISTS idx_events_plan_id
    ON events(plan_id);

CREATE INDEX IF NOT EXISTS idx_events_type
    ON events(type);
