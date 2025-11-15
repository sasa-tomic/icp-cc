import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const POST: RequestHandler = async ({ request }) => {
  try {
    // Extract event data
    const { payload } = await request.json();

    // Only process new review documents
    if (payload.$collectionId !== process.env.REVIEWS_COLLECTION_ID || payload.$operation !== 'create') {
      return new Response(JSON.stringify({
        success: true,
        message: 'Event not relevant for script stats update'
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const { scriptId, rating, userId } = payload;

    // Import Query from the SDK
    const { Query } = sdk;

    // Get all reviews for the script
    const reviews = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.REVIEWS_COLLECTION_ID || '',
      [
        Query.equal('scriptId', scriptId),
        Query.equal('status', 'approved')
      ]
    );

    // Calculate new average rating and review count
    let totalRating = 0;
    let verifiedCount = 0;
    reviews.documents.forEach((review: any) => {
      totalRating += review.rating;
      if (review.isVerifiedPurchase) {
        verifiedCount++;
      }
    });

    const averageRating = reviews.total > 0 ? totalRating / reviews.total : 0;
    const reviewCount = reviews.total;
    const verifiedReviewCount = verifiedCount;

    // Update script document with new stats
    await db.updateDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId,
      {
        rating: parseFloat(averageRating.toFixed(2)),
        reviewCount: reviewCount,
        verifiedReviewCount: verifiedReviewCount
      }
    );

    // Update author stats if this is their first script
    const scriptDoc: any = await db.getDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId
    );

    const userDoc: any = await db.getDocument(
      process.env.DATABASE_ID || '',
      process.env.USERS_COLLECTION_ID || '',
      scriptDoc.authorId
    );

    // Count all scripts by this author
    const authorScripts = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      [
        Query.equal('authorId', scriptDoc.authorId),
        Query.equal('isPublic', true),
        Query.equal('isApproved', true)
      ]
    );

    // Calculate author's average rating across all scripts
    let authorTotalRating = 0;
    authorScripts.documents.forEach((script: any) => {
      authorTotalRating += script.rating || 0;
    });

    const authorAverageRating = authorScripts.total > 0 ? authorTotalRating / authorScripts.total : 0;

    await db.updateDocument(
      process.env.DATABASE_ID || '',
      process.env.USERS_COLLECTION_ID || '',
      scriptDoc.authorId,
      {
        scriptsPublished: authorScripts.total,
        averageRating: parseFloat(authorAverageRating.toFixed(2)),
        totalDownloads: userDoc.totalDownloads || 0 // Keep existing downloads
      }
    );

    return new Response(JSON.stringify({
      success: true,
      data: {
        scriptId,
        newAverageRating: averageRating,
        reviewCount,
        verifiedReviewCount,
        authorId: scriptDoc.authorId,
        authorStats: {
          scriptsPublished: authorScripts.total,
          averageRating: authorAverageRating
        }
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Stats update failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Stats update failed',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};