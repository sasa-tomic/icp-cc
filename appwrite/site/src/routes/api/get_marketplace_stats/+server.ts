import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://cloud.appwrite.io/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const GET: RequestHandler = async () => {
  try {
    // Import Query from the SDK
    const { Query } = sdk;

    // Get total scripts count
    const totalScriptsResult = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      [
        // Only count public and approved scripts
        Query.equal('isPublic', true),
        Query.equal('isApproved', true)
      ]
    );

    // Get total unique authors
    const totalAuthorsResult = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.USERS_COLLECTION_ID || '',
      [
        Query.equal('isVerifiedDeveloper', true)
      ]
    );

    // Get total downloads from all scripts
    const allScriptsResult = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      [
        Query.equal('isPublic', true),
        Query.equal('isApproved', true),
        Query.limit(1000) // Get up to 1000 scripts for stats calculation
      ]
    );

    // Calculate total downloads and average rating
    let totalDownloads = 0;
    let totalRating = 0;
    let ratedScriptsCount = 0;

    allScriptsResult.documents.forEach((script: any) => {
      totalDownloads += script.downloads || 0;

      if (script.rating && script.rating > 0) {
        totalRating += script.rating;
        ratedScriptsCount++;
      }
    });

    const averageRating = ratedScriptsCount > 0 ? totalRating / ratedScriptsCount : 0;

    // Get total purchases count
    const totalPurchasesResult = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.PURCHASES_COLLECTION_ID || '',
      [
        Query.limit(1) // We only need the total count
      ]
    );

    // Get total reviews count
    const totalReviewsResult = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.REVIEWS_COLLECTION_ID || '',
      [
        Query.limit(1) // We only need the total count
      ]
    );

    // Get scripts by category distribution
    const categoryStats: any = {};
    const scriptsByCategory = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      [
        Query.equal('isPublic', true),
        Query.equal('isApproved', true),
        Query.limit(1000)
      ]
    );

    scriptsByCategory.documents.forEach((script: any) => {
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
      totalScripts: totalScriptsResult.total,
      totalAuthors: totalAuthorsResult.total,
      totalDownloads,
      averageRating: Math.round(averageRating * 100) / 100, // Round to 2 decimal places
      totalPurchases: totalPurchasesResult.total,
      totalReviews: totalReviewsResult.total,
      categoryBreakdown: categoryStats,
      // Additional helpful metrics
      activeDevelopers: totalAuthorsResult.total,
      scriptsWithDownloads: allScriptsResult.documents.filter((script: any) => script.downloads > 0).length,
      scriptsWithReviews: allScriptsResult.documents.filter((script: any) => script.rating > 0).length,
      generatedAt: new Date().toISOString()
    };

    console.log('Marketplace stats generated successfully');

    return new Response(JSON.stringify({
      success: true,
      data: stats
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Failed to generate marketplace stats:', err.message);

    // Return default stats if calculation fails
    return new Response(JSON.stringify({
      success: true,
      data: {
        totalScripts: 0,
        totalAuthors: 0,
        totalDownloads: 0,
        averageRating: 0.0,
        totalPurchases: 0,
        totalReviews: 0,
        categoryBreakdown: {},
        activeDevelopers: 0,
        scriptsWithDownloads: 0,
        scriptsWithReviews: 0,
        generatedAt: new Date().toISOString(),
        error: 'Stats calculation failed, showing defaults'
      }
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};