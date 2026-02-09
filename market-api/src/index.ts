/**
 * OpenMesh API - Traffic Market & AASA
 */

interface Env {
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

type ProviderPackage = {
    package_hash: string;
    files: ProviderPackageFile[];
};

type ProviderDetailOkResponse = {
    ok: true;
    provider: TrafficProvider;
    package: ProviderPackage;
};

type ProviderDetailErrorResponse = {
    ok: false;
    error_code: string;
    error: string;
    details?: string[];
};

type ProviderDetailResponse = ProviderDetailOkResponse | ProviderDetailErrorResponse;

type PackageValidationIssue = {
    code: string;
    message: string;
};

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
        provider_hash: "sha256:mock-official-online-provider-v3",
        package_hash: "sha256:mock-official-online-package-v3",
        price_per_gb_usd: 0.0,
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
                "stack": "gvisor"
            }
        ],
        "log": {
            "level": "debug"
        },
        "outbounds": [
            {
                "type": "shadowsocks",
                "tag": "online-ss-1",
                "server": "45.32.115.168",
                "server_port": 10086,
                "method": "aes-256-gcm",
                "password": "yourpassword123"
            },
            {
                "type": "shadowsocks",
                "tag": "online-ss-2",
                "server": "216.128.182.150",
                "server_port": 10086,
                "method": "aes-256-gcm",
                "password": "yourpassword123"
            },
            {
                "type": "selector",
                "tag": "proxy",
                "outbounds": [
                    "online-ss-1",
                    "online-ss-2"
                ],
                "default": "online-ss-1"
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
    }
};

const MOCK_FORCE_PROXY_RULES: Record<string, unknown> = {
    "official-online": {
        proxy: {
            domain_suffix: [
                ".openai.com",
                ".chatgpt.com",
                ".anthropic.com",
                ".google.com",
                ".x.com"
            ],
            domain: [
                "api.openai.com"
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

function makeMarketETag(marketVersion: number, updatedAt: string, providers: TrafficProvider[]): string {
    const parts = providers
        .map(p => [
            p.id,
            p.updated_at,
            p.provider_hash || "",
            p.package_hash || "",
        ].join("|"))
        .sort()
        .join(";");
    return `"market-v${marketVersion}-${updatedAt}-${parts}"`;
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
    return [
        { type: "config", url: `${base}/api/v1/config/${encodeURIComponent(providerID)}` },
        { type: "force_proxy", url: `${base}/api/v1/rules/${encodeURIComponent(providerID)}/routing_rules.json` },
    ];
}

function isDisallowedRuleSetURL(u: URL): boolean {
    const host = u.hostname.toLowerCase();
    if (host.endsWith("githubusercontent.com")) return true;
    if (host === "github.com") return true;
    return false;
}

function validateProviderPackageFiles(files: ProviderPackageFile[]): PackageValidationIssue[] {
    const issues: PackageValidationIssue[] = [];
    const hasConfig = files.some(f => f.type === "config");
    if (!hasConfig) issues.push({ code: "PKG_MISSING_CONFIG", message: "package.files 缺少 type=config" });

    for (const f of files) {
        if ("url" in f) {
            const s = sanitizeURLString(f.url);
            let u: URL | null = null;
            try {
                u = new URL(s);
            } catch {
                issues.push({ code: "PKG_INVALID_URL", message: `无效 URL：${s}` });
                continue;
            }
            if (f.type === "rule_set" && isDisallowedRuleSetURL(u)) {
                issues.push({
                    code: "PKG_RULESET_URL_DISALLOWED",
                    message: `rule_set.url 不允许使用 GitHub 源：${u.toString()}`,
                });
            }
        }
        if (f.type === "rule_set") {
            if (!f.tag || !f.tag.trim()) issues.push({ code: "PKG_RULESET_TAG_EMPTY", message: "rule_set.tag 不能为空" });
            if (f.mode !== "remote_url") issues.push({ code: "PKG_RULESET_MODE_UNSUPPORTED", message: "rule_set.mode 仅支持 remote_url" });
        }
    }

    return issues;
}

function validateConfigCompatibility(config: unknown): PackageValidationIssue[] {
    const issues: PackageValidationIssue[] = [];
    if (!config || typeof config !== "object") {
        issues.push({ code: "CFG_INVALID_JSON", message: "config.json 不是有效对象" });
        return issues;
    }
    const obj = config as Record<string, unknown>;
    const inbounds = obj["inbounds"];
    if (Array.isArray(inbounds)) {
        for (const inboundAny of inbounds) {
            if (!inboundAny || typeof inboundAny !== "object") continue;
            const inbound = inboundAny as Record<string, unknown>;
            if (inbound["type"] !== "tun") continue;
            const stack = typeof inbound["stack"] === "string" ? inbound["stack"].toLowerCase() : undefined;
            if (stack === "system" || stack === "mixed") {
                issues.push({
                    code: "CFG_TUN_STACK_INCOMPATIBLE",
                    message: "tun.stack 不兼容：includeAllNetworks 启用时不能为 system/mixed（请改为 gvisor 或移除 stack 字段）",
                });
            }
        }
    }
    return issues;
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
            const etag = makeMarketETag(mv, updated_at, providers);
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
            const files = buildProviderPackageFiles(url, id);
            const pkgIssues = validateProviderPackageFiles(files);
            const cfg = MOCK_CONFIGS[id];
            const cfgIssues = validateConfigCompatibility(cfg);
            const issues = [...pkgIssues, ...cfgIssues];
            if (issues.length > 0) {
                const response: ProviderDetailResponse = {
                    ok: false,
                    error_code: issues[0].code,
                    error: issues[0].message,
                    details: issues.map(i => `${i.code}: ${i.message}`),
                };
                return json(response, 422);
            }
            const response: ProviderDetailResponse = {
                ok: true,
                provider,
                package: {
                    package_hash: provider.package_hash || "sha256:mock-package",
                    files,
                },
            };
            return json(response);
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
                "/assets/rule-set/:filename": "Get rule-set binary (proxyable)",
                "/api/health": "Health check"
            }
        });
    },
};
