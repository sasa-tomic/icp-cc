import { Env } from '../types';
import { JsonResponse, DatabaseService } from '../utils';

export async function handleMarketplaceStatsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const database = db.getDatabase();

    // Log database info for debugging
    console.log('Marketplace stats - Database info:', {
      hasDb: !!database,
      envKeys: Object.keys(env),
      dbType: database ? 'D1Database' : 'null'
    });

    // Get total scripts count
    const totalScriptsResult = await database.prepare(`
      SELECT COUNT(*) as count FROM scripts 
      WHERE is_public = 1
    `).first();

    // Get total verified authors
    const totalAuthorsResult = await database.prepare(`
      SELECT COUNT(*) as count FROM users 
      WHERE is_verified_developer = 1
    `).first();

    // Get all scripts for stats calculation
    const allScriptsResult = await database.prepare(`
      SELECT downloads, rating FROM scripts 
      WHERE is_public = 1
    `).all();

    // Calculate total downloads and average rating
    let totalDownloads = 0;
    let totalRating = 0;
    let ratedScriptsCount = 0;

    allScriptsResult.results.forEach((script: any) => {
      totalDownloads += script.downloads || 0;

      if (script.rating && script.rating > 0) {
        totalRating += script.rating;
        ratedScriptsCount++;
      }
    });

    const averageRating = ratedScriptsCount > 0 ? totalRating / ratedScriptsCount : 0;

    // Get total purchases and reviews counts
    const totalPurchasesResult = await database.prepare(`
      SELECT COUNT(*) as count FROM purchases
    `).first();

    const totalReviewsResult = await database.prepare(`
      SELECT COUNT(*) as count FROM reviews
    `).first();

    // Get scripts by category distribution
    const categoryStats: any = {};
    const scriptsByCategory = await database.prepare(`
      SELECT category, downloads, rating FROM scripts 
      WHERE is_public = 1
    `).all();

    scriptsByCategory.results.forEach((script: any) => {
      const category = script.category || 'Other';
      if (!categoryStats[category]) {
        categoryStats[category] = {
          count: 0,
          totalDownloads: 0,
          averageRating: 0,
          ratingCount: 0,
          totalRating: 0
        };
      }

      categoryStats[category].count++;
      categoryStats[category].totalDownloads += script.downloads || 0;

      if (script.rating && script.rating > 0) {
        categoryStats[category].ratingCount++;
        categoryStats[category].totalRating += script.rating;
      }
    });

    // Calculate average rating per category
    Object.keys(categoryStats).forEach(category => {
      if (categoryStats[category].ratingCount > 0) {
        categoryStats[category].averageRating =
          categoryStats[category].totalRating / categoryStats[category].ratingCount;
      }
    });

    const stats = {
      totalScripts: totalScriptsResult?.count || 0,
      totalAuthors: totalAuthorsResult?.count || 0,
      totalDownloads,
      averageRating: Math.round(averageRating * 100) / 100, // Round to 2 decimal places
      totalPurchases: totalPurchasesResult?.count || 0,
      totalReviews: totalReviewsResult?.count || 0,
      categoryBreakdown: categoryStats,
      // Additional helpful metrics
      activeDevelopers: totalAuthorsResult?.count || 0,
      scriptsWithDownloads: allScriptsResult.results.filter((script: any) => script.downloads > 0).length,
      scriptsWithReviews: allScriptsResult.results.filter((script: any) => script.rating > 0).length,
      generatedAt: new Date().toISOString()
    };

    console.log('Marketplace stats generated successfully');

    return JsonResponse.success(stats);
  } catch (err: any) {
    console.error('Failed to generate marketplace stats:', err.message);

    return JsonResponse.error('Failed to generate marketplace stats', 500, err.message);
  }
}

export async function handleUpdateScriptStatsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const { scriptId } = await request.json() as any;

    if (!scriptId) {
      return JsonResponse.error('Script ID is required', 400);
    }

    const dbService = new DatabaseService(env);
    const database = dbService.getDatabase();

    // Log database info for debugging
    console.log('Update script stats - Database info:', {
      hasDb: !!database,
      scriptId: scriptId,
      envKeys: Object.keys(env),
      dbType: database ? 'D1Database' : 'null'
    });

    // Get all reviews for script
    const reviews = await database.prepare(`
      SELECT rating FROM reviews WHERE script_id = ?
    `).bind(scriptId).all();

    // Calculate new average rating
    const totalRating = reviews.results.reduce((sum: number, review: any) => sum + review.rating, 0);
    const averageRating = reviews.results.length > 0 ? totalRating / reviews.results.length : 0;

    // Update script
    await database.prepare(`
      UPDATE scripts 
      SET rating = ?, review_count = ?, updated_at = ?
      WHERE id = ?
    `).bind(
      Math.round(averageRating * 100) / 100, // Round to 2 decimal places
      reviews.results.length,
      new Date().toISOString(),
      scriptId
    ).run();

    // Get script details for author stats update
    const script = await database.prepare(`
      SELECT author_id FROM scripts WHERE id = ?
    `).bind(scriptId).first();

    if (script?.author_id) {
      await updateAuthorStats(database, script.author_id);
    }

    return JsonResponse.success({
      scriptId,
      newAverageRating: Math.round(averageRating * 100) / 100,
      reviewCount: reviews.results.length
    });
  } catch (err: any) {
    console.error('Stats update failed:', err.message);
    return JsonResponse.error('Stats update failed', 500, err.message);
  }
}

async function updateAuthorStats(db: D1Database, authorId: string): Promise<void> {
  // Count all scripts by this author
  const authorScripts = await db.prepare(`
    SELECT COUNT(*) as count, AVG(rating) as avg_rating 
    FROM scripts 
    WHERE author_id = ? AND is_public = 1
  `).bind(authorId).first();

  // Update author stats
  await db.prepare(`
    UPDATE users 
    SET scripts_published = ?, average_rating = ?, updated_at = ?
    WHERE id = ?
  `).bind(
    authorScripts?.count || 0,
    Math.round(((authorScripts as any)?.avg_rating || 0) * 100) / 100,
    new Date().toISOString(),
    authorId
  ).run();
}
