import { env, createExecutionContext, waitOnExecutionContext, SELF } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';
import worker from '../src';

describe('ICP Marketplace API worker', () => {
	describe('Health check', () => {
		it('/api/v1/health responds with success message', async () => {
			const request = new Request('http://example.com/api/v1/health');
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

		it('should generate consistent SHA256 hash for identical script content', async () => {
			// Test SHA256 hash generation consistency
			const scriptContent = 'Test Script|Test Description|utility|print("hello")|TestAuthor|1.0.0';
			const encoder = new TextEncoder();
			const data = encoder.encode(scriptContent);
			const hashBuffer1 = await crypto.subtle.digest('SHA-256', data);
			const hashArray1 = Array.from(new Uint8Array(hashBuffer1));
			const scriptId1 = hashArray1.map(b => b.toString(16).padStart(2, '0')).join('');
			
			// Generate hash again with same content
			const hashBuffer2 = await crypto.subtle.digest('SHA-256', data);
			const hashArray2 = Array.from(new Uint8Array(hashBuffer2));
			const scriptId2 = hashArray2.map(b => b.toString(16).padStart(2, '0')).join('');
			
			expect(scriptId1).toBe(scriptId2);
			expect(scriptId1).toHaveLength(64); // SHA256 produces 64 hex characters
		});

		it('should generate different SHA256 hashes for different script content', async () => {
			// Test with different content
			const scriptContent1 = 'Test Script|Test Description|utility|print("hello")|TestAuthor|1.0.0';
			const scriptContent2 = 'Different Script|Test Description|utility|print("hello")|TestAuthor|1.0.0';
			
			const encoder = new TextEncoder();
			const data1 = encoder.encode(scriptContent1);
			const data2 = encoder.encode(scriptContent2);
			
			const hashBuffer1 = await crypto.subtle.digest('SHA-256', data1);
			const hashArray1 = Array.from(new Uint8Array(hashBuffer1));
			const scriptId1 = hashArray1.map(b => b.toString(16).padStart(2, '0')).join('');
			
			const hashBuffer2 = await crypto.subtle.digest('SHA-256', data2);
			const hashArray2 = Array.from(new Uint8Array(hashBuffer2));
			const scriptId2 = hashArray2.map(b => b.toString(16).padStart(2, '0')).join('');
			
			expect(scriptId1).not.toBe(scriptId2);
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
