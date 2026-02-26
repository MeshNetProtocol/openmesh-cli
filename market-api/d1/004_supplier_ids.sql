CREATE TABLE IF NOT EXISTS supplier_ids (
  supplier_id TEXT PRIMARY KEY,
  supplier_type TEXT NOT NULL CHECK (supplier_type IN ('commercial', 'private')),
  owner_wallet TEXT NOT NULL,
  chain_id INTEGER,
  status TEXT NOT NULL CHECK (status IN ('reserved', 'active', 'expired')),
  profile_url TEXT,
  last_verified_tx TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_supplier_ids_owner_wallet
  ON supplier_ids(owner_wallet);

CREATE INDEX IF NOT EXISTS idx_supplier_ids_type_status
  ON supplier_ids(supplier_type, status, updated_at);
