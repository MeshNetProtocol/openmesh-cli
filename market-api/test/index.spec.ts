import { describe, it, expect } from 'vitest';

const WORKER_URL = 'http://localhost:8787';

describe('OpenMesh API - Universal Links', () => {
	describe('Apple App Site Association', () => {
		it('should serve AASA file from /.well-known/apple-app-site-association', async () => {
			const response = await fetch(`${WORKER_URL}/.well-known/apple-app-site-association`);
			
			expect(response.status).toBe(200);
			expect(response.headers.get('Content-Type')).toBe('application/json');
			
			const data = await response.json();
			expect(data).toHaveProperty('applinks');
			expect(data).toHaveProperty('webcredentials');
			expect(data.applinks).toHaveProperty('details');
			expect(Array.isArray(data.applinks.details)).toBe(true);
		});

		it('should serve AASA file from /apple-app-site-association', async () => {
			const response = await fetch(`${WORKER_URL}/apple-app-site-association`);
			
			expect(response.status).toBe(200);
			expect(response.headers.get('Content-Type')).toBe('application/json');
			
			const data = await response.json();
			expect(data).toHaveProperty('applinks');
		});

		it('should include correct structure in AASA file', async () => {
			const response = await fetch(`${WORKER_URL}/.well-known/apple-app-site-association`);
			const data = await response.json();
			
			// Check applinks structure
			expect(data.applinks.details[0]).toHaveProperty('appIDs');
			expect(data.applinks.details[0]).toHaveProperty('components');
			expect(Array.isArray(data.applinks.details[0].appIDs)).toBe(true);
			expect(Array.isArray(data.applinks.details[0].components)).toBe(true);
			
			// Check for expected path patterns
			const components = data.applinks.details[0].components;
			const paths = components.map((c: any) => c['/']).filter(Boolean);
			expect(paths).toContain('/link/*');
			expect(paths).toContain('/share/*');
			expect(paths).toContain('/invite/*');
		});

		it('should have proper cache headers', async () => {
			const response = await fetch(`${WORKER_URL}/.well-known/apple-app-site-association`);
			
			const cacheControl = response.headers.get('Cache-Control');
			expect(cacheControl).toBeTruthy();
			expect(cacheControl).toContain('max-age');
		});

		it('should support CORS', async () => {
			const response = await fetch(`${WORKER_URL}/.well-known/apple-app-site-association`);
			
			expect(response.headers.get('Access-Control-Allow-Origin')).toBe('*');
			expect(response.headers.get('Access-Control-Allow-Methods')).toBeTruthy();
		});
	});

	describe('API Endpoints', () => {
		it('should return API information at root path', async () => {
			const response = await fetch(WORKER_URL);
			
			expect(response.status).toBe(200);
			expect(response.headers.get('Content-Type')).toBe('application/json');
			
			const data = await response.json();
			expect(data).toHaveProperty('service');
			expect(data).toHaveProperty('version');
			expect(data).toHaveProperty('endpoints');
			expect(data).toHaveProperty('universalLinks');
		});

		it('should provide health check endpoint', async () => {
			const response = await fetch(`${WORKER_URL}/api/health`);
			
			expect(response.status).toBe(200);
			
			const data = await response.json();
			expect(data).toHaveProperty('status');
			expect(data.status).toBe('healthy');
			expect(data).toHaveProperty('timestamp');
			expect(data).toHaveProperty('universalLinks');
		});

		it('should validate links correctly', async () => {
			const validUrls = [
				'https://example.com/link/abc123',
				'https://example.com/share/content456',
				'https://example.com/invite/user789'
			];

			for (const url of validUrls) {
				const response = await fetch(`${WORKER_URL}/api/validate-link`, {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({ url })
				});

				expect(response.status).toBe(200);
				
				const data = await response.json();
				expect(data.valid).toBe(true);
				expect(data.matched).toBe(true);
			}
		});

		it('should reject invalid links', async () => {
			const invalidUrls = [
				'https://example.com/other/path',
				'https://example.com/admin/page'
			];

			for (const url of invalidUrls) {
				const response = await fetch(`${WORKER_URL}/api/validate-link`, {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({ url })
				});

				expect(response.status).toBe(200);
				
				const data = await response.json();
				expect(data.valid).toBe(false);
				expect(data.matched).toBe(false);
			}
		});

		it('should handle invalid JSON in validation request', async () => {
			const response = await fetch(`${WORKER_URL}/api/validate-link`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: 'invalid json'
			});

			expect(response.status).toBe(400);
			
			const data = await response.json();
			expect(data).toHaveProperty('error');
		});

		it('should return 404 for undefined API routes', async () => {
			const response = await fetch(`${WORKER_URL}/api/undefined-route`);
			
			expect(response.status).toBe(404);
			
			const data = await response.json();
			expect(data).toHaveProperty('error');
			expect(data.error).toBe('Not Found');
		});
	});

	describe('CORS Support', () => {
		it('should handle OPTIONS preflight requests', async () => {
			const response = await fetch(`${WORKER_URL}/.well-known/apple-app-site-association`, {
				method: 'OPTIONS'
			});

			expect(response.status).toBe(204);
			expect(response.headers.get('Access-Control-Allow-Origin')).toBe('*');
			expect(response.headers.get('Access-Control-Allow-Methods')).toBeTruthy();
			expect(response.headers.get('Access-Control-Max-Age')).toBeTruthy();
		});
	});
});
