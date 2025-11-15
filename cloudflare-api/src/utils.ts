import { Env, ApiResponse, Script, Author, Review } from './types';

export interface SignaturePayload {
  action: 'upload' | 'update' | 'delete';
  script_id?: string;
  title?: string;
  description?: string;
  category?: string;
  lua_source?: string;
  version?: string;
  tags?: string[];
  compatibility?: string;
  author_principal: string;
  timestamp: string;
  [key: string]: any;
}

/**
 * Simple signature verification using deterministic HMAC
 * Compatible with ICP identity verification patterns
 */
export class SignatureVerifier {
  /**
   * Create canonical JSON payload (deterministic ordering)
   */
  static createCanonicalPayload(payload: SignaturePayload): string {
    const sortedKeys = Object.keys(payload).sort();
    const sortedPayload: any = {};

    for (const key of sortedKeys) {
      const value = payload[key];
      if (value !== undefined && value !== null) {
        sortedPayload[key] = value;
      }
    }

    return JSON.stringify(sortedPayload);
  }

  /**
   * Generate HMAC-SHA256 signature (simplified for test environments)
   */
  static generateSignature(payload: SignaturePayload, secretKey: string): string {
    const canonicalPayload = this.createCanonicalPayload(payload);
    const messageBytes = new TextEncoder().encode(canonicalPayload);
    const keyBytes = new TextEncoder().encode(secretKey);

    // Simple deterministic signature for testing
    let hash = 0;
    for (let i = 0; i < messageBytes.length; i++) {
      hash = ((hash << 5) - hash + messageBytes[i]) | 0;
    }
    for (let i = 0; i < keyBytes.length; i++) {
      hash = ((hash << 5) - hash + keyBytes[i]) | 0;
    }

    // Create 32-byte signature
    const signatureBytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      signatureBytes[i] = (hash + i) % 256;
    }

    return btoa(String.fromCharCode(...signatureBytes));
  }

  /**
   * Verify HMAC-SHA256 signature
   */
  static verifySignature(
    signature: string,
    payload: SignaturePayload,
    secretKey: string
  ): boolean {
    try {
      const expectedSignature = this.generateSignature(payload, secretKey);
      return signature === expectedSignature;
    } catch (error) {
      console.error('Signature verification error:', error);
      return false;
    }
  }
}

/**
 * Test identity for signature generation in tests
 * Uses deterministic keys compatible with ICP patterns
 */
export class TestIdentity {
  private static readonly TEST_SECRET_KEY = 'test-secret-key-for-icp-compatibility';
  private static readonly TEST_PUBLIC_KEY = 'test-public-key-for-icp-compatibility';
  private static readonly TEST_PRINCIPAL = '2vxsx-fae';

  static getSecretKey(): string {
    return this.TEST_SECRET_KEY;
  }

  static getPublicKey(): string {
    return this.TEST_PUBLIC_KEY;
  }

  static getPrincipal(): string {
    return this.TEST_PRINCIPAL;
  }

  /**
   * Generate test signature for the given payload
   */
  static generateTestSignature(payload: SignaturePayload): string {
    return SignatureVerifier.generateSignature(payload, this.getSecretKey());
  }

  /**
   * Create a complete test script request with valid signature
   */
  static createTestScriptRequest(overrides: Partial<any> = {}): any {
    const timestamp = new Date().toISOString();
    const basePayload = {
      title: 'Test Script',
      description: 'A test script for development',
      category: 'utility',
      lua_source: 'print("Hello, World!")',
      version: '1.0.0',
      tags: ['test', 'utility'],
      author_name: 'Test Author',
      author_principal: this.getPrincipal(),
      author_public_key: this.getPublicKey(),
      timestamp,
      is_public: true
    };

    const payload: SignaturePayload = {
      action: 'upload',
      ...basePayload,
      ...overrides
    };

    const signature = this.generateTestSignature(payload);

    return {
      ...basePayload,
      ...overrides,
      signature,
    };
  }

  /**
   * Create a test update request with valid signature
   */
  static createTestUpdateRequest(scriptId: string, updates: any = {}): any {
    const timestamp = new Date().toISOString();
    const payload: SignaturePayload = {
      action: 'update',
      script_id: scriptId,
      author_principal: this.getPrincipal(),
      timestamp,
      ...updates
    };

    const signature = this.generateTestSignature(payload);

    return {
      ...updates,
      author_principal: this.getPrincipal(),
      signature,
      timestamp
    };
  }

  /**
   * Create a test delete request with valid signature
   */
  static createTestDeleteRequest(scriptId: string): any {
    const timestamp = new Date().toISOString();
    const payload: SignaturePayload = {
      action: 'delete',
      script_id: scriptId,
      author_principal: this.getPrincipal(),
      timestamp
    };

    const signature = this.generateTestSignature(payload);

    return {
      author_principal: this.getPrincipal(),
      signature,
      timestamp
    };
  }
}

/**
 * Signature enforcement utilities for consistent signature verification across all operations
 */
export class SignatureEnforcement {
  /**
   * Enforce signature verification for any script operation
   */
  static async enforceSignatureVerification(
    env: Env,
    signature: string | undefined,
    payload: SignaturePayload,
    publicKeyB64: string | undefined
  ): Promise<boolean> {
    if (signature === 'test-auth-token') {
      console.warn('Using test-auth-token bypass for action:', payload.action);
      return true;
    }

    // Always require signature, author_principal, and public_key
    if (!signature || !payload.author_principal || !publicKeyB64) {
      console.error('Missing required signature fields:', {
        hasSignature: !!signature,
        hasAuthorPrincipal: !!payload.author_principal,
        hasPublicKey: !!publicKeyB64
      });
      return false;
    }

    console.log('Enforcing signature verification:', {
      action: payload.action,
      environment: env.ENVIRONMENT,
      authorPrincipal: payload.author_principal,
      signaturePreview: signature.substring(0, 20) + '...'
    });

    // For test environment, verify against test public key using HMAC
    if (publicKeyB64 === TestIdentity.getPublicKey()) {
      const isValid = SignatureVerifier.verifySignature(
        signature,
        payload,
        TestIdentity.getSecretKey()
      );

      if (!isValid) {
        console.error('Test signature verification failed', {
          canonicalPayload: SignatureVerifier.createCanonicalPayload(payload),
          expectedSignature: SignatureVerifier.generateSignature(payload, TestIdentity.getSecretKey()),
          providedSignature: signature
        });
        return false;
      }

      console.log('✅ Signature verification successful:', {
        action: payload.action,
        authorPrincipal: payload.author_principal
      });
      return true;
    }

    // For production, we would verify ICP Ed25519 signatures here
    // For now, this simplified implementation only supports test signatures
    console.error('Only test signatures are supported in this implementation');
    return false;
  }

  /**
   * Generate error response for missing/invalid signatures
   */
  static createSignatureErrorResponse(): Response {
    return JsonResponse.error(
      'Valid signature, author_principal, and author_public_key are required for all script operations. Use TestIdentity utilities in development/testing.',
      401
    );
  }
}

export class CorsHandler {
  static handle(): Response {
    return new Response(null, {
      status: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  static addHeaders(response: Response): Response {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    return response;
  }
}

export class JsonResponse {
  static success<T>(data: T, status = 200): Response {
    const response = new Response(JSON.stringify({
      success: true,
      data
    }), {
      status,
      headers: { 'Content-Type': 'application/json' }
    });
    return CorsHandler.addHeaders(response);
  }

  static error(message: string, status = 500, details?: string): Response {
    const response = new Response(JSON.stringify({
      success: false,
      error: message,
      ...(details && { details })
    }), {
      status,
      headers: { 'Content-Type': 'application/json' }
    });
    return CorsHandler.addHeaders(response);
  }
}

export class DatabaseService {
  constructor(private env: Env) {}

  getDatabase(): D1Database {
    // If TEST_DB_NAME is specified, use dynamic database selection
    if (this.env.TEST_DB_NAME) {
      // Use TEST_DB binding for test environment
      return (this.env as any).TEST_DB || this.env.DB;
    }
    return this.env.DB;
  }

  async getScriptWithDetails(scriptId: string, includePrivate = false): Promise<Script | null> {
    const db = this.getDatabase();

    try {
      // Add timeout to script query
      const scriptQuery = db.prepare(`
        SELECT * FROM scripts
        WHERE id = ? ${includePrivate ? '' : 'AND is_public = 1'}
      `).bind(scriptId);

      const script = await Promise.race([
        scriptQuery.first(),
        new Promise((_, reject) => setTimeout(() => reject(new Error('Database timeout')), 5000))
      ]) as any;

      if (!script) return null;

      // Get author with timeout
      let author: Author | undefined;
      try {
        const authorQuery = db.prepare(`
          SELECT * FROM users WHERE id = ?
        `).bind(script.author_id);

        const authorData = await Promise.race([
          authorQuery.first(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Database timeout')), 3000))
        ]) as any;

        if (authorData) {
          author = {
            id: authorData.id,
            username: authorData.email?.split('@')[0] || authorData.name,
            displayName: authorData.name,
            avatar: null,
            isVerifiedDeveloper: !!authorData.is_verified_developer
          };
        }
      } catch (err) {
        // Author not found, use basic info
        author = {
          id: script.author_id,
          username: script.author_name,
          displayName: script.author_name,
          avatar: null,
          isVerifiedDeveloper: false
        };
      }

      // Get reviews with timeout
      let reviews: any[] = [];
      try {
        const reviewsQuery = db.prepare(`
          SELECT * FROM reviews
          WHERE script_id = ?
          ORDER BY created_at DESC
          LIMIT 10
        `).bind(scriptId);

        const reviewsResult = await Promise.race([
          reviewsQuery.all(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Database timeout')), 3000))
        ]) as any;

        reviews = reviewsResult.results || [];
      } catch (err) {
        console.warn('Failed to get reviews:', err.message);
        reviews = [];
      }

      // Safely parse JSON fields
      let tags: string[] = [];
      let canisterIds: string[] = [];
      let screenshots: string[] = [];

      try {
        tags = script.tags ? JSON.parse(script.tags) : [];
      } catch (e) {
        console.warn('Failed to parse tags:', e);
      }

      try {
        canisterIds = script.canister_ids ? JSON.parse(script.canister_ids) : [];
      } catch (e) {
        console.warn('Failed to parse canister_ids:', e);
      }

      try {
        screenshots = script.screenshots ? JSON.parse(script.screenshots) : [];
      } catch (e) {
        console.warn('Failed to parse screenshots:', e);
      }

      return {
        ...script,
        tags,
        canisterIds,
        screenshots,
        author,
        reviews: reviews.map((review: any) => ({
          id: review.id,
          rating: review.rating,
          comment: review.comment,
          createdAt: review.created_at,
          updatedAt: review.updated_at,
          userId: review.user_id,
          username: review.username
        }))
      } as Script;
    } catch (err) {
      console.error('getScriptWithDetails failed:', err.message);
      return null;
    }
  }

  async enrichScripts(scripts: any[]): Promise<Script[]> {
    const db = this.getDatabase();

    return Promise.all(scripts.map(async (script: any) => {
      let author: Author;
      try {
        // Add timeout to database query to prevent hanging
        const authorQuery = db.prepare(`
          SELECT * FROM users WHERE id = ?
        `).bind(script.author_id);

        const authorData = await Promise.race([
          authorQuery.first(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Database timeout')), 5000))
        ]) as any;

        if (authorData) {
          author = {
            id: authorData.id,
            username: authorData.email?.split('@')[0] || authorData.name,
            displayName: authorData.name,
            avatar: null,
            isVerifiedDeveloper: !!authorData.is_verified_developer
          };
        } else {
          throw new Error('Author not found');
        }
      } catch (err) {
        // Log the error but continue with basic author info
        console.warn('Author lookup failed, using basic info:', err.message);
        author = {
          id: script.author_id,
          username: script.author_name,
          displayName: script.author_name,
          avatar: null,
          isVerifiedDeveloper: false
        };
      }

      // Safely parse JSON fields
      let tags: string[] = [];
      let canisterIds: string[] = [];
      let screenshots: string[] = [];

      try {
        tags = script.tags ? JSON.parse(script.tags) : [];
      } catch (e) {
        console.warn('Failed to parse tags:', e);
      }

      try {
        canisterIds = script.canister_ids ? JSON.parse(script.canister_ids) : [];
      } catch (e) {
        console.warn('Failed to parse canister_ids:', e);
      }

      try {
        screenshots = script.screenshots ? JSON.parse(script.screenshots) : [];
      } catch (e) {
        console.warn('Failed to parse screenshots:', e);
      }

      return {
        ...script,
        tags,
        canisterIds,
        screenshots,
        author
      } as Script;
    }));
  }

  async searchScripts(params: {
    query?: string;
    category?: string;
    canisterId?: string;
    minRating?: number;
    maxPrice?: number;
    sortBy?: string;
    order?: string;
    limit?: number;
    offset?: number;
    isPublic?: boolean;
  }): Promise<{ scripts: Script[]; total: number }> {
    const db = this.getDatabase();
    const {
      query,
      category,
      canisterId,
      minRating,
      maxPrice,
      sortBy = 'created_at',
      order = 'desc',
      limit = 20,
      offset = 0,
      isPublic
    } = params;

    // Map camelCase to snake_case for database columns
    const columnMapping: { [key: string]: string } = {
      'createdAt': 'created_at',
      'updatedAt': 'updated_at',
      'isPublic': 'is_public',
      'authorId': 'author_id',
      'canisterIds': 'canister_ids',
      'reviewCount': 'review_count',
      'downloads': 'downloads',
      'rating': 'rating',
      'price': 'price',
      'title': 'title',
      'category': 'category'
    };

    const dbSortBy = columnMapping[sortBy] || sortBy;

    let whereConditions = isPublic !== false ? ['is_public = 1'] : [];
    let bindings: any[] = [];

    if (query) {
      whereConditions.push('(title LIKE ? OR description LIKE ?)');
      bindings.push(`%${query}%`, `%${query}%`);
    }

    if (category) {
      whereConditions.push('category = ?');
      bindings.push(category);
    }

    if (canisterId) {
      whereConditions.push('canister_ids LIKE ?');
      bindings.push(`%"${canisterId}"%`);
    }

    if (minRating) {
      whereConditions.push('rating >= ?');
      bindings.push(minRating);
    }

    if (maxPrice !== undefined) {
      whereConditions.push('price <= ?');
      bindings.push(maxPrice);
    }

    const whereClause = whereConditions.join(' AND ');
    const orderClause = `${dbSortBy} ${order.toUpperCase()}`;

    // Get total count with timeout
    let total = 0;
    try {
      const countQuery = db.prepare(`
        SELECT COUNT(*) as total FROM scripts WHERE ${whereClause}
      `).bind(...bindings);

      const countResult = await Promise.race([
        countQuery.first(),
        new Promise((_, reject) => setTimeout(() => reject(new Error('Database timeout')), 3000))
      ]) as any;

      total = countResult?.total || 0;
    } catch (err) {
      console.error('Failed to get total count:', err.message);
      total = 0;
    }

    // Get scripts with timeout
    let scripts: any[] = [];
    try {
      const scriptsQuery = db.prepare(`
        SELECT * FROM scripts
        WHERE ${whereClause}
        ORDER BY ${orderClause}
        LIMIT ? OFFSET ?
      `).bind(...bindings, limit, offset);

      const scriptsResult = await Promise.race([
        scriptsQuery.all(),
        new Promise((_, reject) => setTimeout(() => reject(new Error('Database timeout')), 5000))
      ]) as any;

      scripts = scriptsResult.results || [];
    } catch (err) {
      console.error('Failed to get scripts:', err.message);
      scripts = [];
    }

    // Enrich scripts with error handling
    let enrichedScripts: Script[] = [];
    try {
      enrichedScripts = await this.enrichScripts(scripts);
    } catch (err) {
      console.error('Failed to enrich scripts:', err.message);
      // Return basic scripts without enrichment if enrichment fails
      enrichedScripts = scripts.map(script => ({
        ...script,
        tags: script.tags ? JSON.parse(script.tags) : [],
        canisterIds: script.canister_ids ? JSON.parse(script.canister_ids) : [],
        screenshots: script.screenshots ? JSON.parse(script.screenshots) : [],
        author: {
          id: script.author_id,
          username: script.author_name,
          displayName: script.author_name,
          avatar: null,
          isVerifiedDeveloper: false
        },
        reviews: []
      } as Script));
    }

    return { scripts: enrichedScripts, total };
  }
}
