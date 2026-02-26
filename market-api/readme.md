cd market-api

# 1) 建立 providers 表
npx wrangler d1 execute openmesh-market --remote --file=./d1/001_schema.sql

# 2) 导入官方在线 provider 数据
npx wrangler d1 execute openmesh-market --remote --file=./d1/002_seed_official_online.sql

# 3) 创建 supplier_id 全局唯一登记表
npx wrangler d1 execute openmesh-market --remote --file=./d1/004_supplier_ids.sql

# 4) 检查表结构和数据
npx wrangler d1 execute openmesh-market --remote --command="SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name;"
npx wrangler d1 execute openmesh-market --remote --command="SELECT id,name,updated_at,visibility,status,price_per_gb_usd FROM providers ORDER BY updated_at DESC LIMIT 20;"
npx wrangler d1 execute openmesh-market --remote --command="SELECT supplier_id,supplier_type,owner_wallet,status,chain_id,last_verified_tx FROM supplier_ids ORDER BY updated_at DESC LIMIT 20;"

# 5) 本地启动
npm run dev -- --port 8787 --local

# 仅保留 providers 只读查询相关配置
# CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:5500,https://meshnetprotocol.github.io
# MARKET_VERSION=1
# MARKET_UPDATED_AT=2026-02-23T00:00:00.000Z
# DEFAULT_CHAIN_ENV=sepolia
# SUPPLIER_REGISTRY_ADDRESS_MAINNET=
# SUPPLIER_REGISTRY_ADDRESS_SEPOLIA=
# PAYMENT_HUB_ADDRESS_MAINNET=
# PAYMENT_HUB_ADDRESS_SEPOLIA=
# USDC_ADDRESS_MAINNET=
# USDC_ADDRESS_SEPOLIA=

# 查看线上日志
npx wrangler tail openmesh-api
