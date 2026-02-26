import { describe, expect, it } from "vitest";
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

type SupplierIdRow = {
    supplier_id: string;
    supplier_type: "commercial" | "private";
    owner_wallet: string;
    chain_id: number | null;
    status: "reserved" | "active" | "expired";
    profile_url: string | null;
    last_verified_tx: string | null;
    created_at: string;
    updated_at: string;
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
            return (this.db.providers.find(row => row.id === id) as T | undefined) ?? null;
        }

        if (this.sql.includes("from supplier_ids where supplier_id=?")) {
            const supplierId = String(this.bound[0] ?? "");
            return (this.db.supplierIds.get(supplierId) as T | undefined) ?? null;
        }

        return null;
    }

    async all<T = unknown>(): Promise<{ results: T[] }> {
        if (this.sql.includes("from providers where visibility='public' and status='active'")) {
            const rows = this.db.providers
                .filter(row => row.visibility === "public" && row.status === "active")
                .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
            return { results: rows as unknown as T[] };
        }

        return { results: [] };
    }

    async run(): Promise<unknown> {
        if (this.sql.includes("insert into supplier_ids")) {
            const row: SupplierIdRow = {
                supplier_id: String(this.bound[0] ?? ""),
                supplier_type: String(this.bound[1] ?? "commercial") as "commercial" | "private",
                owner_wallet: String(this.bound[2] ?? ""),
                chain_id: this.bound[3] === null || this.bound[3] === undefined ? null : Number(this.bound[3]),
                status: String(this.bound[4] ?? "reserved") as "reserved" | "active" | "expired",
                profile_url: this.bound[5] === null || this.bound[5] === undefined ? null : String(this.bound[5]),
                last_verified_tx: this.bound[6] === null || this.bound[6] === undefined ? null : String(this.bound[6]),
                created_at: String(this.bound[7] ?? ""),
                updated_at: String(this.bound[8] ?? ""),
            };

            if (this.db.supplierIds.has(row.supplier_id)) {
                throw new Error("UNIQUE constraint failed: supplier_ids.supplier_id");
            }
            this.db.supplierIds.set(row.supplier_id, row);
            return { success: true, meta: { changes: 1 } };
        }

        if (this.sql.includes("update supplier_ids set status='active'")) {
            const chainId = Number(this.bound[0]);
            const profileUrl = this.bound[1] === null || this.bound[1] === undefined ? null : String(this.bound[1]);
            const txHash = String(this.bound[2] ?? "");
            const updatedAt = String(this.bound[3] ?? "");
            const supplierId = String(this.bound[4] ?? "");
            const ownerWallet = String(this.bound[5] ?? "");

            const current = this.db.supplierIds.get(supplierId);
            if (!current || current.supplier_type !== "commercial" || current.owner_wallet !== ownerWallet) {
                return { success: true, meta: { changes: 0 } };
            }

            this.db.supplierIds.set(supplierId, {
                ...current,
                status: "active",
                chain_id: chainId,
                profile_url: profileUrl,
                last_verified_tx: txHash,
                updated_at: updatedAt,
            });
            return { success: true, meta: { changes: 1 } };
        }

        return { success: true, meta: { changes: 0 } };
    }
}

class FakeD1Database {
    providers: ProviderRow[];
    supplierIds = new Map<string, SupplierIdRow>();

    constructor(rows: ProviderRow[]) {
        this.providers = rows;
    }

    prepare(query: string) {
        return new FakeD1PreparedStatement(query, this);
    }
}

const baseConfig = {
    inbounds: [{ type: "tun", tag: "tun-in", stack: "gvisor" }],
    outbounds: [{ type: "shadowsocks", tag: "ss-main", server_port: 443 }],
    route: {
        rule_set: [
            {
                type: "remote",
                tag: "geoip-cn",
                url: "https://example.com/rules/geoip-cn.srs",
            },
        ],
    },
    metadata: {
        market_url: "https://market.openmesh.network/api/v1/providers",
    },
};

const providerRows: ProviderRow[] = [
    {
        id: "com.meshnetprotocol.online",
        name: "OpenMesh Official Online",
        description: "Official online provider",
        tags_json: JSON.stringify(["official", "online"]),
        author: "OpenMesh Team",
        updated_at: "2026-02-20T00:00:00.000Z",
        price_per_gb_usd: 0.22,
        visibility: "public",
        status: "active",
        config_json: JSON.stringify(baseConfig),
        routing_rules_json: JSON.stringify({ version: 1, rules: [] }),
    },
    {
        id: "com.meshnetprotocol.private",
        name: "Private Provider",
        description: "Should not show in public list",
        tags_json: JSON.stringify(["private"]),
        author: "OpenMesh Team",
        updated_at: "2026-02-21T00:00:00.000Z",
        price_per_gb_usd: 0.5,
        visibility: "private",
        status: "active",
        config_json: JSON.stringify(baseConfig),
        routing_rules_json: null,
    },
];

function makeEnv() {
    return {
        DB: new FakeD1Database(providerRows),
        MARKET_VERSION: "9",
        MARKET_UPDATED_AT: "2026-02-21T00:00:00.000Z",
        DEFAULT_CHAIN_ENV: "sepolia",
        SUPPLIER_REGISTRY_ADDRESS_MAINNET: "0x1111111111111111111111111111111111111111",
        SUPPLIER_REGISTRY_ADDRESS_SEPOLIA: "0x2222222222222222222222222222222222222222",
        PAYMENT_HUB_ADDRESS_MAINNET: "0x3333333333333333333333333333333333333333",
        PAYMENT_HUB_ADDRESS_SEPOLIA: "0x4444444444444444444444444444444444444444",
        USDC_ADDRESS_MAINNET: "0x5555555555555555555555555555555555555555",
        USDC_ADDRESS_SEPOLIA: "0x6666666666666666666666666666666666666666",
    } as any;
}

async function fetchFromWorker(path: string, env: any, init?: RequestInit) {
    const req = new Request(`https://example.com${path}`, init);
    return await worker.fetch(req, env);
}

function declarationMessage(action: "commercial_reserve" | "private_register" | "commercial_confirm", supplierId: string, supplierType: "commercial" | "private", ownerWallet: string): string {
    return [
        "OpenMesh Supplier ID Declaration",
        `action:${action}`,
        `supplier_id:${supplierId}`,
        `supplier_type:${supplierType}`,
        `owner_wallet:${ownerWallet}`,
    ].join("\n");
}

async function signDeclaration(account: ReturnType<typeof privateKeyToAccount>, action: "commercial_reserve" | "private_register" | "commercial_confirm", supplierId: string, supplierType: "commercial" | "private") {
    const message = declarationMessage(action, supplierId, supplierType, account.address.toLowerCase());
    const signature = await account.signMessage({ message });
    return { message, signature };
}

describe("market-api v2 supplier-id + providers", () => {
    it("returns only public active providers", async () => {
        const response = await fetchFromWorker("/api/v1/providers", makeEnv());
        expect(response.status).toBe(200);
        const data: any = await response.json();
        expect(data.ok).toBe(true);
        expect(data.data.length).toBe(1);
        expect(data.data[0].id).toBe("com.meshnetprotocol.online");
    });

    it("returns 404 for removed auth endpoints", async () => {
        const response = await fetchFromWorker("/api/v1/auth/nonce", makeEnv());
        expect(response.status).toBe(404);
    });

    it("returns v2 network configuration", async () => {
        const response = await fetchFromWorker("/api/v2/networks", makeEnv());
        expect(response.status).toBe(200);
        const data: any = await response.json();
        expect(data.ok).toBe(true);
        expect(data.default_chain).toBe("sepolia");
        expect(data.chains.base_mainnet.chain_id).toBe(8453);
        expect(data.chains.base_sepolia.chain_id).toBe(84532);
    });

    it("reserves a commercial supplier id with wallet signature", async () => {
        const env = makeEnv();
        const account = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945382f9d57f8e7d7dcd5a9f37f2f6af6f5d7d");
        const supplierId = "com.meshi.app.v1";
        const signed = await signDeclaration(account, "commercial_reserve", supplierId, "commercial");

        const response = await fetchFromWorker("/api/v2/supplier-ids/reserve", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: account.address,
                message: signed.message,
                signature: signed.signature,
            }),
        });

        expect(response.status).toBe(201);
        const data: any = await response.json();
        expect(data.ok).toBe(true);
        expect(data.supplier_id.status).toBe("reserved");
        expect(data.supplier_id.supplier_type).toBe("commercial");
    });

    it("rejects reserve when supplier id is already taken by another wallet", async () => {
        const env = makeEnv();
        const accountA = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945382f9d57f8e7d7dcd5a9f37f2f6af6f5d7d");
        const accountB = privateKeyToAccount("0x8b3a350cf5c34c9194ca3a545d6b6a2d8f49b35f8e0c8f0cfd2db2a5d47f4f08");
        const supplierId = "com.meshi.app.v2";

        const signedA = await signDeclaration(accountA, "commercial_reserve", supplierId, "commercial");
        await fetchFromWorker("/api/v2/supplier-ids/reserve", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: accountA.address,
                message: signedA.message,
                signature: signedA.signature,
            }),
        });

        const signedB = await signDeclaration(accountB, "commercial_reserve", supplierId, "commercial");
        const response = await fetchFromWorker("/api/v2/supplier-ids/reserve", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: accountB.address,
                message: signedB.message,
                signature: signedB.signature,
            }),
        });

        expect(response.status).toBe(409);
        const data: any = await response.json();
        expect(data.error_code).toBe("SUPPLIER_ID_TAKEN");
    });

    it("registers private supplier id and supports idempotent replay", async () => {
        const env = makeEnv();
        const account = privateKeyToAccount("0x0f4b8b3e37b36f74f74cc6f2b92d77e0d36066db2f4e0f6b56755f8b4d8e2501");
        const supplierId = "com.meshi.private.v1";
        const signed = await signDeclaration(account, "private_register", supplierId, "private");

        const first = await fetchFromWorker("/api/v2/supplier-ids/register-private", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: account.address,
                message: signed.message,
                signature: signed.signature,
            }),
        });
        expect(first.status).toBe(201);

        const second = await fetchFromWorker("/api/v2/supplier-ids/register-private", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: account.address,
                message: signed.message,
                signature: signed.signature,
            }),
        });
        expect(second.status).toBe(200);
        const data: any = await second.json();
        expect(data.supplier_id.status).toBe("active");
        expect(data.supplier_id.supplier_type).toBe("private");
    });

    it("confirms reserved commercial supplier id", async () => {
        const env = makeEnv();
        const account = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945382f9d57f8e7d7dcd5a9f37f2f6af6f5d7d");
        const supplierId = "com.meshi.confirm.v1";

        const reserveSigned = await signDeclaration(account, "commercial_reserve", supplierId, "commercial");
        await fetchFromWorker("/api/v2/supplier-ids/reserve", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: account.address,
                message: reserveSigned.message,
                signature: reserveSigned.signature,
            }),
        });

        const confirmSigned = await signDeclaration(account, "commercial_confirm", supplierId, "commercial");
        const response = await fetchFromWorker("/api/v2/supplier-ids/confirm-commercial", env, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                supplier_id: supplierId,
                owner_wallet: account.address,
                chain_id: 84532,
                tx_hash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                profile_url: "https://example.com/profile/com.meshi.confirm.v1.json",
                message: confirmSigned.message,
                signature: confirmSigned.signature,
            }),
        });

        expect(response.status).toBe(200);
        const data: any = await response.json();
        expect(data.ok).toBe(true);
        expect(data.supplier_id.status).toBe("active");
        expect(data.supplier_id.chain_id).toBe(84532);
        expect(data.supplier_id.last_verified_tx).toBe("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    });
});
