CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  owner_wallet TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_suppliers_owner_wallet
  ON suppliers(owner_wallet);

CREATE INDEX IF NOT EXISTS idx_suppliers_status_updated
  ON suppliers(status, updated_at);

CREATE TABLE IF NOT EXISTS supplier_managers (
  supplier_id TEXT NOT NULL,
  manager_wallet TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'manager',
  created_at TEXT NOT NULL,
  PRIMARY KEY (supplier_id, manager_wallet),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_supplier_managers_supplier_id
  ON supplier_managers(supplier_id);

CREATE TABLE IF NOT EXISTS supplier_configs (
  supplier_id TEXT PRIMARY KEY,
  config_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  updated_by_wallet TEXT NOT NULL,
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
);
