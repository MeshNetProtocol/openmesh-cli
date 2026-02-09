DROP TABLE IF EXISTS providers;

CREATE TABLE IF NOT EXISTS providers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  tags_json TEXT NOT NULL,
  author TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  price_per_gb_usd REAL,
  visibility TEXT NOT NULL DEFAULT 'public',
  status TEXT NOT NULL DEFAULT 'active',
  config_json TEXT NOT NULL,
  routing_rules_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_providers_status_visibility_updated
  ON providers(status, visibility, updated_at);

