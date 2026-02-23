import { describe, it, expect } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import worker from "../src/index";

type ProviderRow = {
    id: string;
    name: string;
    description: string;
    tags_json: string;
    author: string;
    updated_at: string;
    price_per_gb_usd: number | null;
    visibility: "public" | "private";
    status: "active" | "disabled";
    config_json: string;
    routing_rules_json: string | null;
};

type AuthNonceRow = {
    nonce: string;
    expires_at: string;
    used_at: string | null;
};

type SupplierRow = {
    id: string;
    name: string;
    description: string;
    owner_wallet: string;
    status: "active" | "disabled";
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

function normalizeSQL(input: string): string {
    return input.toLowerCase().replace(/\s+/g, " ").trim();
}

class FakeD1PreparedStatement {
    private sql: string;
    private db: FakeD1Database;
    private bound: unknown[] = [];

    constructor(sql: string, db: FakeD1Database) {
        this.sql = normalizeSQL(sql);
        this.db = db;
    }

    bind(...values: unknown[]) {
        this.bound = values;
        return this;
    }

    async first<T = unknown>(): Promise<T | null> {
        if (this.sql.includes("from providers where id=?")) {
            const id = String(this.bound[0] ?? "");
            return (this.db.providers.find(r => r.id === id) as T | undefined) ?? null;
        }

        if (this.sql.includes("from auth_nonces where nonce=?")) {
            const nonce = String(this.bound[0] ?? "");
            return (this.db.nonces.get(nonce) as T | undefined) ?? null;
        }

        if (this.sql.includes("from suppliers where owner_wallet=?")) {
            const wallet = String(this.bound[0] ?? "");
            const row = Array.from(this.db.suppliers.values()).find(s => s.owner_wallet === wallet);
            return (row as T | undefined) ?? null;
        }

        if (this.sql.includes("from suppliers where id=?")) {
            const supplierID = String(this.bound[0] ?? "");
            return (this.db.suppliers.get(supplierID) as T | undefined) ?? null;
        }

        if (this.sql.includes("from supplier_configs where supplier_id=?")) {
            const supplierID = String(this.bound[0] ?? "");
            return (this.db.supplierConfigs.get(supplierID) as T | undefined) ?? null;
        }

        if (this.sql.includes("from supplier_managers m inner join suppliers s")) {
            const managerWallet = String(this.bound[0] ?? "");
            const manager = this.db.supplierManagers.get(managerWallet);
            if (!manager) return null;
            const supplier = this.db.suppliers.get(manager.supplier_id);
            if (!supplier) return null;
            return ({
                ...supplier,
                manager_role: manager.role,
            } as T);
        }

        return null;
    }

    async all<T = unknown>(): Promise<{ results: T[] }> {
        if (this.sql.includes("from supplier_managers where supplier_id=?")) {
            const supplierID = String(this.bound[0] ?? "");
            const managers = Array.from(this.db.supplierManagers.values())
                .filter(m => m.supplier_id === supplierID)
                .sort((a, b) => a.created_at.localeCompare(b.created_at));
            return { results: managers as unknown as T[] };
        }

        const results = this.sql.includes("where id=?")
            ? (this.db.providers.filter(r => r.id === String(this.bound[0] ?? "")) as unknown as T[])
            : (this.db.providers.filter(r => r.visibility === "public" && r.status === "active") as unknown as T[]);
        return { results };
    }

    async run(): Promise<unknown> {
        if (this.sql.includes("insert into auth_nonces")) {
            const nonce = String(this.bound[0] ?? "");
            const expiresAt = String(this.bound[1] ?? "");
            this.db.nonces.set(nonce, {
                nonce,
                expires_at: expiresAt,
                used_at: null,
            });
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("update auth_nonces set used_at=?")) {
            const usedAt = String(this.bound[0] ?? "");
            const nonce = String(this.bound[1] ?? "");
            const row = this.db.nonces.get(nonce);
            if (!row || row.used_at) {
                return { success: true, meta: { changes: 0 } };
            }
            row.used_at = usedAt;
            this.db.nonces.set(nonce, row);
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("insert into suppliers (")) {
            const row: SupplierRow = {
                id: String(this.bound[0] ?? ""),
                name: String(this.bound[1] ?? ""),
                description: String(this.bound[2] ?? ""),
                owner_wallet: String(this.bound[3] ?? ""),
                status: String(this.bound[4] ?? "active") as "active" | "disabled",
                created_at: String(this.bound[5] ?? ""),
                updated_at: String(this.bound[6] ?? ""),
            };
            if (this.db.suppliers.has(row.id) || Array.from(this.db.suppliers.values()).some(s => s.owner_wallet === row.owner_wallet)) {
                throw new Error("UNIQUE constraint failed: suppliers.owner_wallet");
            }
            this.db.suppliers.set(row.id, row);
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("update suppliers set ")) {
            const supplierID = String(this.bound[this.bound.length - 1] ?? "");
            const existing = this.db.suppliers.get(supplierID);
            if (!existing) return { success: true, meta: { changes: 0 } };

            let idx = 0;
            const next = { ...existing };
            if (this.sql.includes("name=?")) {
                next.name = String(this.bound[idx] ?? existing.name);
                idx += 1;
            }
            if (this.sql.includes("description=?")) {
                next.description = String(this.bound[idx] ?? existing.description);
                idx += 1;
            }
            if (this.sql.includes("status=?")) {
                next.status = String(this.bound[idx] ?? existing.status) as "active" | "disabled";
                idx += 1;
            }
            if (this.sql.includes("updated_at=?")) {
                next.updated_at = String(this.bound[idx] ?? existing.updated_at);
            }
            this.db.suppliers.set(supplierID, next);
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("insert into supplier_configs")) {
            const row: SupplierConfigRow = {
                supplier_id: String(this.bound[0] ?? ""),
                config_json: String(this.bound[1] ?? "{}"),
                updated_at: String(this.bound[2] ?? ""),
                updated_by_wallet: String(this.bound[3] ?? ""),
            };
            this.db.supplierConfigs.set(row.supplier_id, row);
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("insert into supplier_managers")) {
            const row: SupplierManagerRow = {
                supplier_id: String(this.bound[0] ?? ""),
                manager_wallet: String(this.bound[1] ?? ""),
                role: String(this.bound[2] ?? "manager"),
                created_at: String(this.bound[3] ?? ""),
            };
            if (this.db.supplierManagers.has(row.manager_wallet)) {
                throw new Error("UNIQUE constraint failed: supplier_managers.manager_wallet");
            }
            this.db.supplierManagers.set(row.manager_wallet, row);
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("delete from supplier_managers where supplier_id=? and manager_wallet=?")) {
            const supplierID = String(this.bound[0] ?? "");
            const managerWallet = String(this.bound[1] ?? "");
            const row = this.db.supplierManagers.get(managerWallet);
            if (!row || row.supplier_id !== supplierID) {
                return { success: true, meta: { changes: 0 } };
            }
            this.db.supplierManagers.delete(managerWallet);
            return { success: true, meta: { changes: 1 } };
        }

        return { success: true, meta: { changes: 0 } };
    }
}

class FakeD1Database {
    providers: ProviderRow[];
    nonces = new Map<string, AuthNonceRow>();
    suppliers = new Map<string, SupplierRow>();
    supplierConfigs = new Map<string, SupplierConfigRow>();
    supplierManagers = new Map<string, SupplierManagerRow>();

    constructor(rows: ProviderRow[]) {
        this.providers = rows;
    }

    prepare(query: string) {
        return new FakeD1PreparedStatement(query, this);
    }

    forceExpireNonce(nonce: string) {
        const row = this.nonces.get(nonce);
        if (!row) return;
        row.expires_at = "2000-01-01T00:00:00.000Z";
        this.nonces.set(nonce, row);
    }
}

const officialOnlineConfig = {
    dns: {
        final: "google-dns",
        reverse_mapping: true,
        strategy: "ipv4_only",
        servers: [
            { detour: "proxy", server: "dns.google", tag: "google-dns", type: "https" },
            { detour: "direct", server: "223.5.5.5", tag: "local-dns", type: "udp" },
        ],
    },
    inbounds: [{ type: "tun", tag: "tun-in" }],
    outbounds: [{ type: "direct", tag: "direct" }],
    route: {
        rule_set: [
            {
                type: "remote",
                tag: "geoip-cn",
                format: "binary",
                url: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
                download_detour: "proxy",
                update_interval: "1d",
            },
            {
                type: "remote",
                tag: "geosite-geolocation-cn",
                format: "binary",
                url: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs",
                download_detour: "proxy",
                update_interval: "1d",
            },
        ],
    },
};

const seedRows: ProviderRow[] = [
    {
        id: "com.meshnetprotocol.profile",
        name: "官方供应商在线版本",
        description: "用于对照测试",
        tags_json: JSON.stringify(["Official", "Online"]),
        author: "OpenMesh Team",
        updated_at: "2026-02-08T00:00:00Z",
        price_per_gb_usd: 0.0,
        visibility: "public",
        status: "active",
        config_json: JSON.stringify(officialOnlineConfig),
        routing_rules_json: JSON.stringify({ proxy: { domain_suffix: ["openai.com"] } }),
    },
];

const walletA = privateKeyToAccount("0x59c6995e998f97a5a0044966f094538f5b4f3077ef8d9dbf8ec5d8bb2fef8f66");
const walletB = privateKeyToAccount("0x8b3a350cf5c34c9194ca14f9d5d8f95f1f4f455f322d8ab3f67c9a088f69d8d4");
const walletC = privateKeyToAccount("0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc3e52d81b6af7f2d34a29f3a0");

function createEnv() {
    return {
        MARKET_VERSION: "1",
        MARKET_UPDATED_AT: "2026-02-08T00:00:00Z",
        AUTH_JWT_SECRET: "unit-test-secret",
        AUTH_NONCE_TTL_SECONDS: "300",
        AUTH_TOKEN_TTL_SECONDS: "900",
        AUTH_ALLOWED_CHAIN_IDS: "1,11155111",
        AUTH_DOMAIN: "example.com",
        AUTH_URI: "https://example.com",
        CORS_ALLOWED_ORIGINS: "https://allowed.example.com",
        AUTH_NONCE_RATE_LIMIT_PER_MIN: "60",
        AUTH_VERIFY_RATE_LIMIT_PER_MIN: "30",
        SUPPLIER_WRITE_RATE_LIMIT_PER_MIN: "120",
        SECURITY_AUDIT_ENABLED: "true",
        DB: new FakeD1Database(seedRows),
    };
}

async function fetchFromWorker(path: string, env: ReturnType<typeof createEnv>, init?: RequestInit) {
    const url = `https://example.com${path}`;
    return worker.fetch(new Request(url, init), env as never);
}

function buildSiweMessage(args: {
    domain: string;
    address: string;
    uri: string;
    chainId: number;
    nonce: string;
    issuedAt: string;
    expirationTime: string;
}) {
    return `${args.domain} wants you to sign in with your Ethereum account:
${args.address}

Sign in to OpenMesh Market.

URI: ${args.uri}
Version: 1
Chain ID: ${args.chainId}
Nonce: ${args.nonce}
Issued At: ${args.issuedAt}
Expiration Time: ${args.expirationTime}`;
}

async function signInAndGetToken(
    env: ReturnType<typeof createEnv>,
    account: ReturnType<typeof privateKeyToAccount>,
): Promise<string> {
    const nonceResp = await fetchFromWorker("/api/v1/auth/nonce", env);
    expect(nonceResp.status).toBe(200);
    const nonceData: any = await nonceResp.json();
    const now = new Date();
    const expiration = new Date(now.getTime() + 5 * 60 * 1000);
    const message = buildSiweMessage({
        domain: nonceData.domain,
        address: account.address,
        uri: nonceData.uri,
        chainId: 1,
        nonce: nonceData.nonce,
        issuedAt: now.toISOString(),
        expirationTime: expiration.toISOString(),
    });
    const signature = await account.signMessage({ message });
    const verifyResp = await fetchFromWorker("/api/v1/auth/verify", env, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message, signature }),
    });
    expect(verifyResp.status).toBe(200);
    const verifyData: any = await verifyResp.json();
    return verifyData.access_token as string;
}

describe("OpenMesh Market API - Worker", () => {
    it("supports CORS OPTIONS preflight", async () => {
        const env = createEnv();
        const response = await fetchFromWorker("/api/v1/providers", env, {
            method: "OPTIONS",
            headers: {
                Origin: "https://allowed.example.com",
            },
        });
        expect(response.status).toBe(204);
        expect(response.headers.get("Access-Control-Allow-Origin")).toBe("https://allowed.example.com");
        expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
    });

    it("rejects CORS request from disallowed origin", async () => {
        const env = createEnv();
        const response = await fetchFromWorker("/api/v1/providers", env, {
            headers: {
                Origin: "https://forbidden.example.com",
            },
        });
        expect(response.status).toBe(403);
        const data: any = await response.json();
        expect(data.error_code).toBe("CORS_ORIGIN_FORBIDDEN");
    });

    it("applies nonce rate limit by client ip", async () => {
        const env = createEnv();
        env.AUTH_NONCE_RATE_LIMIT_PER_MIN = "1";
        const headers = { "CF-Connecting-IP": "203.0.113.77" };

        const first = await fetchFromWorker("/api/v1/auth/nonce", env, { headers });
        expect(first.status).toBe(200);

        const second = await fetchFromWorker("/api/v1/auth/nonce", env, { headers });
        expect(second.status).toBe(429);
        const data: any = await second.json();
        expect(data.error_code).toBe("RATE_LIMITED");
    });

    it("returns providers list", async () => {
        const env = createEnv();
        const response = await fetchFromWorker("/api/v1/providers", env);
        expect(response.status).toBe(200);
        const data: any = await response.json();
        expect(data.ok).toBe(true);
        expect(Array.isArray(data.data)).toBe(true);
    });

    it("returns market manifest with stable ETag", async () => {
        const env = createEnv();
        const r1 = await fetchFromWorker("/api/v1/market/manifest", env);
        expect(r1.status).toBe(200);
        const etag = r1.headers.get("ETag");
        expect(etag).toBeTruthy();

        const r2 = await fetchFromWorker("/api/v1/market/manifest", env, { headers: { "If-None-Match": etag! } });
        expect(r2.status).toBe(304);
    });

    it("returns provider detail + package files", async () => {
        const env = createEnv();
        const response = await fetchFromWorker("/api/v1/providers/com.meshnetprotocol.profile", env);
        expect(response.status).toBe(200);
        const data: any = await response.json();
        expect(data.ok).toBe(true);
        expect(data.provider.id).toBe("com.meshnetprotocol.profile");
        expect(data.package).toHaveProperty("package_hash");
        expect(Array.isArray(data.package.files)).toBe(true);
        expect(data.package.files.some((f: any) => f.type === "config")).toBe(true);
        expect(data.package.files.some((f: any) => f.type === "rule_set")).toBe(true);
    });

    it("returns provider config with remote rule-set URLs", async () => {
        const env = createEnv();
        const response = await fetchFromWorker("/api/v1/config/com.meshnetprotocol.profile", env);
        expect(response.status).toBe(200);
        const data: any = await response.json();
        expect(data).toHaveProperty("route");
        const rs = data?.route?.rule_set;
        expect(Array.isArray(rs)).toBe(true);
        expect(rs.some((x: any) => typeof x?.url === "string" && x.url.startsWith("https://"))).toBe(true);
    });

    it("returns provider routing rules", async () => {
        const env = createEnv();
        const response = await fetchFromWorker("/api/v1/rules/com.meshnetprotocol.profile/routing_rules.json", env);
        expect(response.status).toBe(200);
        const data = await response.json();
        expect(data).toHaveProperty("proxy");
    });

    it("issues JWT from valid SIWE message and accesses protected endpoint", async () => {
        const env = createEnv();
        const nonceResp = await fetchFromWorker("/api/v1/auth/nonce", env);
        expect(nonceResp.status).toBe(200);
        const nonceData: any = await nonceResp.json();
        expect(nonceData.ok).toBe(true);
        expect(typeof nonceData.nonce).toBe("string");

        const now = new Date();
        const expiration = new Date(now.getTime() + 5 * 60 * 1000);
        const message = buildSiweMessage({
            domain: nonceData.domain,
            address: walletA.address,
            uri: nonceData.uri,
            chainId: 1,
            nonce: nonceData.nonce,
            issuedAt: now.toISOString(),
            expirationTime: expiration.toISOString(),
        });
        const signature = await walletA.signMessage({ message });

        const verifyResp = await fetchFromWorker("/api/v1/auth/verify", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message, signature }),
        });
        expect(verifyResp.status).toBe(200);
        const verifyData: any = await verifyResp.json();
        expect(verifyData.ok).toBe(true);
        expect(typeof verifyData.access_token).toBe("string");
        expect(verifyData.wallet).toBe(walletA.address);

        const meResp = await fetchFromWorker("/api/v1/auth/me", env, {
            headers: { Authorization: `Bearer ${verifyData.access_token}` },
        });
        expect(meResp.status).toBe(200);
        const meData: any = await meResp.json();
        expect(meData.ok).toBe(true);
        expect(meData.wallet).toBe(walletA.address.toLowerCase());
    });

    it("rejects SIWE verify replay with same nonce", async () => {
        const env = createEnv();
        const nonceResp = await fetchFromWorker("/api/v1/auth/nonce", env);
        const nonceData: any = await nonceResp.json();
        const now = new Date();
        const expiration = new Date(now.getTime() + 5 * 60 * 1000);
        const message = buildSiweMessage({
            domain: nonceData.domain,
            address: walletA.address,
            uri: nonceData.uri,
            chainId: 1,
            nonce: nonceData.nonce,
            issuedAt: now.toISOString(),
            expirationTime: expiration.toISOString(),
        });
        const signature = await walletA.signMessage({ message });

        const first = await fetchFromWorker("/api/v1/auth/verify", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message, signature }),
        });
        expect(first.status).toBe(200);

        const second = await fetchFromWorker("/api/v1/auth/verify", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message, signature }),
        });
        expect(second.status).toBe(401);
        const secondData: any = await second.json();
        expect(secondData.error_code).toBe("NONCE_ALREADY_USED");
    });

    it("rejects SIWE verify when signature does not match message address", async () => {
        const env = createEnv();
        const nonceResp = await fetchFromWorker("/api/v1/auth/nonce", env);
        const nonceData: any = await nonceResp.json();
        const now = new Date();
        const expiration = new Date(now.getTime() + 5 * 60 * 1000);
        const message = buildSiweMessage({
            domain: nonceData.domain,
            address: walletA.address,
            uri: nonceData.uri,
            chainId: 1,
            nonce: nonceData.nonce,
            issuedAt: now.toISOString(),
            expirationTime: expiration.toISOString(),
        });
        const badSignature = await walletB.signMessage({ message });

        const verifyResp = await fetchFromWorker("/api/v1/auth/verify", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message, signature: badSignature }),
        });
        expect(verifyResp.status).toBe(401);
        const verifyData: any = await verifyResp.json();
        expect(verifyData.error_code).toBe("SIWE_SIGNATURE_MISMATCH");
    });

    it("rejects SIWE verify when nonce is expired", async () => {
        const env = createEnv();
        const nonceResp = await fetchFromWorker("/api/v1/auth/nonce", env);
        const nonceData: any = await nonceResp.json();
        env.DB.forceExpireNonce(nonceData.nonce);

        const now = new Date();
        const expiration = new Date(now.getTime() + 5 * 60 * 1000);
        const message = buildSiweMessage({
            domain: nonceData.domain,
            address: walletA.address,
            uri: nonceData.uri,
            chainId: 1,
            nonce: nonceData.nonce,
            issuedAt: now.toISOString(),
            expirationTime: expiration.toISOString(),
        });
        const signature = await walletA.signMessage({ message });

        const verifyResp = await fetchFromWorker("/api/v1/auth/verify", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ message, signature }),
        });
        expect(verifyResp.status).toBe(401);
        const verifyData: any = await verifyResp.json();
        expect(verifyData.error_code).toBe("NONCE_EXPIRED");
    });

    it("rejects protected endpoint without bearer token", async () => {
        const env = createEnv();
        const meResp = await fetchFromWorker("/api/v1/auth/me", env);
        expect(meResp.status).toBe(401);
        const meData: any = await meResp.json();
        expect(meData.error_code).toBe("AUTH_REQUIRED");
    });

    it("supports supplier create and owner self-management flow", async () => {
        const env = createEnv();
        const token = await signInAndGetToken(env, walletA);

        const createResp = await fetchFromWorker("/api/v1/suppliers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Alpha Supplier", description: "alpha" }),
        });
        expect(createResp.status).toBe(201);
        const createData: any = await createResp.json();
        expect(createData.ok).toBe(true);
        expect(createData.role).toBe("owner");

        const meResp = await fetchFromWorker("/api/v1/suppliers/me", env, {
            headers: { Authorization: `Bearer ${token}` },
        });
        expect(meResp.status).toBe(200);
        const meData: any = await meResp.json();
        expect(meData.role).toBe("owner");
        expect(meData.supplier.name).toBe("Alpha Supplier");

        const patchResp = await fetchFromWorker("/api/v1/suppliers/me", env, {
            method: "PATCH",
            headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Alpha Supplier Updated", status: "active" }),
        });
        expect(patchResp.status).toBe(200);
        const patchData: any = await patchResp.json();
        expect(patchData.supplier.name).toBe("Alpha Supplier Updated");

        const putConfigResp = await fetchFromWorker("/api/v1/suppliers/me/config", env, {
            method: "PUT",
            headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                webhook_url: "https://example.com/hook",
                settlement_wallet: walletA.address,
            }),
        });
        expect(putConfigResp.status).toBe(200);
        const putConfigData: any = await putConfigResp.json();
        expect(putConfigData.config.webhook_url).toBe("https://example.com/hook");

        const getConfigResp = await fetchFromWorker("/api/v1/suppliers/me/config", env, {
            headers: { Authorization: `Bearer ${token}` },
        });
        expect(getConfigResp.status).toBe(200);
        const getConfigData: any = await getConfigResp.json();
        expect(getConfigData.config.webhook_url).toBe("https://example.com/hook");
    });

    it("rejects duplicate supplier creation by the same wallet", async () => {
        const env = createEnv();
        const token = await signInAndGetToken(env, walletA);
        await fetchFromWorker("/api/v1/suppliers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Alpha Supplier" }),
        });

        const secondCreateResp = await fetchFromWorker("/api/v1/suppliers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Alpha Supplier 2" }),
        });
        expect(secondCreateResp.status).toBe(409);
        const secondCreateData: any = await secondCreateResp.json();
        expect(secondCreateData.error_code).toBe("SUPPLIER_ALREADY_EXISTS");
    });

    it("allows owner to manage managers and allows manager to update config only", async () => {
        const env = createEnv();
        const ownerToken = await signInAndGetToken(env, walletA);
        const managerToken = await signInAndGetToken(env, walletB);

        const createResp = await fetchFromWorker("/api/v1/suppliers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${ownerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Beta Supplier" }),
        });
        expect(createResp.status).toBe(201);

        const addManagerResp = await fetchFromWorker("/api/v1/suppliers/me/managers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${ownerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ wallet: walletB.address, role: "manager" }),
        });
        expect(addManagerResp.status).toBe(200);
        const addManagerData: any = await addManagerResp.json();
        expect(addManagerData.managers.some((m: any) => m.manager_wallet === walletB.address.toLowerCase())).toBe(true);

        const managerMeResp = await fetchFromWorker("/api/v1/suppliers/me", env, {
            headers: { Authorization: `Bearer ${managerToken}` },
        });
        expect(managerMeResp.status).toBe(200);
        const managerMeData: any = await managerMeResp.json();
        expect(managerMeData.role).toBe("manager");

        const managerConfigResp = await fetchFromWorker("/api/v1/suppliers/me/config", env, {
            method: "PUT",
            headers: {
                Authorization: `Bearer ${managerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ callback_secret: "secret-123" }),
        });
        expect(managerConfigResp.status).toBe(200);
        const managerConfigData: any = await managerConfigResp.json();
        expect(managerConfigData.updated_by_wallet).toBe(walletB.address.toLowerCase());

        const managerPatchResp = await fetchFromWorker("/api/v1/suppliers/me", env, {
            method: "PATCH",
            headers: {
                Authorization: `Bearer ${managerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Should Fail" }),
        });
        expect(managerPatchResp.status).toBe(403);

        const managerAddOtherManagerResp = await fetchFromWorker("/api/v1/suppliers/me/managers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${managerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ wallet: walletC.address }),
        });
        expect(managerAddOtherManagerResp.status).toBe(403);
    });

    it("removes manager and denies supplier access afterwards", async () => {
        const env = createEnv();
        const ownerToken = await signInAndGetToken(env, walletA);
        const managerToken = await signInAndGetToken(env, walletB);

        await fetchFromWorker("/api/v1/suppliers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${ownerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ name: "Gamma Supplier" }),
        });
        await fetchFromWorker("/api/v1/suppliers/me/managers", env, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${ownerToken}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ wallet: walletB.address }),
        });

        const removeResp = await fetchFromWorker(`/api/v1/suppliers/me/managers/${encodeURIComponent(walletB.address)}`, env, {
            method: "DELETE",
            headers: { Authorization: `Bearer ${ownerToken}` },
        });
        expect(removeResp.status).toBe(200);

        const managerMeResp = await fetchFromWorker("/api/v1/suppliers/me", env, {
            headers: { Authorization: `Bearer ${managerToken}` },
        });
        expect(managerMeResp.status).toBe(404);
    });

    it("returns supplier not found for authenticated wallet without supplier binding", async () => {
        const env = createEnv();
        const token = await signInAndGetToken(env, walletC);
        const meResp = await fetchFromWorker("/api/v1/suppliers/me", env, {
            headers: { Authorization: `Bearer ${token}` },
        });
        expect(meResp.status).toBe(404);
        const meData: any = await meResp.json();
        expect(meData.error_code).toBe("SUPPLIER_NOT_FOUND");
    });
});
