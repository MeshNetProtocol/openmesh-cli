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

const OFFICIAL_PROVIDER_ID = "com.meshnetprotocol.profile";

const smartConfig = {
  log: {
    level: "debug"
  },
  dns: {
    servers: [
      {
        tag: "local-dns",
        address: "223.5.5.5",
        detour: "direct"
      },
      {
        tag: "google-dns",
        address: "https://dns.google/dns-query",
        detour: "proxy"
      }
    ],
    rules: [
      {
        rule_set: "geosite-geolocation-cn",
        server: "local-dns"
      }
    ],
    final: "google-dns",
    strategy: "prefer_ipv4"
  },
  inbounds: [
    {
      type: "tun",
      tag: "tun-in",
      address: [
        "172.18.0.1/30",
        "fd00::1/126"
      ],
      auto_route: true,
      strict_route: false,
      route_exclude_address: [
        "127.0.0.0/8",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "223.5.5.5/32",
        "::1/128",
        "fc00::/7",
        "fe80::/10"
      ],
      route_exclude_address_set: [
        "geoip-cn"
      ],
      sniff: true,
      sniff_override_destination: true
    }
  ],
  outbounds: [
    {
      type: "shadowsocks",
      tag: "meshflux168",
      server: "45.32.115.168",
      server_port: 10086,
      method: "aes-256-gcm",
      password: "yourpassword123"
    },
    {
      type: "shadowsocks",
      tag: "meshflux150",
      server: "216.128.182.150",
      server_port: 21799,
      method: "aes-256-gcm",
      password: "bUK4OB81aODMBw9I"
    },
    {
      type: "shadowsocks",
      tag: "meshflux224",
      server: "64.176.39.224",
      server_port: 29809,
      method: "aes-256-gcm",
      password: "mMxNObzBIYKEw1qV"
    },
    {
      type: "selector",
      tag: "proxy",
      outbounds: [
        "meshflux168",
        "meshflux150",
        "meshflux224"
      ],
      default: "meshflux168"
    },
    {
      type: "direct",
      tag: "direct"
    }
  ],
  route: {
    rules: [
      {
        protocol: "dns",
        action: "hijack-dns"
      },
      {
        action: "sniff"
      },
      {
        domain_suffix: [
          "google.com",
          "googleapis.com",
          "gstatic.com",
          "googleusercontent.com",
          "gvt1.com",
          "gvt2.com",
          "1e100.net",
          "youtube.com",
          "ytimg.com",
          "ggpht.com",
          "android.com",
          "app-measurement.com",
          "github.com",
          "githubusercontent.com",
          "twitter.com",
          "telegram.org",
          "claude.ai",
          "openai.com",
          "facebook.com",
          "fbcdn.net",
          "instagram.com",
          "whatsapp.com",
          "whatsapp.net",
          "tiktok.com",
          "byteoversea.com",
          "netflix.com",
          "bing.com",
          "perplexity.ai",
          "deepl.com"
        ],
        outbound: "proxy"
      },
      {
        rule_set: "geosite-geolocation-cn",
        outbound: "direct"
      },
      {
        rule_set: "geoip-cn",
        outbound: "direct"
      },
      {
        domain_suffix: ["localhost", "local"],
        outbound: "direct"
      },
      {
        ip_is_private: true,
        outbound: "direct"
      }
    ],
    final: "proxy",
    auto_detect_interface: true,
    rule_set: [
      {
        type: "remote",
        tag: "geoip-cn",
        format: "binary",
        url: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        download_detour: "proxy",
        update_interval: "1d"
      },
      {
        type: "remote",
        tag: "geosite-geolocation-cn",
        format: "binary",
        url: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs",
        download_detour: "proxy",
        update_interval: "1d"
      }
    ]
  }
};

const emptyRules = {
  version: 2,
  proxy: {
    domain: [],
    domain_suffix: []
  }
};

const generatedAt = new Date().toISOString();
const configJSON = JSON.stringify(smartConfig, null, 2);
const rulesJSON = JSON.stringify(emptyRules, null, 2);

const sql = `-- Seed official provider with Smart IP-Based Routing
-- No legacy routing_rules domain lists
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
  '官方极速节点 (SmartRouting)',
  '基于IP智能属性自动分流，无需维护列表。全面支持微信加速与海外服务稳定访问。',
  '["Official","SmartRouting","V2"]',
  'OpenMesh Team',
  '${generatedAt}',
  0.0,
  'public',
  'active',
  ${sqlStringConcat(configJSON)},
  ${sqlStringConcat(rulesJSON)}
);
`;

process.stdout.write(sql);
