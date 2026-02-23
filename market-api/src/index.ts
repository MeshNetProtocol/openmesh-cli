import { getAddress, isAddressEqual, recoverMessageAddress, type Hex } from "viem";

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
    AUTH_JWT_SECRET?: string;
    AUTH_NONCE_TTL_SECONDS?: string;
    AUTH_TOKEN_TTL_SECONDS?: string;
    AUTH_ALLOWED_CHAIN_IDS?: string;
    AUTH_DOMAIN?: string;
    AUTH_URI?: string;
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

type SupplierStatus = "active" | "disabled";

type SupplierRow = {
    id: string;
    name: string;
    description: string;
    owner_wallet: string;
    status: SupplierStatus;
    created_at: string;
    updated_at: string;
};

type SupplierConfigRow = {
    supplier_id: string;
    config_json: string;
    updated_at: string;
    updated_by_wallet: string;
};

type SupplierManagerRow = {
    supplier_id: string;
    manager_wallet: string;
    role: string;
    created_at: string;
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

type AuthNonceRow = {
    nonce: string;
    expires_at: string;
    used_at: string | null;
};

type ParsedSiweMessage = {
    domain: string;
    address: string;
    uri: string;
    version: string;
    chainId: number;
    nonce: string;
    issuedAt: string;
    expirationTime?: string;
};

type JwtPayload = {
    sub: string;
    chain_id: number;
    iat: number;
    exp: number;
    iss: string;
    aud: string;
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

function parsePositiveInt(input: string | undefined, fallback: number): number {
    if (!input) return fallback;
    const n = Number.parseInt(input.trim(), 10);
    if (!Number.isFinite(n) || n <= 0) return fallback;
    return n;
}

function authNonceTTLSeconds(env: Env): number {
    return parsePositiveInt(env.AUTH_NONCE_TTL_SECONDS, 300);
}

function authTokenTTLSeconds(env: Env): number {
    return parsePositiveInt(env.AUTH_TOKEN_TTL_SECONDS, 900);
}

function allowedChainIds(env: Env): number[] {
    const raw = (env.AUTH_ALLOWED_CHAIN_IDS || "1").trim();
    const parsed = raw
        .split(",")
        .map(s => Number.parseInt(s.trim(), 10))
        .filter(n => Number.isFinite(n) && n > 0);
    return parsed.length > 0 ? parsed : [1];
}

function expectedDomain(env: Env, requestURL: URL): string {
    return (env.AUTH_DOMAIN || requestURL.host).trim().toLowerCase();
}

function expectedURI(env: Env, requestURL: URL): URL {
    const raw = (env.AUTH_URI || baseURL(requestURL)).trim();
    try {
        return new URL(raw);
    } catch {
        return new URL(baseURL(requestURL));
    }
}

function randomNonce(bytes = 18): string {
    const random = new Uint8Array(bytes);
    crypto.getRandomValues(random);
    const asBinary = Array.from(random).map(n => String.fromCharCode(n)).join("");
    const b64 = btoa(asBinary);
    return b64.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function isHexSignature(value: string): value is Hex {
    return /^0x[0-9a-fA-F]{130}$/.test(value);
}

function parseSiweMessage(message: string): ParsedSiweMessage | null {
    const lines = message.replaceAll("\r\n", "\n").split("\n");
    if (lines.length < 6) return null;
    const wants = " wants you to sign in with your Ethereum account:";
    if (!lines[0].endsWith(wants)) return null;

    const domain = lines[0].slice(0, -wants.length).trim();
    const address = lines[1].trim();
    if (!domain || !address) return null;

    const kv: Record<string, string> = {};
    for (const line of lines) {
        const sep = line.indexOf(": ");
        if (sep <= 0) continue;
        const key = line.slice(0, sep).trim();
        const value = line.slice(sep + 2).trim();
        if (!value) continue;
        kv[key] = value;
    }

    const chainId = Number.parseInt(kv["Chain ID"] || "", 10);
    if (!Number.isFinite(chainId) || chainId <= 0) return null;

    const nonce = kv["Nonce"] || "";
    if (!/^[A-Za-z0-9\-_]{8,}$/.test(nonce)) return null;

    const uri = kv["URI"] || "";
    const version = kv["Version"] || "";
    const issuedAt = kv["Issued At"] || "";
    const expirationTime = kv["Expiration Time"];
    if (!uri || !version || !issuedAt) return null;

    return {
        domain,
        address,
        uri,
        version,
        chainId,
        nonce,
        issuedAt,
        expirationTime,
    };
}

function toUnixSeconds(inputISO: string): number | null {
    const ms = Date.parse(inputISO);
    if (!Number.isFinite(ms)) return null;
    return Math.floor(ms / 1000);
}

async function insertNonce(env: Env, nonce: string, expiresAtISO: string): Promise<void> {
    await env.DB.prepare("INSERT INTO auth_nonces (nonce, expires_at) VALUES (?, ?)")
        .bind(nonce, expiresAtISO)
        .run();
}

async function getAuthNonce(env: Env, nonce: string): Promise<AuthNonceRow | null> {
    return await env.DB.prepare("SELECT nonce, expires_at, used_at FROM auth_nonces WHERE nonce=? LIMIT 1")
        .bind(nonce)
        .first<AuthNonceRow>();
}

function d1Changes(result: unknown): number {
    if (!result || typeof result !== "object") return 0;
    const meta = (result as { meta?: { changes?: unknown } }).meta;
    if (!meta || typeof meta !== "object") return 0;
    const changes = (meta as { changes?: unknown }).changes;
    return typeof changes === "number" ? changes : 0;
}

async function consumeNonce(env: Env, nonce: string, usedAtISO: string): Promise<boolean> {
    const result = await env.DB.prepare("UPDATE auth_nonces SET used_at=? WHERE nonce=? AND used_at IS NULL")
        .bind(usedAtISO, nonce)
        .run();
    return d1Changes(result) > 0;
}

function base64urlEncodeBytes(bytes: Uint8Array): string {
    const asBinary = Array.from(bytes).map(b => String.fromCharCode(b)).join("");
    return btoa(asBinary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function base64urlEncodeJSON(value: unknown): string {
    const jsonString = JSON.stringify(value);
    const bytes = new TextEncoder().encode(jsonString);
    return base64urlEncodeBytes(bytes);
}

function base64urlDecodeString(base64url: string): string | null {
    const base64 = base64url.replaceAll("-", "+").replaceAll("_", "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    try {
        return atob(padded);
    } catch {
        return null;
    }
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i += 1) {
        diff |= a[i] ^ b[i];
    }
    return diff === 0;
}

async function hmacSha256(secret: string, value: string): Promise<Uint8Array> {
    const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
    );
    const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
    return new Uint8Array(signature);
}

async function signJWT(payload: JwtPayload, secret: string): Promise<string> {
    const header = { alg: "HS256", typ: "JWT" };
    const encodedHeader = base64urlEncodeJSON(header);
    const encodedPayload = base64urlEncodeJSON(payload);
    const signingInput = `${encodedHeader}.${encodedPayload}`;
    const signature = await hmacSha256(secret, signingInput);
    return `${signingInput}.${base64urlEncodeBytes(signature)}`;
}

async function verifyJWT(token: string, secret: string): Promise<JwtPayload | null> {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const [encodedHeader, encodedPayload, encodedSig] = parts;
    const signingInput = `${encodedHeader}.${encodedPayload}`;
    const expectedSig = await hmacSha256(secret, signingInput);
    const decodedSigRaw = base64urlDecodeString(encodedSig);
    if (!decodedSigRaw) return null;
    const actualSig = new Uint8Array(Array.from(decodedSigRaw).map(c => c.charCodeAt(0)));
    if (!constantTimeEqual(expectedSig, actualSig)) return null;

    const payloadRaw = base64urlDecodeString(encodedPayload);
    if (!payloadRaw) return null;
    const payload = safeParseJSON<JwtPayload>(payloadRaw);
    if (!payload) return null;
    if (!payload.sub || typeof payload.sub !== "string") return null;
    if (!Number.isFinite(payload.exp) || !Number.isFinite(payload.iat) || !Number.isFinite(payload.chain_id)) return null;
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp <= now) return null;
    return payload;
}

async function requireAuth(request: Request, env: Env): Promise<{ wallet: string; chainId: number; exp: number } | null> {
    const authHeader = request.headers.get("authorization") || "";
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!match) return null;
    const token = match[1].trim();
    if (!token) return null;
    const secret = (env.AUTH_JWT_SECRET || "").trim();
    if (!secret) return null;
    const payload = await verifyJWT(token, secret);
    if (!payload) return null;
    return {
        wallet: payload.sub,
        chainId: payload.chain_id,
        exp: payload.exp,
    };
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
    const outbounds = obj["outbounds"];
    if (Array.isArray(outbounds)) {
        for (const outboundAny of outbounds) {
            if (!outboundAny || typeof outboundAny !== "object") continue;
            const outbound = outboundAny as Record<string, unknown>;
            const type = typeof outbound["type"] === "string" ? outbound["type"].toLowerCase() : "";
            if (type !== "shadowsocks") continue;
            const tag = typeof outbound["tag"] === "string" && outbound["tag"].trim()
                ? outbound["tag"].trim()
                : "shadowsocks";
            const port = parsePortLike(outbound["server_port"]);
            if (port === null || port < 1 || port > 65535) {
                issues.push({
                    code: "CFG_SHADOWSOCKS_SERVER_PORT_INVALID",
                    message: `outbound[${tag}] 缺少合法 server_port（必须是 1-65535 的整数）`,
                });
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

type SupplierIdentity = {
    supplier: SupplierRow;
    role: "owner" | "manager";
    manager_role?: string;
};

function normalizeWallet(input: string): string | null {
    const trimmed = input.trim();
    if (!trimmed) return null;
    try {
        return getAddress(trimmed).toLowerCase();
    } catch {
        return null;
    }
}

function sanitizeSupplierName(value: unknown): string | null {
    if (typeof value !== "string") return null;
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.length > 120) return null;
    return trimmed;
}

function sanitizeSupplierDescription(value: unknown): string {
    if (typeof value !== "string") return "";
    const trimmed = value.trim();
    return trimmed.slice(0, 4000);
}

function parseSupplierStatus(value: unknown): SupplierStatus | null {
    if (typeof value !== "string") return null;
    const trimmed = value.trim().toLowerCase();
    if (trimmed === "active" || trimmed === "disabled") return trimmed;
    return null;
}

function makeSupplierId(): string {
    return `sup_${randomNonce(12)}`;
}

async function getSupplierByOwnerWallet(env: Env, ownerWallet: string): Promise<SupplierRow | null> {
    return await env.DB.prepare(
        "SELECT id,name,description,owner_wallet,status,created_at,updated_at FROM suppliers WHERE owner_wallet=? LIMIT 1"
    ).bind(ownerWallet).first<SupplierRow>();
}

type SupplierJoinRow = SupplierRow & { manager_role: string };

async function getSupplierByManagerWallet(env: Env, managerWallet: string): Promise<SupplierJoinRow | null> {
    return await env.DB.prepare(
        "SELECT s.id,s.name,s.description,s.owner_wallet,s.status,s.created_at,s.updated_at,m.role as manager_role FROM supplier_managers m INNER JOIN suppliers s ON s.id=m.supplier_id WHERE m.manager_wallet=? LIMIT 1"
    ).bind(managerWallet).first<SupplierJoinRow>();
}

async function getSupplierIdentityByWallet(env: Env, wallet: string): Promise<SupplierIdentity | null> {
    const owned = await getSupplierByOwnerWallet(env, wallet);
    if (owned) {
        return { supplier: owned, role: "owner" };
    }
    const managed = await getSupplierByManagerWallet(env, wallet);
    if (managed) {
        return {
            supplier: {
                id: managed.id,
                name: managed.name,
                description: managed.description,
                owner_wallet: managed.owner_wallet,
                status: managed.status,
                created_at: managed.created_at,
                updated_at: managed.updated_at,
            },
            role: "manager",
            manager_role: managed.manager_role,
        };
    }
    return null;
}

async function createSupplier(env: Env, ownerWallet: string, name: string, description: string): Promise<SupplierRow> {
    const now = new Date().toISOString();
    const row: SupplierRow = {
        id: makeSupplierId(),
        name,
        description,
        owner_wallet: ownerWallet,
        status: "active",
        created_at: now,
        updated_at: now,
    };

    await env.DB.prepare(
        "INSERT INTO suppliers (id,name,description,owner_wallet,status,created_at,updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
    ).bind(
        row.id,
        row.name,
        row.description,
        row.owner_wallet,
        row.status,
        row.created_at,
        row.updated_at,
    ).run();

    await env.DB.prepare(
        "INSERT INTO supplier_configs (supplier_id,config_json,updated_at,updated_by_wallet) VALUES (?, ?, ?, ?)"
    ).bind(
        row.id,
        "{}",
        now,
        ownerWallet,
    ).run();

    return row;
}

async function updateSupplier(env: Env, supplierID: string, patch: { name?: string; description?: string; status?: SupplierStatus }): Promise<void> {
    const updates: string[] = [];
    const values: unknown[] = [];
    if (patch.name !== undefined) {
        updates.push("name=?");
        values.push(patch.name);
    }
    if (patch.description !== undefined) {
        updates.push("description=?");
        values.push(patch.description);
    }
    if (patch.status !== undefined) {
        updates.push("status=?");
        values.push(patch.status);
    }
    updates.push("updated_at=?");
    values.push(new Date().toISOString());
    values.push(supplierID);

    await env.DB.prepare(
        `UPDATE suppliers SET ${updates.join(", ")} WHERE id=?`
    ).bind(...values).run();
}

async function getSupplierById(env: Env, supplierID: string): Promise<SupplierRow | null> {
    return await env.DB.prepare(
        "SELECT id,name,description,owner_wallet,status,created_at,updated_at FROM suppliers WHERE id=? LIMIT 1"
    ).bind(supplierID).first<SupplierRow>();
}

async function getSupplierConfig(env: Env, supplierID: string): Promise<SupplierConfigRow | null> {
    return await env.DB.prepare(
        "SELECT supplier_id,config_json,updated_at,updated_by_wallet FROM supplier_configs WHERE supplier_id=? LIMIT 1"
    ).bind(supplierID).first<SupplierConfigRow>();
}

async function upsertSupplierConfig(env: Env, supplierID: string, configJSON: string, updatedByWallet: string): Promise<void> {
    const updatedAt = new Date().toISOString();
    await env.DB.prepare(
        "INSERT INTO supplier_configs (supplier_id,config_json,updated_at,updated_by_wallet) VALUES (?, ?, ?, ?) ON CONFLICT(supplier_id) DO UPDATE SET config_json=excluded.config_json,updated_at=excluded.updated_at,updated_by_wallet=excluded.updated_by_wallet"
    ).bind(
        supplierID,
        configJSON,
        updatedAt,
        updatedByWallet,
    ).run();
}

async function listSupplierManagers(env: Env, supplierID: string): Promise<SupplierManagerRow[]> {
    const result = await env.DB.prepare(
        "SELECT supplier_id,manager_wallet,role,created_at FROM supplier_managers WHERE supplier_id=? ORDER BY created_at ASC"
    ).bind(supplierID).all<SupplierManagerRow>();
    return result.results || [];
}

async function addSupplierManager(env: Env, supplierID: string, managerWallet: string, role: string): Promise<void> {
    await env.DB.prepare(
        "INSERT INTO supplier_managers (supplier_id,manager_wallet,role,created_at) VALUES (?, ?, ?, ?)"
    ).bind(
        supplierID,
        managerWallet,
        role,
        new Date().toISOString(),
    ).run();
}

async function removeSupplierManager(env: Env, supplierID: string, managerWallet: string): Promise<boolean> {
    const result = await env.DB.prepare(
        "DELETE FROM supplier_managers WHERE supplier_id=? AND manager_wallet=?"
    ).bind(supplierID, managerWallet).run();
    return d1Changes(result) > 0;
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
                    "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Max-Age": "86400",
                },
            });
        }

        if (request.method === "GET" && path === "/api/v1/auth/nonce") {
            const nonce = randomNonce();
            const now = new Date();
            const expiresAt = new Date(now.getTime() + authNonceTTLSeconds(env) * 1000);
            await insertNonce(env, nonce, expiresAt.toISOString());
            return json(
                {
                    ok: true,
                    nonce,
                    issued_at: now.toISOString(),
                    expires_at: expiresAt.toISOString(),
                    domain: expectedDomain(env, url),
                    uri: expectedURI(env, url).toString(),
                    chain_ids: allowedChainIds(env),
                },
                200,
                { "Cache-Control": "no-store" }
            );
        }

        if (request.method === "POST" && path === "/api/v1/auth/verify") {
            const secret = (env.AUTH_JWT_SECRET || "").trim();
            if (!secret) {
                return json({ ok: false, error_code: "AUTH_NOT_CONFIGURED", error: "AUTH_JWT_SECRET is missing" }, 500, { "Cache-Control": "no-store" });
            }

            let body: unknown;
            try {
                body = await request.json();
            } catch {
                return json({ ok: false, error_code: "AUTH_BAD_REQUEST", error: "JSON body is required" }, 400, { "Cache-Control": "no-store" });
            }
            if (!body || typeof body !== "object") {
                return json({ ok: false, error_code: "AUTH_BAD_REQUEST", error: "Invalid request body" }, 400, { "Cache-Control": "no-store" });
            }

            const message = typeof (body as Record<string, unknown>).message === "string"
                ? ((body as Record<string, unknown>).message as string).trim()
                : "";
            const signature = typeof (body as Record<string, unknown>).signature === "string"
                ? ((body as Record<string, unknown>).signature as string).trim()
                : "";
            if (!message || !signature) {
                return json({ ok: false, error_code: "AUTH_BAD_REQUEST", error: "message and signature are required" }, 400, { "Cache-Control": "no-store" });
            }
            if (!isHexSignature(signature)) {
                return json({ ok: false, error_code: "AUTH_BAD_SIGNATURE", error: "signature must be 65-byte hex string" }, 400, { "Cache-Control": "no-store" });
            }

            const parsedSiwe = parseSiweMessage(message);
            if (!parsedSiwe) {
                return json({ ok: false, error_code: "SIWE_PARSE_FAILED", error: "Invalid SIWE message" }, 400, { "Cache-Control": "no-store" });
            }
            if (parsedSiwe.version !== "1") {
                return json({ ok: false, error_code: "SIWE_VERSION_UNSUPPORTED", error: "Only SIWE version 1 is supported" }, 401, { "Cache-Control": "no-store" });
            }

            const normalizedDomain = parsedSiwe.domain.trim().toLowerCase();
            if (normalizedDomain !== expectedDomain(env, url)) {
                return json({ ok: false, error_code: "SIWE_DOMAIN_MISMATCH", error: "SIWE domain does not match server domain" }, 401, { "Cache-Control": "no-store" });
            }

            let messageURI: URL;
            try {
                messageURI = new URL(parsedSiwe.uri);
            } catch {
                return json({ ok: false, error_code: "SIWE_URI_INVALID", error: "SIWE URI is invalid" }, 400, { "Cache-Control": "no-store" });
            }
            const expectedLoginURI = expectedURI(env, url);
            if (messageURI.origin !== expectedLoginURI.origin) {
                return json({ ok: false, error_code: "SIWE_URI_MISMATCH", error: "SIWE URI origin mismatch" }, 401, { "Cache-Control": "no-store" });
            }
            const configuredUri = (env.AUTH_URI || "").trim();
            if (configuredUri) {
                const normalizeHref = (href: string) => href.endsWith("/") ? href.slice(0, -1) : href;
                if (normalizeHref(messageURI.href) !== normalizeHref(expectedLoginURI.href)) {
                    return json({ ok: false, error_code: "SIWE_URI_MISMATCH", error: "SIWE URI does not match AUTH_URI" }, 401, { "Cache-Control": "no-store" });
                }
            }

            const chainIds = allowedChainIds(env);
            if (!chainIds.includes(parsedSiwe.chainId)) {
                return json({ ok: false, error_code: "SIWE_CHAIN_NOT_ALLOWED", error: "SIWE chainId is not allowed" }, 401, { "Cache-Control": "no-store" });
            }

            const nowSec = Math.floor(Date.now() / 1000);
            const issuedAtSec = toUnixSeconds(parsedSiwe.issuedAt);
            if (issuedAtSec === null) {
                return json({ ok: false, error_code: "SIWE_ISSUED_AT_INVALID", error: "SIWE issuedAt is invalid" }, 400, { "Cache-Control": "no-store" });
            }
            if (issuedAtSec > nowSec + 60) {
                return json({ ok: false, error_code: "SIWE_ISSUED_AT_IN_FUTURE", error: "SIWE issuedAt is too far in the future" }, 401, { "Cache-Control": "no-store" });
            }
            if (parsedSiwe.expirationTime) {
                const expirationSec = toUnixSeconds(parsedSiwe.expirationTime);
                if (expirationSec === null) {
                    return json({ ok: false, error_code: "SIWE_EXPIRATION_INVALID", error: "SIWE expirationTime is invalid" }, 400, { "Cache-Control": "no-store" });
                }
                if (expirationSec <= nowSec) {
                    return json({ ok: false, error_code: "SIWE_EXPIRED", error: "SIWE message is expired" }, 401, { "Cache-Control": "no-store" });
                }
            }

            const nonceRow = await getAuthNonce(env, parsedSiwe.nonce);
            if (!nonceRow) {
                return json({ ok: false, error_code: "NONCE_NOT_FOUND", error: "Nonce does not exist" }, 401, { "Cache-Control": "no-store" });
            }
            if (nonceRow.used_at) {
                return json({ ok: false, error_code: "NONCE_ALREADY_USED", error: "Nonce already used" }, 401, { "Cache-Control": "no-store" });
            }
            const nonceExpiry = toUnixSeconds(nonceRow.expires_at);
            if (nonceExpiry === null || nonceExpiry <= nowSec) {
                return json({ ok: false, error_code: "NONCE_EXPIRED", error: "Nonce is expired" }, 401, { "Cache-Control": "no-store" });
            }

            let normalizedAddress: string;
            try {
                normalizedAddress = getAddress(parsedSiwe.address);
            } catch {
                return json({ ok: false, error_code: "SIWE_ADDRESS_INVALID", error: "SIWE address is invalid" }, 400, { "Cache-Control": "no-store" });
            }

            let recoveredAddress: string;
            try {
                recoveredAddress = await recoverMessageAddress({
                    message,
                    signature,
                });
            } catch {
                return json({ ok: false, error_code: "SIWE_RECOVER_FAILED", error: "Unable to recover signer from signature" }, 401, { "Cache-Control": "no-store" });
            }
            if (!isAddressEqual(recoveredAddress, normalizedAddress)) {
                return json({ ok: false, error_code: "SIWE_SIGNATURE_MISMATCH", error: "Signature does not match SIWE address" }, 401, { "Cache-Control": "no-store" });
            }

            const consumed = await consumeNonce(env, parsedSiwe.nonce, new Date().toISOString());
            if (!consumed) {
                return json({ ok: false, error_code: "NONCE_ALREADY_USED", error: "Nonce already used" }, 401, { "Cache-Control": "no-store" });
            }

            const tokenTTL = authTokenTTLSeconds(env);
            const iat = nowSec;
            const exp = nowSec + tokenTTL;
            const payload: JwtPayload = {
                sub: normalizedAddress.toLowerCase(),
                chain_id: parsedSiwe.chainId,
                iat,
                exp,
                iss: "openmesh-market-api",
                aud: "openmesh-market-client",
            };
            const accessToken = await signJWT(payload, secret);

            return json(
                {
                    ok: true,
                    access_token: accessToken,
                    token_type: "Bearer",
                    expires_in: tokenTTL,
                    wallet: normalizedAddress,
                    chain_id: parsedSiwe.chainId,
                },
                200,
                { "Cache-Control": "no-store" }
            );
        }

        if (request.method === "GET" && path === "/api/v1/auth/me") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            return json(
                {
                    ok: true,
                    wallet: auth.wallet,
                    chain_id: auth.chainId,
                    token_expires_at: new Date(auth.exp * 1000).toISOString(),
                },
                200,
                { "Cache-Control": "no-store" }
            );
        }

        if (request.method === "POST" && path === "/api/v1/suppliers") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }

            let body: unknown;
            try {
                body = await request.json();
            } catch {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "JSON body is required" }, 400, { "Cache-Control": "no-store" });
            }
            if (!body || typeof body !== "object") {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "Invalid body" }, 400, { "Cache-Control": "no-store" });
            }

            const bodyObj = body as Record<string, unknown>;
            const name = sanitizeSupplierName(bodyObj.name);
            if (!name) {
                return json({ ok: false, error_code: "SUPPLIER_NAME_INVALID", error: "Supplier name is required (1-120 chars)" }, 400, { "Cache-Control": "no-store" });
            }
            const description = sanitizeSupplierDescription(bodyObj.description);

            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (identity) {
                return json({ ok: false, error_code: "SUPPLIER_ALREADY_EXISTS", error: "Wallet already bound to a supplier" }, 409, { "Cache-Control": "no-store" });
            }

            try {
                const supplier = await createSupplier(env, auth.wallet, name, description);
                return json(
                    {
                        ok: true,
                        role: "owner",
                        supplier,
                    },
                    201,
                    { "Cache-Control": "no-store" }
                );
            } catch (error) {
                const message = error instanceof Error ? error.message : String(error);
                if (message.includes("UNIQUE constraint failed")) {
                    return json({ ok: false, error_code: "SUPPLIER_ALREADY_EXISTS", error: "Wallet already bound to a supplier" }, 409, { "Cache-Control": "no-store" });
                }
                return json({ ok: false, error_code: "SUPPLIER_CREATE_FAILED", error: "Failed to create supplier" }, 500, { "Cache-Control": "no-store" });
            }
        }

        if (request.method === "GET" && path === "/api/v1/suppliers/me") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (!identity) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "No supplier bound to current wallet" }, 404, { "Cache-Control": "no-store" });
            }
            const managers = await listSupplierManagers(env, identity.supplier.id);
            return json(
                {
                    ok: true,
                    role: identity.role,
                    manager_role: identity.manager_role,
                    supplier: identity.supplier,
                    managers,
                },
                200,
                { "Cache-Control": "no-store" }
            );
        }

        if (request.method === "PATCH" && path === "/api/v1/suppliers/me") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (!identity) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "No supplier bound to current wallet" }, 404, { "Cache-Control": "no-store" });
            }
            if (identity.role !== "owner") {
                return json({ ok: false, error_code: "SUPPLIER_FORBIDDEN", error: "Only supplier owner can update supplier profile" }, 403, { "Cache-Control": "no-store" });
            }

            let body: unknown;
            try {
                body = await request.json();
            } catch {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "JSON body is required" }, 400, { "Cache-Control": "no-store" });
            }
            if (!body || typeof body !== "object") {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "Invalid body" }, 400, { "Cache-Control": "no-store" });
            }
            const bodyObj = body as Record<string, unknown>;

            const patch: { name?: string; description?: string; status?: SupplierStatus } = {};
            if ("name" in bodyObj) {
                const name = sanitizeSupplierName(bodyObj.name);
                if (!name) {
                    return json({ ok: false, error_code: "SUPPLIER_NAME_INVALID", error: "Supplier name must be 1-120 chars" }, 400, { "Cache-Control": "no-store" });
                }
                patch.name = name;
            }
            if ("description" in bodyObj) {
                patch.description = sanitizeSupplierDescription(bodyObj.description);
            }
            if ("status" in bodyObj) {
                const status = parseSupplierStatus(bodyObj.status);
                if (!status) {
                    return json({ ok: false, error_code: "SUPPLIER_STATUS_INVALID", error: "status must be active or disabled" }, 400, { "Cache-Control": "no-store" });
                }
                patch.status = status;
            }

            if (Object.keys(patch).length === 0) {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "No updatable fields provided" }, 400, { "Cache-Control": "no-store" });
            }

            await updateSupplier(env, identity.supplier.id, patch);
            const updated = await getSupplierById(env, identity.supplier.id);
            if (!updated) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "Supplier not found after update" }, 404, { "Cache-Control": "no-store" });
            }
            return json({ ok: true, role: "owner", supplier: updated }, 200, { "Cache-Control": "no-store" });
        }

        if (request.method === "GET" && path === "/api/v1/suppliers/me/config") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (!identity) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "No supplier bound to current wallet" }, 404, { "Cache-Control": "no-store" });
            }
            const configRow = await getSupplierConfig(env, identity.supplier.id);
            const config = configRow ? safeParseJSON<unknown>(configRow.config_json) : {};
            if (configRow && config === null) {
                return json({ ok: false, error_code: "SUPPLIER_CONFIG_INVALID", error: "Stored supplier config is invalid JSON" }, 500, { "Cache-Control": "no-store" });
            }
            return json(
                {
                    ok: true,
                    role: identity.role,
                    supplier_id: identity.supplier.id,
                    config: config ?? {},
                    updated_at: configRow?.updated_at || identity.supplier.updated_at,
                    updated_by_wallet: configRow?.updated_by_wallet || identity.supplier.owner_wallet,
                },
                200,
                { "Cache-Control": "no-store" }
            );
        }

        if (request.method === "PUT" && path === "/api/v1/suppliers/me/config") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (!identity) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "No supplier bound to current wallet" }, 404, { "Cache-Control": "no-store" });
            }

            let body: unknown;
            try {
                body = await request.json();
            } catch {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "JSON body is required" }, 400, { "Cache-Control": "no-store" });
            }
            if (!body || typeof body !== "object" || Array.isArray(body)) {
                return json({ ok: false, error_code: "SUPPLIER_CONFIG_INVALID", error: "config body must be a JSON object" }, 400, { "Cache-Control": "no-store" });
            }

            await upsertSupplierConfig(env, identity.supplier.id, JSON.stringify(body), auth.wallet);
            const configRow = await getSupplierConfig(env, identity.supplier.id);
            const config = configRow ? safeParseJSON<unknown>(configRow.config_json) : null;
            if (!configRow || config === null) {
                return json({ ok: false, error_code: "SUPPLIER_CONFIG_INVALID", error: "Failed to read updated supplier config" }, 500, { "Cache-Control": "no-store" });
            }

            return json(
                {
                    ok: true,
                    supplier_id: identity.supplier.id,
                    config,
                    updated_at: configRow.updated_at,
                    updated_by_wallet: configRow.updated_by_wallet,
                },
                200,
                { "Cache-Control": "no-store" }
            );
        }

        if (request.method === "POST" && path === "/api/v1/suppliers/me/managers") {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (!identity) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "No supplier bound to current wallet" }, 404, { "Cache-Control": "no-store" });
            }
            if (identity.role !== "owner") {
                return json({ ok: false, error_code: "SUPPLIER_FORBIDDEN", error: "Only supplier owner can manage managers" }, 403, { "Cache-Control": "no-store" });
            }

            let body: unknown;
            try {
                body = await request.json();
            } catch {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "JSON body is required" }, 400, { "Cache-Control": "no-store" });
            }
            if (!body || typeof body !== "object") {
                return json({ ok: false, error_code: "BAD_REQUEST", error: "Invalid body" }, 400, { "Cache-Control": "no-store" });
            }
            const bodyObj = body as Record<string, unknown>;
            const managerWallet = normalizeWallet(typeof bodyObj.wallet === "string" ? bodyObj.wallet : "");
            if (!managerWallet) {
                return json({ ok: false, error_code: "MANAGER_WALLET_INVALID", error: "wallet must be a valid EVM address" }, 400, { "Cache-Control": "no-store" });
            }
            if (managerWallet === identity.supplier.owner_wallet) {
                return json({ ok: false, error_code: "MANAGER_WALLET_INVALID", error: "manager wallet must differ from owner wallet" }, 400, { "Cache-Control": "no-store" });
            }
            const role = typeof bodyObj.role === "string" && bodyObj.role.trim() ? bodyObj.role.trim() : "manager";

            try {
                await addSupplierManager(env, identity.supplier.id, managerWallet, role);
            } catch (error) {
                const message = error instanceof Error ? error.message : String(error);
                if (message.includes("UNIQUE constraint failed")) {
                    return json({ ok: false, error_code: "MANAGER_ALREADY_EXISTS", error: "manager wallet is already assigned" }, 409, { "Cache-Control": "no-store" });
                }
                return json({ ok: false, error_code: "MANAGER_CREATE_FAILED", error: "Failed to create manager" }, 500, { "Cache-Control": "no-store" });
            }

            const managers = await listSupplierManagers(env, identity.supplier.id);
            return json({ ok: true, managers }, 200, { "Cache-Control": "no-store" });
        }

        const removeManagerMatch = path.match(/^\/api\/v1\/suppliers\/me\/managers\/([^\/]+)$/);
        if (request.method === "DELETE" && removeManagerMatch) {
            const auth = await requireAuth(request, env);
            if (!auth) {
                return json({ ok: false, error_code: "AUTH_REQUIRED", error: "Unauthorized" }, 401, { "Cache-Control": "no-store" });
            }
            const identity = await getSupplierIdentityByWallet(env, auth.wallet);
            if (!identity) {
                return json({ ok: false, error_code: "SUPPLIER_NOT_FOUND", error: "No supplier bound to current wallet" }, 404, { "Cache-Control": "no-store" });
            }
            if (identity.role !== "owner") {
                return json({ ok: false, error_code: "SUPPLIER_FORBIDDEN", error: "Only supplier owner can manage managers" }, 403, { "Cache-Control": "no-store" });
            }

            let managerWalletRaw = "";
            try {
                managerWalletRaw = decodeURIComponent(removeManagerMatch[1]);
            } catch {
                managerWalletRaw = removeManagerMatch[1];
            }
            const managerWallet = normalizeWallet(managerWalletRaw);
            if (!managerWallet) {
                return json({ ok: false, error_code: "MANAGER_WALLET_INVALID", error: "wallet must be a valid EVM address" }, 400, { "Cache-Control": "no-store" });
            }

            const removed = await removeSupplierManager(env, identity.supplier.id, managerWallet);
            if (!removed) {
                return json({ ok: false, error_code: "MANAGER_NOT_FOUND", error: "manager wallet not found" }, 404, { "Cache-Control": "no-store" });
            }
            const managers = await listSupplierManagers(env, identity.supplier.id);
            return json({ ok: true, managers }, 200, { "Cache-Control": "no-store" });
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
                        "Cache-Control": "public, max-age=0, must-revalidate",
                    },
                });
            }
            return json(
                { ok: true, market_version: mv, updated_at, providers },
                200,
                {
                    "ETag": etag,
                    "Cache-Control": "public, max-age=0, must-revalidate",
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
                "/api/v1/auth/nonce": "Create one-time nonce for SIWE sign-in",
                "/api/v1/auth/verify": "Verify SIWE signature and issue JWT",
                "/api/v1/auth/me": "Protected endpoint for current auth context",
                "/api/v1/suppliers": "Create supplier (owner wallet)",
                "/api/v1/suppliers/me": "Get or update current supplier profile",
                "/api/v1/suppliers/me/config": "Get or update current supplier config",
                "/api/v1/suppliers/me/managers": "Add manager wallet (owner only)",
                "/api/v1/suppliers/me/managers/:wallet": "Remove manager wallet (owner only)",
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
