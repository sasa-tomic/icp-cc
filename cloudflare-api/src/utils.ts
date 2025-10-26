import { Env, ApiResponse, Script, Author, Review } from './types';

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

  async getScriptWithDetails(scriptId: string): Promise<Script | null> {
    // Get script
    const script = await this.env.DB.prepare(`
      SELECT * FROM scripts 
      WHERE id = ? AND is_public = 1
    `).bind(scriptId).first();

    if (!script) return null;

    // Get author
    let author: Author | undefined;
    try {
      const authorData = await this.env.DB.prepare(`
        SELECT * FROM users WHERE id = ?
      `).bind(script.author_id).first();

      if (authorData) {
        author = {
          id: authorData.id,
          username: authorData.email?.split('@')[0] || authorData.name,
          displayName: authorData.name,
          avatar: null, // Add avatar field if needed
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

    // Get reviews
    const reviews = await this.env.DB.prepare(`
      SELECT * FROM reviews 
      WHERE script_id = ? 
      ORDER BY created_at DESC 
      LIMIT 10
    `).bind(scriptId).all();

    return {
      ...script,
      tags: script.tags ? JSON.parse(script.tags as string) : [],
      canisterIds: script.canister_ids ? JSON.parse(script.canister_ids as string) : [],
      screenshots: script.screenshots ? JSON.parse(script.screenshots as string) : [],
      author,
      reviews: reviews.results.map((review: any) => ({
        id: review.id,
        rating: review.rating,
        comment: review.comment,
        createdAt: review.created_at,
        updatedAt: review.updated_at,
        userId: review.user_id,
        username: review.username // Add username if needed
      }))
    } as Script;
  }

  async enrichScripts(scripts: any[]): Promise<Script[]> {
    return Promise.all(scripts.map(async (script: any) => {
      let author: Author;
      try {
        const authorData = await this.env.DB.prepare(`
          SELECT * FROM users WHERE id = ?
        `).bind(script.author_id).first();

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
        author = {
          id: script.author_id,
          username: script.author_name,
          displayName: script.author_name,
          avatar: null,
          isVerifiedDeveloper: false
        };
      }

      return {
        ...script,
        tags: script.tags ? JSON.parse(script.tags) : [],
        canisterIds: script.canister_ids ? JSON.parse(script.canister_ids) : [],
        screenshots: script.screenshots ? JSON.parse(script.screenshots) : [],
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
  }): Promise<{ scripts: Script[]; total: number }> {
    const {
      query,
      category,
      canisterId,
      minRating,
      maxPrice,
      sortBy = 'created_at',
      order = 'desc',
      limit = 20,
      offset = 0
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

    let whereConditions = ['is_public = 1'];
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

    // Get total count
    const countResult = await this.env.DB.prepare(`
      SELECT COUNT(*) as total FROM scripts WHERE ${whereClause}
    `).bind(...bindings).first();

    const total = countResult?.total || 0;

    // Get scripts
    const scriptsResult = await this.env.DB.prepare(`
      SELECT * FROM scripts 
      WHERE ${whereClause} 
      ORDER BY ${orderClause} 
      LIMIT ? OFFSET ?
    `).bind(...bindings, limit, offset).all();

    const enrichedScripts = await this.enrichScripts(scriptsResult.results);

    return { scripts: enrichedScripts, total };
  }
}