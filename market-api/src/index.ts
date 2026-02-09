interface D1PreparedStatementLike {
    bind(...values: unknown[]): D1PreparedStatementLike;
    first<T = unknown>(): Promise<T | null>;
    all<T = unknown>(): Promise<{ results: T[] }>;
    run(): Promise<unknown>;
}

interface D1DatabaseLike {
    prepare(query: string): D1PreparedStatementLike;
}

interface Env {
    DB: D1DatabaseLike;
    MARKET_VERSION?: string;
    MARKET_UPDATED_AT?: string;
}

type ProviderVisibility = "public" | "private";
type ProviderStatus = "active" | "disabled";

type ProviderRow = {
    id: string;
    name: string;
    description: string;
    tags_json: string;
    author: string;
    updated_at: string;
    price_per_gb_usd: number | null;
    visibility: ProviderVisibility;
    status: ProviderStatus;
    config_json: string;
    routing_rules_json: string | null;
};

interface TrafficProvider {
    id: string;
    name: string;
    description: string;
    config_url: string;
    tags: string[];
    icon_url?: string;
    author: string;
    updated_at: string;
    provider_hash: string;
    package_hash: string;
    price_per_gb_usd?: number;
    detail_url: string;
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

function corsHeaders(): Record<string, string> {
    return {
        "Access-Control-Allow-Origin": "*",
    };
}

function json(resObj: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
    return new Response(JSON.stringify(resObj), {
        status,
        headers: {
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=60",
            ...corsHeaders(),
            ...extraHeaders,
        },
    });
}

function sanitizeURLString(s: string): string {
    let out = s.trim();
    if ((out.startsWith("`") && out.endsWith("`")) || (out.startsWith("“") && out.endsWith("”"))) {
        out = out.slice(1, -1).trim();
    }
    out = out.replaceAll("`", "").trim();
    return out;
}

function baseURL(url: URL): string {
    const hostname = url.hostname === "localhost" ? "127.0.0.1" : url.hostname;
    const host = url.port ? `${hostname}:${url.port}` : hostname;
    return `${url.protocol}//${host}`;
}

function isUnsafePublicURL(u: URL): boolean {
    const protocol = u.protocol.toLowerCase();
    if (protocol !== "https:") return true;
    const host = u.hostname.toLowerCase();
    if (!host) return true;
    if (host === "localhost") return true;
    if (host.endsWith(".localhost")) return true;
    if (host === "127.0.0.1" || host === "::1") return true;
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) {
        const parts = host.split(".").map(n => Number.parseInt(n, 10));
        if (parts.some(n => !Number.isFinite(n) || n < 0 || n > 255)) return true;
        const [a, b] = parts;
        if (a === 10) return true;
        if (a === 127) return true;
        if (a === 192 && b === 168) return true;
        if (a === 172 && b >= 16 && b <= 31) return true;
        if (a === 169 && b === 254) return true;
    }
    if (u.username || u.password) return true;
    return false;
}

function validateExternalURLString(urlString: string, field: string): PackageValidationIssue[] {
    const issues: PackageValidationIssue[] = [];
    const s = sanitizeURLString(urlString);
    let u: URL;
    try {
        u = new URL(s);
    } catch {
        issues.push({ code: "URL_INVALID", message: `${field} 无效 URL：${s}` });
        return issues;
    }
    if (isUnsafePublicURL(u)) {
        issues.push({ code: "URL_UNSAFE", message: `${field} 必须是可公开访问的 https URL（禁止 localhost/私网IP/凭据）：${u.toString()}` });
    }
    return issues;
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

function marketVersion(env: Env): number {
    const s = (env.MARKET_VERSION || "").trim();
    const n = Number.parseInt(s, 10);
    return Number.isFinite(n) ? n : 1;
}

function marketUpdatedAt(env: Env, providers: TrafficProvider[]): string {
    const envUpdatedAt = (env.MARKET_UPDATED_AT || "").trim();
    if (envUpdatedAt) return envUpdatedAt;
    const max = providers.map(p => p.updated_at).sort().slice(-1)[0];
    return max || new Date().toISOString();
}

function makeMarketETag(marketVersion: number, updatedAt: string, providers: TrafficProvider[]): string {
    const parts = providers
        .map(p => [p.id, p.updated_at, p.provider_hash, p.package_hash].join("|"))
        .sort()
        .join(";");
    return `"market-v${marketVersion}-${updatedAt}-${parts}"`;
}

function sameETag(request: Request, etag: string): boolean {
    const inm = request.headers.get("if-none-match");
    if (!inm) return false;
    return inm.split(",").map(s => s.trim()).includes(etag);
}

async function sha256Hex(input: string): Promise<string> {
    const bytes = new TextEncoder().encode(input);
    const hash = await crypto.subtle.digest("SHA-256", bytes);
    const arr = Array.from(new Uint8Array(hash));
    return arr.map(b => b.toString(16).padStart(2, "0")).join("");
}

async function computePackageHash(row: ProviderRow): Promise<string> {
    const routing = row.routing_rules_json || "";
    const payload = `config.json\0${row.config_json}\nrouting_rules.json\0${routing}\n`;
    return `sha256:${await sha256Hex(payload)}`;
}

async function computeProviderHash(row: ProviderRow, packageHash: string): Promise<string> {
    const tags = row.tags_json || "[]";
    const payload = [
        row.id,
        row.name,
        row.description,
        tags,
        row.author,
        row.updated_at,
        String(row.price_per_gb_usd ?? ""),
        row.visibility,
        row.status,
        packageHash,
    ].join("|");
    return `sha256:${await sha256Hex(payload)}`;
}

function safeParseJSON<T>(s: string): T | null {
    try {
        return JSON.parse(s) as T;
    } catch {
        return null;
    }
}

function validateProviderPackageFiles(files: ProviderPackageFile[]): PackageValidationIssue[] {
    const issues: PackageValidationIssue[] = [];
    const hasConfig = files.some(f => f.type === "config");
    if (!hasConfig) issues.push({ code: "PKG_MISSING_CONFIG", message: "package.files 缺少 type=config" });

    for (const f of files) {
        if (f.type === "rule_set") {
            if (f.url) issues.push(...validateExternalURLString(f.url, "package.files[rule_set].url"));
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
    const route = obj["route"];
    if (route && typeof route === "object") {
        const r = route as Record<string, unknown>;
        const ruleSet = r["rule_set"];
        if (Array.isArray(ruleSet)) {
            for (const rsAny of ruleSet) {
                if (!rsAny || typeof rsAny !== "object") continue;
                const rs = rsAny as Record<string, unknown>;
                if (rs["type"] !== "remote") continue;
                const u = typeof rs["url"] === "string" ? rs["url"] : "";
                if (!u) continue;
                issues.push(...validateExternalURLString(u, "config.route.rule_set.url"));
            }
        }
    }
    return issues;
}

function extractRemoteRuleSets(configObj: unknown): Array<{ tag: string; url: string }> {
    if (!configObj || typeof configObj !== "object") return [];
    const cfg = configObj as Record<string, unknown>;
    const route = cfg["route"];
    if (!route || typeof route !== "object") return [];
    const r = route as Record<string, unknown>;
    const ruleSet = r["rule_set"];
    if (!Array.isArray(ruleSet)) return [];
    const out: Array<{ tag: string; url: string }> = [];
    for (const rsAny of ruleSet) {
        if (!rsAny || typeof rsAny !== "object") continue;
        const rs = rsAny as Record<string, unknown>;
        if (rs["type"] !== "remote") continue;
        const tag = typeof rs["tag"] === "string" ? rs["tag"].trim() : "";
        const url = typeof rs["url"] === "string" ? sanitizeURLString(rs["url"]) : "";
        if (!tag || !url) continue;
        out.push({ tag, url });
    }
    return out;
}

function toTrafficProvider(url: URL, row: ProviderRow, providerHash: string, packageHash: string): TrafficProvider {
    const base = baseURL(url);
    const tags = safeParseJSON<string[]>(row.tags_json) || [];
    return {
        id: row.id,
        name: row.name,
        description: row.description,
        config_url: `${base}/api/v1/config/${encodeURIComponent(row.id)}`,
        tags,
        author: row.author,
        updated_at: row.updated_at,
        provider_hash: providerHash,
        package_hash: packageHash,
        price_per_gb_usd: row.price_per_gb_usd ?? undefined,
        detail_url: `${base}/api/v1/providers/${encodeURIComponent(row.id)}`,
    };
}

async function listProviderRows(env: Env): Promise<ProviderRow[]> {
    const res = await env.DB.prepare(
        "SELECT id,name,description,tags_json,author,updated_at,price_per_gb_usd,visibility,status,config_json,routing_rules_json FROM providers WHERE visibility='public' AND status='active' ORDER BY updated_at DESC"
    ).all<ProviderRow>();
    return res.results || [];
}

async function getProviderRowByID(env: Env, id: string): Promise<ProviderRow | null> {
    return await env.DB.prepare(
        "SELECT id,name,description,tags_json,author,updated_at,price_per_gb_usd,visibility,status,config_json,routing_rules_json FROM providers WHERE id=? LIMIT 1"
    ).bind(id).first<ProviderRow>();
}

function buildProviderPackageFiles(url: URL, provider: TrafficProvider, configObj: unknown, hasRoutingRules: boolean): ProviderPackageFile[] {
    const base = baseURL(url);
    const files: ProviderPackageFile[] = [
        { type: "config", url: `${base}/api/v1/config/${encodeURIComponent(provider.id)}` },
    ];
    if (hasRoutingRules) {
        files.push({ type: "force_proxy", url: `${base}/api/v1/rules/${encodeURIComponent(provider.id)}/routing_rules.json` });
    }
    for (const rs of extractRemoteRuleSets(configObj)) {
        files.push({
            type: "rule_set",
            tag: rs.tag,
            mode: "remote_url",
            url: rs.url,
        });
    }

    return files;
}

async function buildProvidersForRequest(env: Env, url: URL): Promise<TrafficProvider[]> {
    const rows = await listProviderRows(env);
    const providers: TrafficProvider[] = [];
    for (const row of rows) {
        const packageHash = await computePackageHash(row);
        const providerHash = await computeProviderHash(row, packageHash);
        providers.push(toTrafficProvider(url, row, providerHash, packageHash));
    }
    return providers;
}

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);
        const path = url.pathname;

        if (!env || !env.DB) {
            return json({ ok: false, error_code: "SERVER_NO_DB", error: "D1 database binding missing" }, 500);
        }

        if (request.method === "OPTIONS") {
            return new Response(null, {
                status: 204,
                headers: {
                    ...corsHeaders(),
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Max-Age": "86400",
                },
            });
        }

        if (request.method === "GET" && path === "/api/v1/providers") {
            const providers = await buildProvidersForRequest(env, url);
            return json({ ok: true, data: providers });
        }

        if (request.method === "GET" && path === "/api/v1/market/manifest") {
            const providers = await buildProvidersForRequest(env, url);
            const mv = marketVersion(env);
            const updated_at = marketUpdatedAt(env, providers);
            const etag = makeMarketETag(mv, updated_at, providers);
            if (sameETag(request, etag)) {
                return new Response(null, {
                    status: 304,
                    headers: {
                        ...corsHeaders(),
                        "ETag": etag,
                        "Cache-Control": "public, max-age=60",
                    },
                });
            }
            return json(
                { ok: true, market_version: mv, updated_at, providers },
                200,
                {
                    "ETag": etag,
                    "Cache-Control": "public, max-age=60",
                }
            );
        }

        if (request.method === "GET" && path === "/api/v1/market/recommended") {
            const providers = (await buildProvidersForRequest(env, url)).slice(0, 6);
            return json({ ok: true, data: providers });
        }

        if (request.method === "GET" && path === "/api/v1/market/providers") {
            const providers = await buildProvidersForRequest(env, url);
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
            if (order !== "asc") filtered = filtered.reverse();

            const total = filtered.length;
            const start = (page - 1) * pageSize;
            const data = filtered.slice(start, start + pageSize);
            return json({ ok: true, page, page_size: pageSize, total, data });
        }

        const configMatch = path.match(/^\/api\/v1\/config\/([^\/]+)$/);
        if (request.method === "GET" && configMatch) {
            const id = configMatch[1];
            const row = await getProviderRowByID(env, id);
            if (!row) return json({ ok: false, error: "Config not found" }, 404);
            const base = baseURL(url);
            const cfgObj = safeParseJSON<unknown>(row.config_json);
            if (!cfgObj) return json({ ok: false, error: "Invalid config JSON" }, 500);
            const rewrittenMarket = rewriteMarketHostInObject(cfgObj, base);
            return json(rewrittenMarket);
        }

        const rulesMatch = path.match(/^\/api\/v1\/rules\/([^\/]+)\/routing_rules\.json$/);
        if (request.method === "GET" && rulesMatch) {
            const id = rulesMatch[1];
            const row = await getProviderRowByID(env, id);
            if (!row || !row.routing_rules_json) return json({ ok: false, error: "Rules not found" }, 404);
            const rules = safeParseJSON<unknown>(row.routing_rules_json);
            if (!rules) return json({ ok: false, error: "Invalid rules JSON" }, 500);
            return json(rules);
        }

        const providerDetailMatch = path.match(/^\/api\/v1\/providers\/([^\/]+)$/);
        if (request.method === "GET" && providerDetailMatch) {
            const id = providerDetailMatch[1];
            const row = await getProviderRowByID(env, id);
            if (!row) return json({ ok: false, error: "Provider not found" }, 404);
            const cfgObj = safeParseJSON<unknown>(row.config_json);
            if (!cfgObj) return json({ ok: false, error: "Invalid config JSON" }, 500);

            const packageHash = await computePackageHash(row);
            const providerHash = await computeProviderHash(row, packageHash);
            const provider = toTrafficProvider(url, row, providerHash, packageHash);
            const files = buildProviderPackageFiles(url, provider, cfgObj, !!row.routing_rules_json);

            const issues = [
                ...validateProviderPackageFiles(files),
                ...validateConfigCompatibility(cfgObj),
            ];
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
                    package_hash: packageHash,
                    files,
                },
            };
            return json(response);
        }

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
                "/api/health": "Health check",
            },
        });
    },
};
