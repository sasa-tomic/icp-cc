import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const GET: RequestHandler = async ({ params, url }) => {
  try {
    const scriptId = params.id;
    const limit = parseInt(url.searchParams.get('limit') || '20');
    const offset = parseInt(url.searchParams.get('offset') || '0');
    const verifiedOnly = url.searchParams.get('verified_only') === 'true';

    if (!scriptId) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script ID is required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const { Query } = sdk;

    // Build queries
    let queries: any[] = [
      Query.equal('scriptId', scriptId),
      Query.orderDesc('createdAt'),
      Query.limit(limit),
      Query.offset(offset)
    ];

    // Filter by verified purchases if requested
    if (verifiedOnly) {
      queries.push(Query.equal('verified', true));
    }

    // Get reviews for the script
    const reviews = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.REVIEWS_COLLECTION_ID || '',
      queries
    );

    return new Response(JSON.stringify({
      success: true,
      data: reviews.documents
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Get script reviews failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to get script reviews',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};