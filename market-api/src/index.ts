/**
 * OpenMesh API - Traffic Market & AASA
 */

interface Env {
    IOS_TEAM_ID?: string;
    IOS_BUNDLE_ID?: string;
    UL_PATHS?: string;
    MARKET_VERSION?: string;
    MARKET_UPDATED_AT?: string;
}

interface TrafficProvider {
    id: string;
    name: string;
    description: string;
    config_url: string;
    tags: string[];
    icon_url?: string;
    author: string;
    updated_at: string;
    provider_hash?: string;
    package_hash?: string;
    price_per_gb_usd?: number;
    detail_url?: string;
}

type ProviderPackageFile =
    | { type: "config"; url: string }
    | { type: "force_proxy"; url: string }
    | { type: "rule_set"; tag: string; mode: "remote_url"; url: string };

const UPSTREAM_RULE_SETS: Record<string, string> = {
    "geoip-cn.srs": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
    "geosite-geolocation-cn.srs": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs",
};

// Mock Data
const MOCK_PROVIDERS: TrafficProvider[] = [
    {
        id: "official-online",
        name: "官方供应商在线版本",
        description: "用于对照测试：行为与 App 内置默认配置一致（force_proxy -> proxy；geoip/geosite -> direct；未命中流量由本地开关控制）",
        config_url: "https://market.openmesh.network/api/v1/config/official-online",
        tags: ["Official", "Online"],
        author: "OpenMesh Team",
        updated_at: "2026-02-08T00:00:00Z",
        provider_hash: "sha256:mock-official-online-provider",
        package_hash: "sha256:mock-official-online-package",
        price_per_gb_usd: 0.0,
    },
    {
        id: "us-access-cn",
        name: "US to China",
        description: "For users in US accessing Chinese apps and websites (Bilibili, NetEase Music, etc).",
        config_url: "https://market.openmesh.network/api/v1/config/us-access-cn",
        tags: ["Community", "US-to-CN"],
        author: "Community Contributor",
        updated_at: "2026-02-01T00:00:00Z",
        provider_hash: "sha256:mock-us-access-cn-provider",
        package_hash: "sha256:mock-us-access-cn-package",
        price_per_gb_usd: 0.05,
    }
];

// Mock Config Content (Simplified sing-box config structure)
// In reality, this would be fetched from R2 or KV
const MOCK_CONFIGS: Record<string, any> = {
    "official-online": {
        "dns": {
            "final": "google-dns",
            "reverse_mapping": true,
            "rules": [
                {
                    "action": "route",
                    "rule_set": "geosite-geolocation-cn",
                    "server": "local-dns",
                    "strategy": "ipv4_only"
                }
            ],
            "servers": [
                {
                    "detour": "proxy",
                    "server": "dns.google",
                    "tag": "google-dns",
                    "type": "https"
                },
                {
                    "detour": "direct",
                    "server": "223.5.5.5",
                    "tag": "local-dns",
                    "type": "udp"
                }
            ],
            "strategy": "ipv4_only"
        },
        "experimental": {
            "cache_file": {
                "enabled": true
            }
        },
        "inbounds": [
            {
                "address": [
                    "172.18.0.1/30",
                    "fdfe:dcba:9876::1/126"
                ],
                "auto_route": true,
                "route_exclude_address": [
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
                "route_exclude_address_set": [
                    "geoip-cn"
                ],
                "strict_route": false,
                "tag": "tun-in",
                "type": "tun",
                "stack": "system"
            }
        ],
        "log": {
            "level": "debug"
        },
        "outbounds": [
            {
                "type": "shadowsocks",
                "tag": "meshflux168",
                "server": "45.32.115.168",
                "server_port": 10086,
                "method": "aes-256-gcm",
                "password": "yourpassword123"
            },
            {
                "type": "shadowsocks",
                "tag": "meshflux150",
                "server": "216.128.182.150",
                "server_port": 10086,
                "method": "aes-256-gcm",
                "password": "yourpassword123"
            },
            {
                "type": "shadowsocks",
                "tag": "meshflux170",
                "server": "144.202.10.170",
                "server_port": 10087,
                "method": "aes-256-gcm",
                "password": "yourpassword123"
            },
            {
                "type": "shadowsocks",
                "tag": "meshflux252",
                "server": "45.76.45.252",
                "server_port": 10086,
                "method": "aes-256-gcm",
                "password": "yourpassword123"
            },
            {
                "type": "selector",
                "tag": "proxy",
                "outbounds": [
                    "meshflux168",
                    "meshflux150",
                    "meshflux170",
                    "meshflux252"
                ],
                "default": "meshflux150"
            },
            {
                "domain_strategy": "ipv4_only",
                "fallback_delay": "300ms",
                "tag": "direct",
                "type": "direct"
            }
        ],
        "route": {
            "auto_detect_interface": true,
            "default_domain_resolver": "google-dns",
            "final": "proxy",
            "rule_set": [
                {
                    "type": "remote",
                    "tag": "geoip-cn",
                    "format": "binary",
                    "url": "https://market.openmesh.network/assets/rule-set/geoip-cn.srs",
                    "download_detour": "direct",
                    "update_interval": "72h"
                },
                {
                    "type": "remote",
                    "tag": "geosite-geolocation-cn",
                    "format": "binary",
                    "url": "https://market.openmesh.network/assets/rule-set/geosite-geolocation-cn.srs",
                    "download_detour": "direct",
                    "update_interval": "72h"
                }
            ],
            "rules": [
                {
                    "action": "sniff"
                },
                {
                    "rule_set": "geosite-geolocation-cn",
                    "outbound": "direct"
                },
                {
                    "rule_set": "geoip-cn",
                    "outbound": "direct"
                },
                {
                    "action": "hijack-dns",
                    "protocol": "dns"
                }
            ]
        }
    },
    "us-access-cn": {
        "log": { "level": "info", "timestamp": true },
        "inbounds": [
            { "type": "tun", "tag": "tun-in", "interface_name": "utun", "inet4_address": "172.19.0.1/30", "auto_route": true, "strict_route": true, "stack": "system" }
        ],
        "outbounds": [
             { "type": "direct", "tag": "direct" },
             { "type": "selector", "tag": "proxy", "outbounds": ["cn-sh-01"], "default": "cn-sh-01" },
             { "type": "shadowsocks", "tag": "cn-sh-01", "server": "sh.example.com", "server_port": 8388, "method": "aes-256-gcm", "password": "password" }
        ],
        "route": {
            "rules": [
                 { "rule_set": "geosite-geolocation-cn", "outbound": "proxy" },
                 { "rule_set": "geoip-cn", "outbound": "proxy" }
            ],
            "rule_set": [
                { "tag": "geoip-cn", "type": "remote", "format": "binary", "url": "https://market.openmesh.network/assets/rule-set/geoip-cn.srs", "download_detour": "direct", "update_interval": "72h" },
                { "tag": "geosite-geolocation-cn", "type": "remote", "format": "binary", "url": "https://market.openmesh.network/assets/rule-set/geosite-geolocation-cn.srs", "download_detour": "direct", "update_interval": "72h" }
            ],
            "final": "direct"
        }
    }
};

const MOCK_FORCE_PROXY_RULES: Record<string, unknown> = {
    "official-online": {
        proxy: {
            domain_suffix: [
                ".openai.com",
                ".chatgpt.com",
                ".anthropic.com"
            ],
            domain: [
                "api.openai.com"
            ]
        }
    },
    "us-access-cn": {
        proxy: {
            domain_suffix: [
                ".bilibili.com",
                ".music.163.com"
            ]
        }
    }
};

function marketVersion(env: Env): number {
    const s = (env.MARKET_VERSION || "").trim();
    const n = Number.parseInt(s, 10);
    return Number.isFinite(n) ? n : 1;
}

function marketUpdatedAt(env: Env, providers: TrafficProvider[]): string {
    const envUpdatedAt = (env.MARKET_UPDATED_AT || "").trim();
    if (envUpdatedAt) return envUpdatedAt;
    const max = providers.map(p => p.updated_at).sort().slice(-1)[0];
    return max || "2026-02-08T00:00:00Z";
}

function makeETag(marketVersion: number, updatedAt: string): string {
    return `"market-v${marketVersion}-${updatedAt}"`;
}

function sameETag(request: Request, etag: string): boolean {
    const inm = request.headers.get("if-none-match");
    if (!inm) return false;
    return inm.split(",").map(s => s.trim()).includes(etag);
}

function baseURL(url: URL): string {
    const hostname = url.hostname === "localhost" ? "127.0.0.1" : url.hostname;
    const host = url.port ? `${hostname}:${url.port}` : hostname;
    return `${url.protocol}//${host}`;
}

function sanitizeURLString(s: string): string {
    let out = s.trim();
    if ((out.startsWith("`") && out.endsWith("`")) || (out.startsWith("“") && out.endsWith("”"))) {
        out = out.slice(1, -1).trim();
    }
    out = out.replaceAll("`", "").trim();
    return out;
}

function rewriteMarketHostInObject(value: unknown, base: string): unknown {
    if (typeof value === "string") {
        const sanitized = sanitizeURLString(value);
        return sanitized.replaceAll("https://market.openmesh.network", base);
    }
    if (Array.isArray(value)) {
        return value.map(v => rewriteMarketHostInObject(v, base));
    }
    if (value && typeof value === "object") {
        const obj = value as Record<string, unknown>;
        const out: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(obj)) {
            out[k] = rewriteMarketHostInObject(v, base);
        }
        return out;
    }
    return value;
}

function buildProvidersForRequest(url: URL): TrafficProvider[] {
    const base = baseURL(url);
    return MOCK_PROVIDERS.map(p => ({
        ...p,
        config_url: p.config_url.replace("https://market.openmesh.network", base),
        detail_url: `${base}/api/v1/providers/${encodeURIComponent(p.id)}`,
    }));
}

function buildProviderPackageFiles(url: URL, providerID: string): ProviderPackageFile[] {
    const base = baseURL(url);
    if (providerID === "official-online") {
        return [
            { type: "config", url: `${base}/api/v1/config/official-online` },
            { type: "force_proxy", url: `${base}/api/v1/rules/official-online/routing_rules.json` },
            { type: "rule_set", tag: "geoip-cn", mode: "remote_url", url: `${base}/assets/rule-set/geoip-cn.srs` },
            { type: "rule_set", tag: "geosite-geolocation-cn", mode: "remote_url", url: `${base}/assets/rule-set/geosite-geolocation-cn.srs` },
        ];
    }
    if (providerID === "us-access-cn") {
        return [
            { type: "config", url: `${base}/api/v1/config/us-access-cn` },
            { type: "force_proxy", url: `${base}/api/v1/rules/us-access-cn/routing_rules.json` },
            { type: "rule_set", tag: "geoip-cn", mode: "remote_url", url: `${base}/assets/rule-set/geoip-cn.srs` },
            { type: "rule_set", tag: "geosite-geolocation-cn", mode: "remote_url", url: `${base}/assets/rule-set/geosite-geolocation-cn.srs` },
        ];
    }
    return [
        { type: "config", url: `${base}/api/v1/config/${encodeURIComponent(providerID)}` },
        { type: "force_proxy", url: `${base}/api/v1/rules/${encodeURIComponent(providerID)}/routing_rules.json` },
    ];
}


function normalizePaths(paths: string[]): string[] {
    const out: string[] = [];
    for (const p of paths) {
        let s = p.trim();
        if (!s.startsWith("/")) s = "/" + s;
        out.push(s);
    }
    return Array.from(new Set(out));
}

function buildAASA(env: Env) {
    const teamId = (env.IOS_TEAM_ID || "TEAMID").trim();
    const bundleId = (env.IOS_BUNDLE_ID || "com.MeshNetProtocol.OpenMesh.OpenMesh").trim();
    const appID = `${teamId}.${bundleId}`;
    const rawPaths = (env.UL_PATHS || "/callback").split(",").map(s => s.trim()).filter(Boolean);
    const basePaths = normalizePaths(rawPaths);

    const paths: string[] = [];
    for (const bp of basePaths) {
        paths.push(bp);
        if (bp !== "/") {
            paths.push(`${bp}*`);
            paths.push(bp.endsWith("/") ? `${bp}*` : `${bp}/*`);
        } else {
            paths.push("/*");
        }
    }

    return {
        applinks: {
            apps: [],
            details: [{ appID, paths }],
        },
        webcredentials: { apps: [appID] },
    };
}

function json(resObj: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
    return new Response(JSON.stringify(resObj), {
        status,
        headers: {
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=300",
            "Access-Control-Allow-Origin": "*", // Allow CORS for all API responses
            ...extraHeaders,
        },
    });
}

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);
        const path = url.pathname;

        if (request.method === "OPTIONS") {
            return new Response(null, {
                status: 204,
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Max-Age": "86400",
                },
            });
        }

        // AASA
        if (request.method === "GET" && (path === "/.well-known/apple-app-site-association" || path === "/apple-app-site-association")) {
            return json(buildAASA(env));
        }

        // Market API: List Providers
        if (request.method === "GET" && path === "/api/v1/providers") {
            const providers = buildProvidersForRequest(url);
            return json({
                ok: true,
                data: providers
            });
        }

        if (request.method === "GET" && path === "/api/v1/market/manifest") {
            const providers = buildProvidersForRequest(url);
            const mv = marketVersion(env);
            const updated_at = marketUpdatedAt(env, providers);
            const etag = makeETag(mv, updated_at);
            if (sameETag(request, etag)) {
                return new Response(null, {
                    status: 304,
                    headers: {
                        "ETag": etag,
                        "Cache-Control": "public, max-age=60",
                        "Access-Control-Allow-Origin": "*",
                    },
                });
            }
            return json(
                {
                    ok: true,
                    market_version: mv,
                    updated_at,
                    providers,
                },
                200,
                {
                    "ETag": etag,
                    "Cache-Control": "public, max-age=60",
                }
            );
        }

        if (request.method === "GET" && path === "/api/v1/market/recommended") {
            const providers = buildProvidersForRequest(url).slice(0, 6);
            return json({ ok: true, data: providers });
        }

        if (request.method === "GET" && path === "/api/v1/market/providers") {
            const providers = buildProvidersForRequest(url);
            const page = Math.max(1, Number.parseInt(url.searchParams.get("page") || "1", 10) || 1);
            const pageSize = Math.min(60, Math.max(1, Number.parseInt(url.searchParams.get("page_size") || "24", 10) || 24));
            const sort = (url.searchParams.get("sort") || "time").toLowerCase();
            const order = (url.searchParams.get("order") || "desc").toLowerCase();
            const q = (url.searchParams.get("q") || "").trim().toLowerCase();

            let filtered = providers;
            if (q) {
                filtered = filtered.filter(p => p.name.toLowerCase().includes(q) || p.description.toLowerCase().includes(q));
            }
            if (sort === "price") {
                filtered = filtered.sort((a, b) => (a.price_per_gb_usd || 0) - (b.price_per_gb_usd || 0));
            } else {
                filtered = filtered.sort((a, b) => a.updated_at.localeCompare(b.updated_at));
            }
            if (order !== "asc") {
                filtered = filtered.reverse();
            }

            const total = filtered.length;
            const start = (page - 1) * pageSize;
            const data = filtered.slice(start, start + pageSize);
            return json({
                ok: true,
                page,
                page_size: pageSize,
                total,
                data,
            });
        }

        // Market API: Get Config
        // Route: /api/v1/config/:id
        const configMatch = path.match(/^\/api\/v1\/config\/([^\/]+)$/);
        if (request.method === "GET" && configMatch) {
            const id = configMatch[1];
            const config = MOCK_CONFIGS[id];
            if (config) {
                const base = baseURL(url);
                const rewritten = rewriteMarketHostInObject(config, base);
                return json(rewritten);
            } else {
                return json({ ok: false, error: "Config not found" }, 404);
            }
        }

        const assetsRuleSetMatch = path.match(/^\/assets\/rule-set\/([^\/]+)$/);
        if (request.method === "GET" && assetsRuleSetMatch) {
            const filename = assetsRuleSetMatch[1];
            const upstream = UPSTREAM_RULE_SETS[filename];
            if (!upstream) {
                return new Response("Not Found", { status: 404, headers: { "Access-Control-Allow-Origin": "*" } });
            }
            try {
                const res = await fetch(upstream);
                const headers = new Headers(res.headers);
                headers.set("Access-Control-Allow-Origin", "*");
                headers.set("Cache-Control", "public, max-age=86400");
                if (!headers.get("Content-Type")) {
                    headers.set("Content-Type", "application/octet-stream");
                }
                return new Response(res.body, { status: res.status, headers });
            } catch {
                const headers = new Headers();
                headers.set("Access-Control-Allow-Origin", "*");
                headers.set("Cache-Control", "public, max-age=86400");
                headers.set("Location", upstream);
                return new Response(null, { status: 302, headers });
            }
        }

        const rulesMatch = path.match(/^\/api\/v1\/rules\/([^\/]+)\/routing_rules\.json$/);
        if (request.method === "GET" && rulesMatch) {
            const id = rulesMatch[1];
            const rules = MOCK_FORCE_PROXY_RULES[id];
            if (rules) {
                return json(rules);
            }
            return json({ ok: false, error: "Rules not found" }, 404);
        }

        const providerDetailMatch = path.match(/^\/api\/v1\/providers\/([^\/]+)$/);
        if (request.method === "GET" && providerDetailMatch) {
            const id = providerDetailMatch[1];
            const providers = buildProvidersForRequest(url);
            const provider = providers.find(p => p.id === id);
            if (!provider) {
                return json({ ok: false, error: "Provider not found" }, 404);
            }
            return json({
                ok: true,
                provider,
                package: {
                    package_hash: provider.package_hash || "sha256:mock-package",
                    files: buildProviderPackageFiles(url, id),
                }
            });
        }

        // Health
        if (path === "/api/health") {
            return json({ status: "healthy", timestamp: new Date().toISOString() });
        }

        return json({
            service: "OpenMesh Market API",
            endpoints: {
                "/api/v1/providers": "List traffic providers",
                "/api/v1/market/manifest": "Market manifest (version + providers)",
                "/api/v1/market/recommended": "Recommended providers",
                "/api/v1/market/providers": "Browse providers (pagination/sort/search)",
                "/api/v1/config/:id": "Get provider config",
                "/api/v1/providers/:id": "Get provider detail",
                "/api/v1/rules/:id/routing_rules.json": "Get provider force_proxy rules",
                "/api/health": "Health check"
            }
        });
    },
} satisfies ExportedHandler<Env>;
