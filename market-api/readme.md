cd market-api
node d1/generate_seed_official_online.mjs > d1/002_seed_official_online.sql




cd market-api

# 1) 先建表
npx wrangler d1 execute openmesh-market --remote --file=./d1/001_schema.sql

# 2) 再导入官方在线 provider 
npx wrangler d1 execute openmesh-market --remote --file=./d1/002_seed_official_online.sql

npx wrangler d1 execute openmesh-market --remote --command="SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name;"

npx wrangler d1 execute openmesh-market --local --command="PRAGMA table_info(providers);"

npx wrangler d1 execute openmesh-market --local --command="SELECT id,name,updated_at,visibility,status,price_per_gb_usd FROM providers ORDER BY updated_at DESC LIMIT 20;"

npx wrangler d1 execute openmesh-market --local --command="SELECT id, length(config_json) AS config_len, length(routing_rules_json) AS rules_len FROM providers;"



npm run dev -- --port 8787 --local


npx wrangler tail openmesh-api