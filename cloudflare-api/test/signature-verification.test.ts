import { describe, it, expect, beforeAll } from 'vitest';
import { TestIdentity, SignatureEnforcement, SignaturePayload, SignatureVerifier } from '../src/utils';

describe('Signature Verification Utilities', () => {
  // Mock environment for testing
  const mockEnv = {
    ENVIRONMENT: 'local',
    DB: null,
    TEST_DB: null
  } as any;

  describe('TestIdentity', () => {
    it('should provide consistent test credentials', () => {
      expect(TestIdentity.getPrincipal()).toBe('2vxsx-fae');
      expect(TestIdentity.getPublicKey()).toBe('test-public-key-for-icp-compatibility');
      expect(TestIdentity.getSecretKey()).toBe('test-secret-key-for-icp-compatibility');
    });

    it('should create valid test script requests', () => {
      const testRequest = TestIdentity.createTestScriptRequest({
        title: 'Custom Test Script'
      });

      expect(testRequest.title).toBe('Custom Test Script');
      expect(testRequest.author_principal).toBe(TestIdentity.getPrincipal());
      expect(testRequest.author_public_key).toBe(TestIdentity.getPublicKey());
      expect(testRequest.signature).toBeDefined();
      expect(testRequest.timestamp).toBeDefined();
    });

    it('should create valid test update requests', () => {
      const testUpdate = TestIdentity.createTestUpdateRequest('test-script-id', {
        title: 'Updated Title'
      });

      expect(testUpdate.author_principal).toBe(TestIdentity.getPrincipal());
      expect(testUpdate.signature).toBeDefined();
      expect(testUpdate.timestamp).toBeDefined();
    });

    it('should create valid test delete requests', () => {
      const testDelete = TestIdentity.createTestDeleteRequest('test-script-id');

      expect(testDelete.author_principal).toBe(TestIdentity.getPrincipal());
      expect(testDelete.signature).toBeDefined();
      expect(testDelete.timestamp).toBeDefined();
    });
  });

  describe('SignatureVerifier', () => {
    it('should create canonical JSON payload with deterministic ordering', () => {
      const payload = {
        z: 'last',
        a: 'first',
        m: 'middle',
        action: 'upload',
        timestamp: '2023-01-01T00:00:00.000Z'
      };

      const canonical = SignatureVerifier.createCanonicalPayload(payload);
      const expected = JSON.stringify({
        a: 'first',
        action: 'upload',
        m: 'middle',
        timestamp: '2023-01-01T00:00:00.000Z',
        z: 'last'
      });

      expect(canonical).toBe(expected);
    });

    it('should generate consistent signatures for identical payloads', () => {
      const payload = {
        action: 'upload',
        title: 'Test Script',
        author_principal: 'test-principal',
        timestamp: '2023-01-01T00:00:00.000Z'
      };

      const signature1 = SignatureVerifier.generateSignature(payload, 'test-secret');
      const signature2 = SignatureVerifier.generateSignature(payload, 'test-secret');

      expect(signature1).toBe(signature2);
      expect(signature1).toMatch(/^[A-Za-z0-9+/]+={0,2}$/); // Base64 format
    });

    it('should generate different signatures for different payloads', () => {
      const payload1 = { action: 'upload', title: 'Script A', timestamp: '2023-01-01T00:00:00.000Z' };
      const payload2 = { action: 'upload', title: 'Script B', timestamp: '2023-01-01T00:00:00.000Z' };

      const signature1 = SignatureVerifier.generateSignature(payload1, 'test-secret');
      const signature2 = SignatureVerifier.generateSignature(payload2, 'test-secret');

      expect(signature1).not.toBe(signature2);
    });

    it('should verify signatures correctly', () => {
      const payload = {
        action: 'upload',
        title: 'Test Script',
        author_principal: 'test-principal',
        timestamp: '2023-01-01T00:00:00.000Z'
      };

      const signature = SignatureVerifier.generateSignature(payload, 'test-secret');
      const isValid = SignatureVerifier.verifySignature(signature, payload, 'test-secret');

      expect(isValid).toBe(true);
    });

    it('should reject invalid signatures', () => {
      const payload = {
        action: 'upload',
        title: 'Test Script',
        author_principal: 'test-principal',
        timestamp: '2023-01-01T00:00:00.000Z'
      };

      const wrongSignature = SignatureVerifier.generateSignature(payload, 'wrong-secret');
      const isValid = SignatureVerifier.verifySignature(wrongSignature, payload, 'test-secret');

      expect(isValid).toBe(false);
    });

    it('should handle malformed signatures gracefully', () => {
      const payload = { action: 'upload', timestamp: '2023-01-01T00:00:00.000Z' };

      expect(() => {
        SignatureVerifier.verifySignature('invalid-signature', payload, 'test-secret');
      }).not.toThrow();

      const isValid = SignatureVerifier.verifySignature('invalid-signature', payload, 'test-secret');
      expect(isValid).toBe(false);
    });
  });

  describe('SignatureEnforcement', () => {
    it('should enforce signature verification for script creation', async () => {
      const testRequest = TestIdentity.createTestScriptRequest();
      // Use the exact same payload structure that TestIdentity uses for signature generation
      const payload: SignaturePayload = {
        action: 'upload',
        title: testRequest.title,
        description: testRequest.description,
        category: testRequest.category,
        lua_source: testRequest.lua_source,
        version: testRequest.version,
        tags: testRequest.tags,
        author_name: testRequest.author_name,
        author_principal: testRequest.author_principal,
        author_public_key: testRequest.author_public_key,
        timestamp: testRequest.timestamp,
        is_public: testRequest.is_public
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        testRequest.signature,
        payload,
        testRequest.author_public_key
      );

      expect(isValid).toBe(true);
    });

    it('should reject requests without signatures', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: 'Test',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        undefined,
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(false);
    });

    it('should reject requests with invalid signatures', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: 'Test',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        'invalid-signature',
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(false);
    });

    it('should enforce signature verification for script updates', async () => {
      const testUpdate = TestIdentity.createTestUpdateRequest('script-id', {
        title: 'Updated Title'
      });

      const payload: SignaturePayload = {
        action: 'update',
        script_id: 'script-id',
        title: 'Updated Title',
        author_principal: testUpdate.author_principal,
        timestamp: testUpdate.timestamp
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        testUpdate.signature,
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(true);
    });

    it('should enforce signature verification for script deletion', async () => {
      const testDelete = TestIdentity.createTestDeleteRequest('script-id');

      const payload: SignaturePayload = {
        action: 'delete',
        script_id: 'script-id',
        author_principal: testDelete.author_principal,
        timestamp: testDelete.timestamp
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        testDelete.signature,
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(true);
    });

    it('should reject requests without author_principal', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: 'Test',
        timestamp: new Date().toISOString()
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        'some-signature',
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(false);
    });

    it('should reject requests without public_key', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: 'Test',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        'some-signature',
        payload,
        undefined
      );

      expect(isValid).toBe(false);
    });

    it('should reject requests with mismatched author_principal in production', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: 'Test',
        author_principal: 'different-principal',
        timestamp: new Date().toISOString()
      };

      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        'some-signature',
        payload,
        'different-public-key'
      );

      expect(isValid).toBe(false);
    });

    it('should handle empty payload fields gracefully', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: '',
        description: '',
        category: '',
        lua_source: '',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString()
      };

      const signature = SignatureVerifier.generateSignature(payload, TestIdentity.getSecretKey());
      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        signature,
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(true);
    });

    it('should handle null and undefined values in payload', async () => {
      const payload: SignaturePayload = {
        action: 'upload',
        title: 'Test Script',
        author_principal: TestIdentity.getPrincipal(),
        timestamp: new Date().toISOString(),
        description: null as any,
        tags: undefined as any,
        compatibility: null as any
      };

      const signature = SignatureVerifier.generateSignature(payload, TestIdentity.getSecretKey());
      const isValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        signature,
        payload,
        TestIdentity.getPublicKey()
      );

      expect(isValid).toBe(true);
    });
  });

  describe('Integration Tests', () => {
    it('should demonstrate complete workflow with test utilities', async () => {
      // 1. Create a script with valid signature (use default values to ensure consistency)
      const createRequest = TestIdentity.createTestScriptRequest();

      const createPayload: SignaturePayload = {
        action: 'upload',
        title: createRequest.title,
        description: createRequest.description,
        category: createRequest.category,
        lua_source: createRequest.lua_source,
        version: createRequest.version,
        tags: createRequest.tags,
        author_name: createRequest.author_name,
        author_principal: createRequest.author_principal,
        author_public_key: createRequest.author_public_key,
        timestamp: createRequest.timestamp,
        is_public: createRequest.is_public
      };

      const isCreateValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        createRequest.signature,
        createPayload,
        createRequest.author_public_key
      );

      expect(isCreateValid).toBe(true);

      // 2. Update the script with valid signature
      const updateRequest = TestIdentity.createTestUpdateRequest('test-script-id', {
        title: 'Updated Integration Test Script'
      });

      const updatePayload: SignaturePayload = {
        action: 'update',
        script_id: 'test-script-id',
        title: 'Updated Integration Test Script',
        author_principal: updateRequest.author_principal,
        timestamp: updateRequest.timestamp
      };

      const isUpdateValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        updateRequest.signature,
        updatePayload,
        TestIdentity.getPublicKey()
      );

      expect(isUpdateValid).toBe(true);

      // 3. Delete the script with valid signature
      const deleteRequest = TestIdentity.createTestDeleteRequest('test-script-id');

      const deletePayload: SignaturePayload = {
        action: 'delete',
        script_id: 'test-script-id',
        author_principal: deleteRequest.author_principal,
        timestamp: deleteRequest.timestamp
      };

      const isDeleteValid = await SignatureEnforcement.enforceSignatureVerification(
        mockEnv,
        deleteRequest.signature,
        deletePayload,
        TestIdentity.getPublicKey()
      );

      expect(isDeleteValid).toBe(true);
    });
  });
});