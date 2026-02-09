import fs from "node:fs";
import path from "node:path";

function sqlStringConcat(s, chunkSize = 800) {
  const escaped = s.replaceAll("'", "''");
  const chunks = [];
  for (let i = 0; i < escaped.length; i += chunkSize) {
    chunks.push(escaped.slice(i, i + chunkSize));
  }
  return chunks.map((c) => `'${c}'`).join(" ||\n  ");
}

const repoRoot = path.resolve(process.cwd(), "..");
const configPath = path.join(repoRoot, "openmesh-apple", "MeshFluxMac", "default_profile.json");
const rulesPath = path.join(repoRoot, "openmesh-apple", "shared", "routing_rules.json");

const config = fs.readFileSync(configPath, "utf8");
const rules = fs.readFileSync(rulesPath, "utf8");

const OFFICIAL_PROVIDER_ID = "com.meshnetprotocol.profile";
const RULE_SET_UPSTREAM_BY_TAG = {
  "geoip-cn": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
  "geosite-geolocation-cn": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs",
};

function patchRuleSetURLsToGitHub(configJSON) {
  let obj;
  try {
    obj = JSON.parse(configJSON);
  } catch {
    return configJSON;
  }
  const route = obj?.route;
  if (!route || !Array.isArray(route.rule_set)) return configJSON;
  for (const rs of route.rule_set) {
    if (!rs || rs.type !== "remote") continue;
    const upstream = RULE_SET_UPSTREAM_BY_TAG[rs.tag];
    if (!upstream) continue;
    rs.url = upstream;
    if (!rs.download_detour) rs.download_detour = "proxy";
  }
  return JSON.stringify(obj);
}

const generatedAt = new Date().toISOString();
const patchedConfig = patchRuleSetURLsToGitHub(config);

const sql = `-- Seed official provider from local default profile
-- Ensure geoip/geosite rule-set URLs use GitHub upstreams (for blocked-network test)
-- Generated at: ${generatedAt}

DELETE FROM providers WHERE id='${OFFICIAL_PROVIDER_ID}';

INSERT INTO providers (
  id,
  name,
  description,
  tags_json,
  author,
  updated_at,
  price_per_gb_usd,
  visibility,
  status,
  config_json,
  routing_rules_json
) VALUES (
  '${OFFICIAL_PROVIDER_ID}',
  '官方供应商在线版本',
  '用于对照测试：行为与 App 内置默认配置一致（force_proxy -> proxy；geoip/geosite -> direct；未命中流量由本地开关控制）',
  '["Official","Online"]',
  'OpenMesh Team',
  '2026-02-08T00:00:00Z',
  0.0,
  'public',
  'active',
  ${sqlStringConcat(patchedConfig)},
  ${sqlStringConcat(rules)}
);
`;

process.stdout.write(sql);
