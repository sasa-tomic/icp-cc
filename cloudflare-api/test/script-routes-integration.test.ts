import { describe, it, expect, beforeEach, beforeAll } from 'vitest';
import { TestIdentity } from '../src/utils';

describe('Script Routes Integration Tests with Signature Enforcement', () => {
  let env: any;
  let mockDb: any;

  beforeAll(() => {
    // Mock D1 database with proper method chaining
    mockDb = {
      prepare: (query: string) => ({
        bind: (...args: any[]) => ({
          run: () => Promise.resolve({ success: true, meta: { changes: 1 } }),
          first: () => Promise.resolve(null),
          all: () => Promise.resolve({ results: [] })
        })
      })
    };

    env = {
      ENVIRONMENT: 'test',
      DB: mockDb,
      TEST_DB: mockDb
    };
  });

  describe('POST /api/v1/scripts', () => {
    it('should create script with valid signature', async () => {
      const testRequest = TestIdentity.createTestScriptRequest({
        title: 'Integration Test Script',
        description: 'A script for testing integration',
        category: 'test',
        lua_source: 'print("Hello, Integration!")'
      });

      const request = new Request('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(testRequest)
      });

      // Import the handler function
      const { handleScriptsRequest } = await import('../src/routes/scripts');
      const response = await handleScriptsRequest(request, env);

      expect(response.status).toBe(201);
      const data = await response.json();
      expect(data.success).toBe(true);
      expect(data.data.title).toBe('Integration Test Script');
    });

    it('should reject script creation without signature', async () => {
      const scriptData = {
        title: 'Invalid Script',
        description: 'No signature provided',
        category: 'test',
        lua_source: 'print("No signature")',
        author_principal: TestIdentity.getPrincipal(),
        author_public_key: TestIdentity.getPublicKey(),
        timestamp: new Date().toISOString()
      };

      const request = new Request('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scriptData)
      });

      const { handleScriptsRequest } = await import('../src/routes/scripts');
      const response = await handleScriptsRequest(request, env);

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.error).toContain('signature');
    });

    it('should reject script creation with invalid signature', async () => {
      const scriptData = {
        title: 'Invalid Signature Script',
        description: 'Invalid signature provided',
        category: 'test',
        lua_source: 'print("Invalid signature")',
        author_principal: TestIdentity.getPrincipal(),
        author_public_key: TestIdentity.getPublicKey(),
        signature: 'invalid-signature',
        timestamp: new Date().toISOString()
      };

      const request = new Request('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scriptData)
      });

      const { handleScriptsRequest } = await import('../src/routes/scripts');
      const response = await handleScriptsRequest(request, env);

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.success).toBe(false);
    });
  });

  describe('PUT /api/v1/scripts/:id', () => {
    const scriptId = 'test-script-id';

    beforeEach(() => {
      // Mock existing script lookup - keep the same structure as beforeAll
      const originalPrepare = mockDb.prepare;
      mockDb.prepare = (query: string) => {
        if (query.includes('SELECT')) {
          return {
            bind: (...args: any[]) => ({
              first: () => Promise.resolve({
                author_principal: TestIdentity.getPrincipal(),
                author_public_key: TestIdentity.getPublicKey()
              })
            })
          };
        }
        return originalPrepare(query);
      };
    });

    it('should update script with valid signature', async () => {
      const updateData = TestIdentity.createTestUpdateRequest(scriptId, {
        title: 'Updated Integration Test Script',
        description: 'Updated description'
      });

      const request = new Request(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updateData)
      });

      const { handleScriptByIdRequest } = await import('../src/routes/scripts');
      const response = await handleScriptByIdRequest(request, env, scriptId);

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.success).toBe(true);
    });

    it('should reject script update without signature', async () => {
      const updateData = {
        title: 'Updated Without Signature',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const request = new Request(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updateData)
      });

      const { handleScriptByIdRequest } = await import('../src/routes/scripts');
      const response = await handleScriptByIdRequest(request, env, scriptId);

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.error).toContain('signature');
    });

    it('should reject script update with wrong author principal', async () => {
      // Mock script with different author
      const originalPrepare = mockDb.prepare;
      mockDb.prepare = (query: string) => {
        if (query.includes('SELECT')) {
          return {
            bind: (...args: any[]) => ({
              first: () => Promise.resolve({
                author_principal: 'different-principal',
                author_public_key: TestIdentity.getPublicKey()
              })
            })
          };
        }
        return originalPrepare(query);
      };

      const updateData = TestIdentity.createTestUpdateRequest(scriptId, {
        title: 'Hijacked Update'
      });

      const request = new Request(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updateData)
      });

      const { handleScriptByIdRequest } = await import('../src/routes/scripts');
      const response = await handleScriptByIdRequest(request, env, scriptId);

      expect(response.status).toBe(403);
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.error).toContain('Author principal does not match');
    });
  });

  describe('DELETE /api/v1/scripts/:id', () => {
    const scriptId = 'test-script-id';

    beforeEach(() => {
      // Mock existing script lookup - keep the same structure as beforeAll
      const originalPrepare = mockDb.prepare;
      mockDb.prepare = (query: string) => {
        if (query.includes('SELECT')) {
          return {
            bind: (...args: any[]) => ({
              first: () => Promise.resolve({
                author_principal: TestIdentity.getPrincipal(),
                author_public_key: TestIdentity.getPublicKey()
              }),
              run: () => Promise.resolve({ success: true, meta: { changes: 1 } })
            })
          };
        }
        return originalPrepare(query);
      };
    });

    it('should delete script with valid signature', async () => {
      const deleteData = TestIdentity.createTestDeleteRequest(scriptId);

      const request = new Request(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(deleteData)
      });

      const { handleScriptByIdRequest } = await import('../src/routes/scripts');
      const response = await handleScriptByIdRequest(request, env, scriptId);

      expect(response.status).toBe(200);
      const data = await response.json();
      expect(data.success).toBe(true);
      expect(data.data.message).toContain('deleted successfully');
    });

    it('should reject script deletion without signature', async () => {
      const deleteData = {
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const request = new Request(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(deleteData)
      });

      const { handleScriptByIdRequest } = await import('../src/routes/scripts');
      const response = await handleScriptByIdRequest(request, env, scriptId);

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.error).toContain('signature');
    });

    it('should reject script deletion when script not found', async () => {
      // Mock script not found
      const originalPrepare = mockDb.prepare;
      mockDb.prepare = (query: string) => {
        if (query.includes('SELECT')) {
          return {
            bind: (...args: any[]) => ({
              first: () => Promise.resolve(null)
            })
          };
        }
        return originalPrepare(query);
      };

      const deleteData = TestIdentity.createTestDeleteRequest(scriptId);

      const request = new Request(`http://example.com/api/v1/scripts/${scriptId}`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(deleteData)
      });

      const { handleScriptByIdRequest } = await import('../src/routes/scripts');
      const response = await handleScriptByIdRequest(request, env, scriptId);

      expect(response.status).toBe(404);
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.error).toContain('Script not found');
    });
  });

  describe('Error Handling', () => {
    it('should handle malformed JSON gracefully', async () => {
      const request = new Request('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'invalid-json'
      });

      const { handleScriptsRequest } = await import('../src/routes/scripts');
      const response = await handleScriptsRequest(request, env);

      expect(response.status).toBe(500);
      const data = await response.json();
      expect(data.success).toBe(false);
    });

    it('should handle missing required fields', async () => {
      const incompleteData = TestIdentity.createTestScriptRequest();
      delete (incompleteData as any).title;
      delete (incompleteData as any).description;

      const request = new Request('http://example.com/api/v1/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(incompleteData)
      });

      const { handleScriptsRequest } = await import('../src/routes/scripts');
      const response = await handleScriptsRequest(request, env);

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.error).toContain('Missing required fields');
    });
  });
});