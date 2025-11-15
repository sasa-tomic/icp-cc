import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { applyMigrations, resetDatabase, dropCoreTables } from './helpers/database';

describe.sequential('ICP Marketplace API worker', () => {
	beforeAll(async () => {
		await applyMigrations();
	});

	beforeEach(async () => {
		await resetDatabase();
	});

	describe('Health check', () => {
		it('/api/v1/health responds with success message', async () => {
			const response = await SELF.fetch('http://example.com/api/v1/health');
			expect(response.status).toBe(200);
			const data = await response.json();
			expect(data.success).toBe(true);
			expect(data.message).toContain('ICP Marketplace API is running');
		});
	});

	describe('Scripts API', () => {
		it('/api/v1/scripts returns empty dataset when database has no scripts', async () => {
			const response = await SELF.fetch('http://example.com/api/v1/scripts');
			expect(response.status).toBe(200);
			const data = await response.json();
			expect(data.success).toBe(true);
			expect(Array.isArray(data.data.scripts)).toBe(true);
			expect(data.data.total).toBe(0);
		});

		it('should generate consistent SHA256 hash for identical script content', async () => {
			const scriptContent = 'Test Script|Test Description|utility|print("hello")|TestAuthor|1.0.0';
			const encoder = new TextEncoder();
			const data = encoder.encode(scriptContent);
			const hashBuffer1 = await crypto.subtle.digest('SHA-256', data);
			const hashArray1 = Array.from(new Uint8Array(hashBuffer1));
			const scriptId1 = hashArray1.map(b => b.toString(16).padStart(2, '0')).join('');

			const hashBuffer2 = await crypto.subtle.digest('SHA-256', data);
			const hashArray2 = Array.from(new Uint8Array(hashBuffer2));
			const scriptId2 = hashArray2.map(b => b.toString(16).padStart(2, '0')).join('');

			expect(scriptId1).toBe(scriptId2);
			expect(scriptId1).toHaveLength(64);
		});

		it('should generate different SHA256 hashes for different script content', async () => {
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

		it('/api/v1/scripts/search supports GET requests', async () => {
			const response = await SELF.fetch('http://example.com/api/v1/scripts/search?q=test');
			expect(response.status).toBe(200);
			const data = await response.json();
			expect(data.success).toBe(true);
			expect(Array.isArray(data.data.scripts)).toBe(true);
		});

		it('/api/v1/scripts/search returns results for POST requests', async () => {
			const response = await SELF.fetch('http://example.com/api/v1/scripts/search', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ query: 'test' })
			});

			const data = await response.json();
			expect(response.status).toBe(200);
			expect(data.success).toBe(true);
			expect(Array.isArray(data.data.scripts)).toBe(true);
		});

		it('/api/v1/marketplace-stats returns aggregated values when data exists', async () => {
			const now = new Date().toISOString();

			await env.DB.prepare(`
				INSERT INTO users (id, email, name, is_verified_developer, created_at, updated_at)
				VALUES (?, ?, ?, 1, ?, ?)
			`).bind('user-1', 'dev@example.com', 'Dev One', now, now).run();

			await env.DB.prepare(`
				INSERT INTO users (id, email, name, is_verified_developer, created_at, updated_at)
				VALUES (?, ?, ?, 0, ?, ?)
			`).bind('user-2', 'tester@example.com', 'Tester Two', now, now).run();

			await env.DB.prepare(`
				INSERT INTO scripts (
					id, title, description, category, tags, lua_source, author_name, author_id,
					author_principal, author_public_key, upload_signature, canister_ids, icon_url,
					screenshots, version, compatibility, price, is_public, downloads, rating,
					review_count, created_at, updated_at
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			`).bind(
				'script-1',
				'Script One',
				'Description',
				'utility',
				JSON.stringify(['test']),
				'print("hello")',
				'Dev One',
				'user-1',
				'2vxsx-fae',
				'test-public-key',
				'test-signature',
				JSON.stringify(['canister-1']),
				null,
				JSON.stringify([]),
				'1.0.0',
				null,
				10.5,
				1,
				42,
				4.5,
				2,
				now,
				now
			).run();

			await env.DB.prepare(`
				INSERT INTO reviews (id, script_id, user_id, rating, comment, created_at, updated_at)
				VALUES (?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?)
			`).bind(
				'review-1', 'script-1', 'user-1', 5, 'Great', now, now,
				'review-2', 'script-1', 'user-2', 4, 'Good', now, now
			).run();

			await env.DB.prepare(`
				INSERT INTO purchases (id, script_id, user_id, price, purchase_date)
				VALUES (?, ?, ?, ?, ?)
			`).bind('purchase-1', 'script-1', 'user-1', 10.5, now).run();

			const response = await SELF.fetch('http://example.com/api/v1/marketplace-stats');
			const data = await response.json();

			expect(response.status).toBe(200);
			expect(data.success).toBe(true);
			expect(data.data.totalScripts).toBe(1);
			expect(data.data.totalAuthors).toBe(1);
			expect(data.data.totalDownloads).toBe(42);
			expect(data.data.totalReviews).toBeGreaterThanOrEqual(2);
			expect(data.data.totalPurchases).toBe(1);
			expect(data.data.averageRating).toBeGreaterThan(0);
		});

		it('/api/v1/marketplace-stats fails loudly when schema missing', async () => {
			await dropCoreTables();

			const response = await SELF.fetch('http://example.com/api/v1/marketplace-stats');
			const data = await response.json();

			expect(response.status).toBe(500);
			expect(data.success).toBe(false);
			expect(data.error).toBe('Failed to generate marketplace stats');
		});
	});

	describe('Script validation', () => {
		it('/api/v1/scripts/validate rejects non-POST requests', async () => {
			const response = await SELF.fetch('http://example.com/api/v1/scripts/validate');
			const data = await response.json();
			expect(response.status).toBe(405);
			expect(data.success).toBe(false);
			expect(data.error).toBe('Method not allowed');
		});

		it('/api/v1/scripts/validate rejects empty script', async () => {
			const response = await SELF.fetch('http://example.com/api/v1/scripts/validate', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ lua_source: '' })
			});
			const data = await response.json();
			expect(response.status).toBe(200);
			expect(data.success).toBe(true);
			expect(data.data.is_valid).toBe(false);
			expect(data.data.errors).toContain('Lua source cannot be empty');
		});

		it('/api/v1/scripts/validate accepts valid script', async () => {
			const validScript = `
function init()
	return { counter = 0 }
end

function view(state)
	return {
		type = "column",
		children = {
			{ type = "text", text = "Counter: " .. state.counter },
			{ type = "button", text = "Increment", on_press = { type = "increment" } }
		}
	}
end

function update(msg, state)
	if msg.type == "increment" then
		state.counter = state.counter + 1
	end
	return state
end
			`;

			const response = await SELF.fetch('http://example.com/api/v1/scripts/validate', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ lua_source: validScript })
			});
			const data = await response.json();
			expect(response.status).toBe(200);
			expect(data.success).toBe(true);
			expect(data.data.is_valid).toBe(true);
			expect(data.data.errors).toHaveLength(0);
		});

		it('/api/v1/scripts/validate detects security issues', async () => {
			const dangerousScript = `
function init()
	return {}
end

function view(state)
	return { type = "text", text = "Hello" }
end

function update(msg, state)
	loadstring("print('dangerous')")
	return state
end
			`;

			const response = await SELF.fetch('http://example.com/api/v1/scripts/validate', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ lua_source: dangerousScript })
			});
			const data = await response.json();
			expect(response.status).toBe(200);
			expect(data.success).toBe(true);
			expect(data.data.is_valid).toBe(false);
			expect(data.data.errors.some((e: string) => e.includes('loadstring'))).toBe(true);
		});

		it('/api/v1/scripts/validate detects syntax errors', async () => {
			const syntaxErrorScript = `
function init()
	return { counter = 0
end  -- Missing closing brace

function view(state)
	return { type = "text", text = "Hello" }
end

function update(msg, state)
	return state
end
			`;

			const response = await SELF.fetch('http://example.com/api/v1/scripts/validate', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ lua_source: syntaxErrorScript })
			});
			const data = await response.json();
			expect(response.status).toBe(200);
			expect(data.success).toBe(true);
			expect(data.data.is_valid).toBe(false);
			expect(data.data.errors.length > 0).toBe(true);
		});
	});

	describe('Error handling', () => {
		it('returns 404 for unknown endpoints', async () => {
			const response = await SELF.fetch('http://example.com/unknown');
			const data = await response.json();
			expect(response.status).toBe(404);
			expect(data.success).toBe(false);
			expect(data.error).toBe('Not Found');
		});
	});

	describe('CORS handling', () => {
		it('handles OPTIONS requests', async () => {
			const response = await SELF.fetch('http://example.com/api/scripts', {
				method: 'OPTIONS'
			});
			expect(response.status).toBe(200);
		});
	});
});
