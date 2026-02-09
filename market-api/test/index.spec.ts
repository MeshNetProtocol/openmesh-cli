import { describe, it, expect } from 'vitest';
import worker from '../src/index';

type ProviderRow = {
	id: string;
	name: string;
	description: string;
	tags_json: string;
	author: string;
	updated_at: string;
	price_per_gb_usd: number | null;
	visibility: 'public' | 'private';
	status: 'active' | 'disabled';
	config_json: string;
	routing_rules_json: string | null;
};

class FakeD1PreparedStatement {
	private sql: string;
	private rows: ProviderRow[];
	private bound: unknown[] = [];

	constructor(sql: string, rows: ProviderRow[]) {
		this.sql = sql;
		this.rows = rows;
	}

	bind(...values: unknown[]) {
		this.bound = values;
		return this;
	}

	async first<T = unknown>(): Promise<T | null> {
		const id = String(this.bound[0] ?? '');
		const row = this.rows.find(r => r.id === id);
		return (row as any) ?? null;
	}

	async all<T = unknown>(): Promise<{ results: T[] }> {
		const results = this.sql.includes("WHERE id=?")
			? (this.rows.filter(r => r.id === String(this.bound[0] ?? '')) as any)
			: (this.rows.filter(r => r.visibility === 'public' && r.status === 'active') as any);
		return { results };
	}

	async run(): Promise<unknown> {
		return {};
	}
}

class FakeD1Database {
	private rows: ProviderRow[];
	constructor(rows: ProviderRow[]) {
		this.rows = rows;
	}
	prepare(query: string) {
		return new FakeD1PreparedStatement(query, this.rows);
	}
}

const officialOnlineConfig = {
	dns: {
		final: 'google-dns',
		reverse_mapping: true,
		strategy: 'ipv4_only',
		servers: [
			{ detour: 'proxy', server: 'dns.google', tag: 'google-dns', type: 'https' },
			{ detour: 'direct', server: '223.5.5.5', tag: 'local-dns', type: 'udp' },
		],
	},
	inbounds: [{ type: 'tun', tag: 'tun-in' }],
	outbounds: [{ type: 'direct', tag: 'direct' }],
	route: {
		rule_set: [
			{
				type: 'remote',
				tag: 'geoip-cn',
				format: 'binary',
				url: 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
				download_detour: 'proxy',
				update_interval: '1d',
			},
			{
				type: 'remote',
				tag: 'geosite-geolocation-cn',
				format: 'binary',
				url: 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
				download_detour: 'proxy',
				update_interval: '1d',
			},
		],
	},
};

const seedRows: ProviderRow[] = [
	{
		id: 'com.meshnetprotocol.profile',
		name: '官方供应商在线版本',
		description: '用于对照测试',
		tags_json: JSON.stringify(['Official', 'Online']),
		author: 'OpenMesh Team',
		updated_at: '2026-02-08T00:00:00Z',
		price_per_gb_usd: 0.0,
		visibility: 'public',
		status: 'active',
		config_json: JSON.stringify(officialOnlineConfig),
		routing_rules_json: JSON.stringify({ proxy: { domain_suffix: ['openai.com'] } }),
	},
];

const env = {
	MARKET_VERSION: '1',
	MARKET_UPDATED_AT: '2026-02-08T00:00:00Z',
	DB: new FakeD1Database(seedRows),
};

async function fetchFromWorker(path: string, init?: RequestInit) {
	const url = `https://example.com${path}`;
	return worker.fetch(new Request(url, init), env as any);
}

describe('OpenMesh Market API - Worker', () => {
	it('supports CORS OPTIONS preflight', async () => {
		const response = await fetchFromWorker('/api/v1/providers', { method: 'OPTIONS' });
		expect(response.status).toBe(204);
		expect(response.headers.get('Access-Control-Allow-Origin')).toBe('*');
	});

	it('returns providers list', async () => {
		const response = await fetchFromWorker('/api/v1/providers');
		expect(response.status).toBe(200);
		const data: any = await response.json();
		expect(data.ok).toBe(true);
		expect(Array.isArray(data.data)).toBe(true);
	});

	it('returns market manifest with stable ETag', async () => {
		const r1 = await fetchFromWorker('/api/v1/market/manifest');
		expect(r1.status).toBe(200);
		const etag = r1.headers.get('ETag');
		expect(etag).toBeTruthy();

		const r2 = await fetchFromWorker('/api/v1/market/manifest', { headers: { 'If-None-Match': etag! } });
		expect(r2.status).toBe(304);
	});

	it('returns provider detail + package files', async () => {
		const response = await fetchFromWorker('/api/v1/providers/com.meshnetprotocol.profile');
		expect(response.status).toBe(200);
		const data: any = await response.json();
		expect(data.ok).toBe(true);
		expect(data.provider.id).toBe('com.meshnetprotocol.profile');
		expect(data.package).toHaveProperty('package_hash');
		expect(Array.isArray(data.package.files)).toBe(true);
		expect(data.package.files.some((f: any) => f.type === 'config')).toBe(true);
		expect(data.package.files.some((f: any) => f.type === 'rule_set')).toBe(true);
	});

	it('returns provider config with remote rule-set URLs', async () => {
		const response = await fetchFromWorker('/api/v1/config/com.meshnetprotocol.profile');
		expect(response.status).toBe(200);
		const data: any = await response.json();
		expect(data).toHaveProperty('route');
		const rs = data?.route?.rule_set;
		expect(Array.isArray(rs)).toBe(true);
		expect(rs.some((x: any) => typeof x?.url === 'string' && x.url.startsWith('https://'))).toBe(true);
	});

	it('returns provider routing rules', async () => {
		const response = await fetchFromWorker('/api/v1/rules/com.meshnetprotocol.profile/routing_rules.json');
		expect(response.status).toBe(200);
		const data = await response.json();
		expect(data).toHaveProperty('proxy');
	});
});
