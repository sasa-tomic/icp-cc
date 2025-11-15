import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const GET: RequestHandler = async ({ params, url }) => {
  try {
    const category = params.category;
    const limit = parseInt(url.searchParams.get('limit') || '20');
    const offset = parseInt(url.searchParams.get('offset') || '0');
    const sortBy = url.searchParams.get('sort_by') || 'rating';
    const sortOrder = url.searchParams.get('sort_order') || 'desc';

    if (!category) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Category is required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const { Query } = sdk;

    // Build queries
    let queries: any[] = [
      Query.equal('isPublic', true),
      Query.equal('isApproved', true),
      Query.equal('category', category)
    ];

    // Sort order
    if (sortOrder === 'desc') {
      queries.push(Query.orderDesc(sortBy));
    } else {
      queries.push(Query.orderAsc(sortBy));
    }

    // Pagination
    queries.push(Query.limit(limit));
    queries.push(Query.offset(offset));

    // Get scripts by category
    const scripts = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      queries
    );

    // Get author details for each script
    const enrichedScripts = await Promise.all(
      scripts.documents.map(async (script: any) => {
        try {
          const authorDoc = await db.getDocument(
            process.env.DATABASE_ID || '',
            process.env.USERS_COLLECTION_ID || '',
            script.authorId
          );

          return {
            ...script,
            author: {
              id: authorDoc.$id,
              username: authorDoc.username,
              displayName: authorDoc.displayName,
              avatar: authorDoc.avatar,
              isVerifiedDeveloper: authorDoc.isVerifiedDeveloper
            }
          };
        } catch (err) {
          // Author not found, return script with basic author info
          return {
            ...script,
            author: {
              id: script.authorId,
              username: script.authorName,
              displayName: script.authorName,
              avatar: null,
              isVerifiedDeveloper: false
            }
          };
        }
      })
    );

    return new Response(JSON.stringify({
      success: true,
      data: enrichedScripts
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Get scripts by category failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to get scripts by category',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};