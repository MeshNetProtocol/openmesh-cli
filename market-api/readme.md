cd market-api
node d1/generate_seed_official_online.mjs > d1/002_seed_official_online.sql




cd market-api

# 1) 先建表
npx wrangler d1 execute openmesh-market --remote --file=./d1/001_schema.sql

# 2) 再导入官方在线 provider 
npx wrangler d1 execute openmesh-market --remote --file=./d1/002_seed_official_online.sql

# 3) 鉴权基础表（里程碑 A）
npx wrangler d1 execute openmesh-market --remote --file=./d1/004_auth_schema.sql

# 4) 供应商管理表（里程碑 B）
npx wrangler d1 execute openmesh-market --remote --file=./d1/005_suppliers_schema.sql

# 5) 安全审计表（里程碑 D）
npx wrangler d1 execute openmesh-market --remote --file=./d1/006_security_audit.sql

npx wrangler d1 execute openmesh-market --remote --command="SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name;"

npx wrangler d1 execute openmesh-market --local --command="PRAGMA table_info(providers);"

npx wrangler d1 execute openmesh-market --local --command="SELECT id,name,updated_at,visibility,status,price_per_gb_usd FROM providers ORDER BY updated_at DESC LIMIT 20;"

npx wrangler d1 execute openmesh-market --local --command="SELECT id, length(config_json) AS config_len, length(routing_rules_json) AS rules_len FROM providers;"



npm run dev -- --port 8787 --local

# 认证相关环境变量（可写入 .dev.vars）
# AUTH_JWT_SECRET=replace-with-a-strong-random-secret
# AUTH_NONCE_TTL_SECONDS=300
# AUTH_TOKEN_TTL_SECONDS=900
# AUTH_ALLOWED_CHAIN_IDS=1,11155111
# AUTH_DOMAIN=localhost:8787
# AUTH_URI=http://127.0.0.1:8787
# CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:5500,https://meshnetprotocol.github.io
# AUTH_NONCE_RATE_LIMIT_PER_MIN=60
# AUTH_VERIFY_RATE_LIMIT_PER_MIN=30
# SUPPLIER_WRITE_RATE_LIMIT_PER_MIN=120
# SECURITY_AUDIT_ENABLED=true


npx wrangler tail openmesh-api
