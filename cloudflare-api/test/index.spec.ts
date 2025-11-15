import { env, createExecutionContext, waitOnExecutionContext, SELF } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';
import worker from '../src';

describe('ICP Marketplace API worker', () => {
	describe('Health check', () => {
		it('/health responds with success message', async () => {
			const request = new Request('http://example.com/health');
			const response = await SELF.fetch(request);
			expect(response.status).toBe(200);
			const data = await response.json();
			expect(data.success).toBe(true);
			expect(data.message).toContain('ICP Marketplace API is running');
		});
	});

	describe('Scripts API', () => {
		it('/api/v1/scripts returns 500 when database not available', async () => {
			const request = new Request('http://example.com/api/v1/scripts');
			const response = await SELF.fetch(request);
			expect(response.status).toBe(500);
			const data = await response.json();
			expect(data.success).toBe(false);
		});

		it('/api/v1/scripts/search rejects GET requests', async () => {
			const request = new Request('http://example.com/api/v1/scripts/search?q=test');
			const response = await SELF.fetch(request);
			expect(response.status).toBe(405);
			const data = await response.json();
			expect(data.success).toBe(false);
			expect(data.error).toBe('Method not allowed');
		});

		it('/api/v1/scripts/search handles POST requests', async () => {
			const request = new Request('http://example.com/api/v1/scripts/search', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ query: 'test' })
			});
			const response = await SELF.fetch(request);
			expect(response.status).toBe(500);
			const data = await response.json();
			expect(data.success).toBe(false);
		});

		it('/api/v1/marketplace-stats returns default values when database not available', async () => {
			const request = new Request('http://example.com/api/v1/marketplace-stats');
			const response = await SELF.fetch(request);
			expect(response.status).toBe(500);
			const data = await response.json();
			expect(data.success).toBe(true);
			expect(data.data.totalScripts).toBe(0);
			expect(data.data.totalDownloads).toBe(0);
			expect(data.data.error).toBe('Stats calculation failed, showing defaults');
		});
	});

	describe('Error handling', () => {
		it('returns 404 for unknown endpoints', async () => {
			const request = new Request('http://example.com/unknown');
			const response = await SELF.fetch(request);
			expect(response.status).toBe(404);
			const data = await response.json();
			expect(data.success).toBe(false);
			expect(data.error).toBe('Not Found');
		});
	});

	describe('CORS handling', () => {
		it('handles OPTIONS requests', async () => {
			const request = new Request('http://example.com/api/scripts', {
				method: 'OPTIONS'
			});
			const response = await SELF.fetch(request);
			expect(response.status).toBe(200);
		});
	});
});
