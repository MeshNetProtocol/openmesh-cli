
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
    CORS_ALLOWED_ORIGINS?: string;
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

function json(resObj: unknown, status = 200, headers: Record<string, string> = {}) {
    return new Response(JSON.stringify(resObj), {
        status,
        headers: {
            "Content-Type": "application/json",
            ...headers,
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
        issues.push({ code: "URL_INVALID", message: `${field} invalid URL: ${s}` });
        return issues;
    }
    if (isUnsafePublicURL(u)) {
        issues.push({ code: "URL_UNSAFE", message: `${field} must be public https URL: ${u.toString()}` });
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

function safeParseJSON<T>(s: string): T | null {
    try {
        return JSON.parse(s) as T;
    } catch {
        return null;
    }
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

function makeMarketETag(version: number, updatedAt: string, providers: TrafficProvider[]): string {
    const parts = providers
        .map(p => [p.id, p.updated_at, p.provider_hash, p.package_hash].join("|"))
        .sort()
        .join(";");
    return `"market-v${version}-${updatedAt}-${parts}"`;
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
    const payload = [
        row.id,
        row.name,
        row.description,
        row.tags_json,
        row.author,
        row.updated_at,
        String(row.price_per_gb_usd ?? ""),
        row.visibility,
        row.status,
        packageHash,
    ].join("|");
    return `sha256:${await sha256Hex(payload)}`;
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

function extractRemoteRuleSets(configObj: unknown): Array<{ tag: string; url: string }> {
    if (!configObj || typeof configObj !== "object") return [];
    const cfg = configObj as Record<string, unknown>;
    const route = cfg.route;
    if (!route || typeof route !== "object") return [];
    const ruleSet = (route as Record<string, unknown>).rule_set;
    if (!Array.isArray(ruleSet)) return [];

    const out: Array<{ tag: string; url: string }> = [];
    for (const rsAny of ruleSet) {
        if (!rsAny || typeof rsAny !== "object") continue;
        const rs = rsAny as Record<string, unknown>;
        if (rs.type !== "remote") continue;
        const tag = typeof rs.tag === "string" ? rs.tag.trim() : "";
        const url = typeof rs.url === "string" ? sanitizeURLString(rs.url) : "";
        if (!tag || !url) continue;
        out.push({ tag, url });
    }
    return out;
}

function parsePortLike(value: unknown): number | null {
    if (typeof value === "number" && Number.isInteger(value)) return value;
    if (typeof value === "string") {
        const s = value.trim();
        if (!/^\d+$/.test(s)) return null;
        const n = Number.parseInt(s, 10);
        if (!Number.isFinite(n)) return null;
        return n;
    }
    return null;
}

function validateConfigCompatibility(config: unknown): PackageValidationIssue[] {
    const issues: PackageValidationIssue[] = [];
    if (!config || typeof config !== "object") {
        issues.push({ code: "CFG_INVALID_JSON", message: "config.json is not an object" });
        return issues;
    }

    const obj = config as Record<string, unknown>;
    const inbounds = obj.inbounds;
    if (Array.isArray(inbounds)) {
        for (const inboundAny of inbounds) {
            if (!inboundAny || typeof inboundAny !== "object") continue;
            const inbound = inboundAny as Record<string, unknown>;
            if (inbound.type !== "tun") continue;
            const stack = typeof inbound.stack === "string" ? inbound.stack.toLowerCase() : undefined;
            if (stack === "system" || stack === "mixed") {
                issues.push({
                    code: "CFG_TUN_STACK_INCOMPATIBLE",
                    message: "tun.stack cannot be system/mixed when includeAllNetworks is enabled",
                });
            }
        }
    }

    const route = obj.route;
    if (route && typeof route === "object") {
        const ruleSet = (route as Record<string, unknown>).rule_set;
        if (Array.isArray(ruleSet)) {
            for (const rsAny of ruleSet) {
                if (!rsAny || typeof rsAny !== "object") continue;
                const rs = rsAny as Record<string, unknown>;
                if (rs.type !== "remote") continue;
                const u = typeof rs.url === "string" ? rs.url : "";
                if (!u) continue;
                issues.push(...validateExternalURLString(u, "config.route.rule_set.url"));
            }
        }
    }

    const outbounds = obj.outbounds;
    if (Array.isArray(outbounds)) {
        for (const outboundAny of outbounds) {
            if (!outboundAny || typeof outboundAny !== "object") continue;
            const outbound = outboundAny as Record<string, unknown>;
            const type = typeof outbound.type === "string" ? outbound.type.toLowerCase() : "";
            if (type !== "shadowsocks") continue;
            const tag = typeof outbound.tag === "string" && outbound.tag.trim() ? outbound.tag.trim() : "shadowsocks";
            const port = parsePortLike(outbound.server_port);
            if (port === null || port < 1 || port > 65535) {
                issues.push({
                    code: "CFG_SHADOWSOCKS_SERVER_PORT_INVALID",
                    message: `outbound[${tag}] invalid server_port (must be 1-65535)`,
                });
            }
        }
    }

    return issues;
}

function validateProviderPackageFiles(files: ProviderPackageFile[]): PackageValidationIssue[] {
    const issues: PackageValidationIssue[] = [];
    const hasConfig = files.some(file => file.type === "config");
    if (!hasConfig) {
        issues.push({ code: "PKG_MISSING_CONFIG", message: "package.files missing type=config" });
    }

    for (const file of files) {
        if (file.type !== "rule_set") continue;
        if (!file.tag || !file.tag.trim()) {
            issues.push({ code: "PKG_RULESET_TAG_EMPTY", message: "rule_set.tag is required" });
        }
        if (file.mode !== "remote_url") {
            issues.push({ code: "PKG_RULESET_MODE_UNSUPPORTED", message: "rule_set.mode must be remote_url" });
        }
        issues.push(...validateExternalURLString(file.url, "package.files[rule_set].url"));
    }

    return issues;
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

function allowedOrigins(env: Env): string[] {
    const raw = (env.CORS_ALLOWED_ORIGINS || "").trim();
    if (!raw) return [];
    return raw.split(",").map(s => s.trim()).filter(Boolean);
}

function resolveCorsOrigin(request: Request, env: Env): { allowOrigin: string | null; forbidden: boolean } {
    const origin = request.headers.get("origin");
    if (!origin) return { allowOrigin: null, forbidden: false };

    const configured = allowedOrigins(env);
    if (configured.length === 0) return { allowOrigin: "*", forbidden: false };
    if (configured.includes("*") || configured.includes(origin)) return { allowOrigin: origin, forbidden: false };
    return { allowOrigin: null, forbidden: true };
}

function buildHeaders(allowOrigin: string | null, extra: Record<string, string> = {}): Record<string, string> {
    const headers: Record<string, string> = {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        ...extra,
    };
    if (allowOrigin) {
        headers["Access-Control-Allow-Origin"] = allowOrigin;
        headers["Vary"] = "Origin";
    }
    return headers;
}

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);
        const path = url.pathname;

        if (!env || !env.DB) {
            return json({ ok: false, error_code: "SERVER_NO_DB", error: "D1 database binding missing" }, 500);
        }

        const cors = resolveCorsOrigin(request, env);
        if (cors.forbidden) {
            return json(
                { ok: false, error_code: "CORS_ORIGIN_FORBIDDEN", error: "Origin is not allowed" },
                403,
                buildHeaders(cors.allowOrigin, { "Cache-Control": "no-store" }),
            );
        }

        if (request.method === "OPTIONS") {
            return new Response(null, {
                status: 204,
                headers: buildHeaders(cors.allowOrigin, {
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type",
                    "Access-Control-Max-Age": "86400",
                }),
            });
        }

        const respond = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
            json(body, status, buildHeaders(cors.allowOrigin, headers));

        const respondEmpty = (status = 204, headers: Record<string, string> = {}) =>
            new Response(null, { status, headers: buildHeaders(cors.allowOrigin, headers) });

        if (request.method === "GET" && path === "/api/v1/providers") {
            const providers = await buildProvidersForRequest(env, url);
            return respond({ ok: true, data: providers }, 200, { "Cache-Control": "public, max-age=60" });
        }

        if (request.method === "GET" && path === "/api/v1/market/manifest") {
            const providers = await buildProvidersForRequest(env, url);
            const version = marketVersion(env);
            const updatedAt = marketUpdatedAt(env, providers);
            const etag = makeMarketETag(version, updatedAt, providers);

            if (sameETag(request, etag)) {
                return respondEmpty(304, {
                    ETag: etag,
                    "Cache-Control": "public, max-age=0, must-revalidate",
                });
            }

            return respond(
                { ok: true, market_version: version, updated_at: updatedAt, providers },
                200,
                {
                    ETag: etag,
                    "Cache-Control": "public, max-age=0, must-revalidate",
                },
            );
        }

        if (request.method === "GET" && path === "/api/v1/market/recommended") {
            const providers = (await buildProvidersForRequest(env, url)).slice(0, 6);
            return respond({ ok: true, data: providers }, 200, { "Cache-Control": "public, max-age=60" });
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
            return respond({ ok: true, page, page_size: pageSize, total, data }, 200, { "Cache-Control": "public, max-age=60" });
        }

        const configMatch = path.match(/^\/api\/v1\/config\/([^/]+)$/);
        if (request.method === "GET" && configMatch) {
            const providerId = decodeURIComponent(configMatch[1]);
            const row = await getProviderRowByID(env, providerId);
            if (!row) return respond({ ok: false, error: "Config not found" }, 404, { "Cache-Control": "no-store" });
            const configObj = safeParseJSON<unknown>(row.config_json);
            if (!configObj) return respond({ ok: false, error: "Invalid config JSON" }, 500, { "Cache-Control": "no-store" });
            const rewritten = rewriteMarketHostInObject(configObj, baseURL(url));
            return respond(rewritten, 200, { "Cache-Control": "public, max-age=60" });
        }

        const rulesMatch = path.match(/^\/api\/v1\/rules\/([^/]+)\/routing_rules\.json$/);
        if (request.method === "GET" && rulesMatch) {
            const providerId = decodeURIComponent(rulesMatch[1]);
            const row = await getProviderRowByID(env, providerId);
            if (!row || !row.routing_rules_json) {
                return respond({ ok: false, error: "Rules not found" }, 404, { "Cache-Control": "no-store" });
            }
            const rules = safeParseJSON<unknown>(row.routing_rules_json);
            if (!rules) return respond({ ok: false, error: "Invalid rules JSON" }, 500, { "Cache-Control": "no-store" });
            return respond(rules, 200, { "Cache-Control": "public, max-age=60" });
        }

        const providerDetailMatch = path.match(/^\/api\/v1\/providers\/([^/]+)$/);
        if (request.method === "GET" && providerDetailMatch) {
            const providerId = decodeURIComponent(providerDetailMatch[1]);
            const row = await getProviderRowByID(env, providerId);
            if (!row) return respond({ ok: false, error: "Provider not found" }, 404, { "Cache-Control": "no-store" });

            const configObj = safeParseJSON<unknown>(row.config_json);
            if (!configObj) return respond({ ok: false, error: "Invalid config JSON" }, 500, { "Cache-Control": "no-store" });

            const packageHash = await computePackageHash(row);
            const providerHash = await computeProviderHash(row, packageHash);
            const provider = toTrafficProvider(url, row, providerHash, packageHash);
            const files = buildProviderPackageFiles(url, provider, configObj, !!row.routing_rules_json);
            const issues = [
                ...validateProviderPackageFiles(files),
                ...validateConfigCompatibility(configObj),
            ];

            if (issues.length > 0) {
                const response: ProviderDetailResponse = {
                    ok: false,
                    error_code: issues[0].code,
                    error: issues[0].message,
                    details: issues.map(issue => `${issue.code}: ${issue.message}`),
                };
                return respond(response, 422, { "Cache-Control": "no-store" });
            }

            const response: ProviderDetailResponse = {
                ok: true,
                provider,
                package: {
                    package_hash: packageHash,
                    files,
                },
            };
            return respond(response, 200, { "Cache-Control": "public, max-age=60" });
        }

        if (request.method === "GET" && path === "/api/health") {
            return respond({ status: "healthy", timestamp: new Date().toISOString() }, 200, { "Cache-Control": "no-store" });
        }

        if (request.method === "GET" && (path === "/" || path === "/api")) {
            return respond({
                service: "OpenMesh Market API",
                mode: "providers-readonly",
                endpoints: {
                    "/api/v1/providers": "List active public providers",
                    "/api/v1/market/manifest": "Market manifest",
                    "/api/v1/market/recommended": "Recommended providers",
                    "/api/v1/market/providers": "Browse providers",
                    "/api/v1/config/:id": "Get provider config",
                    "/api/v1/providers/:id": "Get provider detail",
                    "/api/v1/rules/:id/routing_rules.json": "Get provider routing rules",
                    "/api/health": "Health check",
                },
            }, 200, { "Cache-Control": "no-store" });
        }

        return respond({ ok: false, error: "Not found" }, 404, { "Cache-Control": "no-store" });
    },
};
