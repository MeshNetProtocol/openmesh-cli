-- Add pending_plan_id and current_authorization_id to subscriptions table

ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS pending_plan_id TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS current_authorization_id TEXT NOT NULL DEFAULT '';

-- Add subscription_id and authorization_id to charges table for better tracking
ALTER TABLE charges
ADD COLUMN IF NOT EXISTS subscription_id TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS authorization_id TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_charges_subscription_id
    ON charges(subscription_id);

CREATE INDEX IF NOT EXISTS idx_charges_authorization_id
    ON charges(authorization_id);
