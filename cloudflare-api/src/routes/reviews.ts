import { Env } from '../types';
import { JsonResponse, DatabaseService } from '../utils';

export async function handleReviewsRequest(request: Request, env: Env, scriptId: string): Promise<Response> {
  if (request.method !== 'GET') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const url = new URL(request.url);
    const limit = parseInt(url.searchParams.get('limit') || '20');
    const offset = parseInt(url.searchParams.get('offset') || '0');
    const verifiedOnly = url.searchParams.get('verified_only') === 'true';

    if (!scriptId) {
      return JsonResponse.error('Script ID is required', 400);
    }

    let query = `
      SELECT * FROM reviews 
      WHERE script_id = ? 
      ORDER BY created_at DESC 
      LIMIT ? OFFSET ?
    `;
    let bindings = [scriptId, limit, offset];

    if (verifiedOnly) {
      query = `
        SELECT * FROM reviews 
        WHERE script_id = ? AND verified = 1 
        ORDER BY created_at DESC 
        LIMIT ? OFFSET ?
      `;
    }

    const database = db.getDatabase();
    const reviews = await database.prepare(query).bind(...bindings).all();

    return JsonResponse.success(reviews.results);
  } catch (err: any) {
    console.error('Get script reviews failed:', err.message);
    return JsonResponse.error('Failed to get script reviews', 500, err.message);
  }
}

export async function handleCreateReviewRequest(request: Request, env: Env, scriptId: string): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const { rating, comment, userId } = await request.json() as any;

    if (!scriptId || !rating || !userId) {
      return JsonResponse.error('Missing required fields: scriptId, rating, userId', 400);
    }

    if (rating < 1 || rating > 5) {
      return JsonResponse.error('Rating must be between 1 and 5', 400);
    }

    const now = new Date().toISOString();
    const reviewId = crypto.randomUUID();

    // Check if user already reviewed this script
    const database = db.getDatabase();
    const existingReview = await database.prepare(`
      SELECT id FROM reviews WHERE script_id = ? AND user_id = ?
    `).bind(scriptId, userId).first();

    if (existingReview) {
      return JsonResponse.error('User has already reviewed this script', 409);
    }

    // Create review
    await database.prepare(`
      INSERT INTO reviews (id, script_id, user_id, rating, comment, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(reviewId, scriptId, userId, rating, comment, now, now).run();

    // Update script rating and review count
    await updateScriptStats(database, scriptId);

    const review = await database.prepare(`
      SELECT * FROM reviews WHERE id = ?
    `).bind(reviewId).first();

    return JsonResponse.success(review, 201);
  } catch (err: any) {
    console.error('Create review failed:', err.message);
    return JsonResponse.error('Failed to create review', 500, err.message);
  }
}

async function updateScriptStats(db: D1Database, scriptId: string): Promise<void> {
  // Get all reviews for script
  const reviews = await db.prepare(`
    SELECT rating FROM reviews WHERE script_id = ?
  `).bind(scriptId).all();

  // Calculate new average rating
  const totalRating = reviews.results.reduce((sum: number, review: any) => sum + review.rating, 0);
  const averageRating = reviews.results.length > 0 ? totalRating / reviews.results.length : 0;

  // Update script
  await db.prepare(`
    UPDATE scripts 
    SET rating = ?, review_count = ?, updated_at = ?
    WHERE id = ?
  `).bind(averageRating, reviews.results.length, new Date().toISOString(), scriptId).run();
}