import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { SELF, env } from 'cloudflare:test';
import { TestIdentity } from '../src/utils';
import { applyMigrations, resetDatabase } from './helpers/database';

async function createScript(overrides: Record<string, unknown> = {}) {
  const requestBody = TestIdentity.createTestScriptRequest({
    title: 'Integration Test Script',
    description: 'A script for integration testing',
    category: 'test',
    lua_source: 'print("Hello, Integration!")',
    ...overrides
  });

  const response = await SELF.fetch('http://example.com/api/v1/scripts', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(requestBody)
  });

  const data = await response.json();
  return { response, data, requestBody };
}

describe.sequential('Script Routes Integration (real D1)', () => {
  beforeAll(async () => {
    await applyMigrations();
  });

  beforeEach(async () => {
    await resetDatabase();
  });

  describe('POST /api/v1/scripts', () => {
    it('creates script with valid signature and persists data', async () => {
      const { response, data } = await createScript();

      expect(response.status).toBe(201);
      expect(data.success).toBe(true);
      expect(data.data.title).toBe('Integration Test Script');

      const persisted = await env.DB.prepare(
        'SELECT title, description, category FROM scripts WHERE id = ?'
      ).bind(data.data.id).first();

      expect(persisted?.title).toBe('Integration Test Script');
      expect(persisted?.description).toBe('A script for integration testing');
      expect(persisted?.category).toBe('test');
    });

    it('rejects script creation without signature', async () => {
      const requestBody = TestIdentity.createTestScriptRequest({
        title: 'Unsigned Script'
      });
      delete (requestBody as any).signature;

      const response = await SELF.fetch('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody)
      });

      const data = await response.json();
      expect(response.status).toBe(401);
      expect(data.success).toBe(false);
      expect(data.error).toContain('signature');
    });

    it('rejects script creation with invalid signature', async () => {
      const requestBody = TestIdentity.createTestScriptRequest({
        title: 'Tampered Script'
      });
      (requestBody as any).signature = 'invalid-signature';

      const response = await SELF.fetch('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody)
      });

      const data = await response.json();
      expect(response.status).toBe(401);
      expect(data.success).toBe(false);
      expect(data.error).toContain('signature');
    });
  });

  describe('PUT /api/v1/scripts/:id', () => {
    it('updates script when signature and principal are valid', async () => {
      const { data } = await createScript();
      const scriptId = data.data.id as string;

      const updatePayload = TestIdentity.createTestUpdateRequest(scriptId, {
        title: 'Updated Integration Script',
        description: 'Updated description'
      });

      const response = await SELF.fetch(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatePayload)
      });

      const body = await response.json();
      expect(response.status).toBe(200);
      expect(body.success).toBe(true);
      expect(body.data.title).toBe('Updated Integration Script');

      const persisted = await env.DB.prepare(
        'SELECT title, description FROM scripts WHERE id = ?'
      ).bind(scriptId).first();

      expect(persisted?.title).toBe('Updated Integration Script');
      expect(persisted?.description).toBe('Updated description');
    });

    it('rejects script update without signature', async () => {
      const { data } = await createScript();
      const scriptId = data.data.id as string;

      const updatePayload: any = {
        title: 'Unsigned Update',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const response = await SELF.fetch(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatePayload)
      });

      const body = await response.json();
      expect(response.status).toBe(401);
      expect(body.success).toBe(false);
      expect(body.error).toContain('signature');
    });

    it('rejects script update from different principal', async () => {
      const { data } = await createScript();
      const scriptId = data.data.id as string;

      const updatePayload = TestIdentity.createTestUpdateRequest(scriptId, {
        title: 'Hijacked Update'
      });
      updatePayload.author_principal = 'different-principal';

      const response = await SELF.fetch(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatePayload)
      });

      const body = await response.json();
      expect(response.status).toBe(403);
      expect(body.success).toBe(false);
      expect(body.error).toContain('Author principal does not match script author');
    });
  });

  describe('DELETE /api/v1/scripts/:id', () => {
    it('deletes script when signature is valid', async () => {
      const { data } = await createScript();
      const scriptId = data.data.id as string;

      const deletePayload = TestIdentity.createTestDeleteRequest(scriptId);

      const response = await SELF.fetch(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(deletePayload)
      });

      const body = await response.json();
      expect(response.status).toBe(200);
      expect(body.success).toBe(true);
      expect(body.data.message).toContain('deleted successfully');

      const persisted = await env.DB.prepare(
        'SELECT id FROM scripts WHERE id = ?'
      ).bind(scriptId).first();
      expect(persisted).toBeNull();
    });

    it('rejects script deletion without signature', async () => {
      const { data } = await createScript();
      const scriptId = data.data.id as string;

      const deletePayload: any = {
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const response = await SELF.fetch(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(deletePayload)
      });

      const body = await response.json();
      expect(response.status).toBe(401);
      expect(body.success).toBe(false);
      expect(body.error).toContain('signature');
    });
  });
});
