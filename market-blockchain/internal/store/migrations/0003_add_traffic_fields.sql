-- Add traffic statistics fields to subscriptions table
ALTER TABLE subscriptions
ADD COLUMN uplink BIGINT NOT NULL DEFAULT 0,
ADD COLUMN downlink BIGINT NOT NULL DEFAULT 0,
ADD COLUMN total_traffic BIGINT NOT NULL DEFAULT 0;

-- Add index for querying subscriptions by traffic usage
CREATE INDEX idx_subscriptions_total_traffic ON subscriptions(total_traffic);

-- Add comment for documentation
COMMENT ON COLUMN subscriptions.uplink IS 'Total bytes uploaded by user';
COMMENT ON COLUMN subscriptions.downlink IS 'Total bytes downloaded by user';
COMMENT ON COLUMN subscriptions.total_traffic IS 'Total traffic (uplink + downlink) in bytes';
