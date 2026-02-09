import { describe, it, expect } from 'vitest';
import worker from '../src/index';

const env = {
	MARKET_VERSION: '1',
	MARKET_UPDATED_AT: '2026-02-08T00:00:00Z',
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
		const response = await fetchFromWorker('/api/v1/providers/official-online');
		expect(response.status).toBe(200);
		const data: any = await response.json();
		expect(data.ok).toBe(true);
		expect(data.provider.id).toBe('official-online');
		expect(data.package).toHaveProperty('package_hash');
		expect(Array.isArray(data.package.files)).toBe(true);
		expect(data.package.files.some((f: any) => f.type === 'config')).toBe(true);
		expect(data.package.files.some((f: any) => f.type === 'rule_set')).toBe(true);
	});

	it('returns provider routing rules', async () => {
		const response = await fetchFromWorker('/api/v1/rules/official-online/routing_rules.json');
		expect(response.status).toBe(200);
		const data = await response.json();
		expect(data).toHaveProperty('proxy');
	});
});
