import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const GET: RequestHandler = async ({ params }) => {
  try {
    const scriptId = params.id;

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

    // Get the script document
    const scriptDoc = await db.getDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId,
      [
        Query.equal('isPublic', true),
        Query.equal('isApproved', true)
      ]
    );

    // Get author details
    let author = {
      id: scriptDoc.authorId,
      username: scriptDoc.authorName,
      displayName: scriptDoc.authorName,
      avatar: null,
      isVerifiedDeveloper: false
    };

    try {
      const authorDoc = await db.getDocument(
        process.env.DATABASE_ID || '',
        process.env.USERS_COLLECTION_ID || '',
        scriptDoc.authorId
      );

      author = {
        id: authorDoc.$id,
        username: authorDoc.username,
        displayName: authorDoc.displayName,
        avatar: authorDoc.avatar,
        isVerifiedDeveloper: authorDoc.isVerifiedDeveloper
      };
    } catch (err) {
      // Author not found, use basic info
    }

    // Get reviews for this script
    const reviewsResult = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.REVIEWS_COLLECTION_ID || '',
      [
        Query.equal('scriptId', scriptId),
        Query.orderDesc('createdAt'),
        Query.limit(10)
      ]
    );

    const script = {
      ...scriptDoc,
      author,
      reviews: reviewsResult.documents.map((review: any) => ({
        id: review.$id,
        rating: review.rating,
        comment: review.comment,
        verified: review.verified,
        createdAt: review.createdAt,
        updatedAt: review.updatedAt,
        userId: review.userId,
        username: review.username
      }))
    };

    return new Response(JSON.stringify({
      success: true,
      data: script
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Get script details failed:', err.message);

    if (err.code === 404) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script not found'
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to get script details',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

export const PUT: RequestHandler = async ({ params, request }) => {
  try {
    const scriptId = params.id;

    if (!scriptId) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script ID is required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const updateData = await request.json();

    // Add updated timestamp
    updateData.updatedAt = new Date().toISOString();

    const result = await db.updateDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId,
      updateData
    );

    return new Response(JSON.stringify({
      success: true,
      data: result
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Update script failed:', err.message);

    if (err.code === 404) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script not found'
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to update script',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

export const DELETE: RequestHandler = async ({ params }) => {
  try {
    const scriptId = params.id;

    if (!scriptId) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script ID is required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    await db.deleteDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId
    );

    return new Response(JSON.stringify({
      success: true,
      message: 'Script deleted successfully'
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Delete script failed:', err.message);

    if (err.code === 404) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script not found'
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to delete script',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};