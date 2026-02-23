CREATE TABLE IF NOT EXISTS audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  wallet_address TEXT,
  client_ip TEXT,
  http_method TEXT,
  path TEXT,
  status_code INTEGER,
  error_code TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at
  ON audit_logs(created_at);

CREATE INDEX IF NOT EXISTS idx_audit_logs_event_type_created_at
  ON audit_logs(event_type, created_at);

CREATE INDEX IF NOT EXISTS idx_audit_logs_wallet_created_at
  ON audit_logs(wallet_address, created_at);
