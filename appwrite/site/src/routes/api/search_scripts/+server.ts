import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const POST: RequestHandler = async ({ request }) => {
  try {
    const { query, category, canisterId, minRating, maxPrice, sortBy = 'createdAt', order = 'desc', limit = 20, offset = 0 } = await request.json();

    // Import Query from the SDK
    const { Query } = sdk;

    let queries: any[] = [];

    // Base query for public and approved scripts
    queries.push(Query.equal('isPublic', true));
    queries.push(Query.equal('isApproved', true));

    // Full-text search across title, description, and tags
    if (query) {
      queries.push(Query.search('title', query));
      queries.push(Query.search('description', query));
    }

    // Category filter
    if (category) {
      queries.push(Query.equal('category', category));
    }

    // Canister ID filter - check if script is compatible with specified canister
    if (canisterId) {
      queries.push(Query.search('canisterIds', canisterId));
    }

    // Rating filter
    if (minRating) {
      queries.push(Query.greaterThanEqual('rating', minRating));
    }

    // Price filter
    if (maxPrice !== undefined) {
      queries.push(Query.lessThanEqual('price', maxPrice));
    }

    // Sort order
    queries.push(Query.orderDesc(sortBy === 'rating' || sortBy === 'downloads' || sortBy === 'createdAt' ? sortBy : 'createdAt'));

    // Pagination
    queries.push(Query.limit(limit));
    queries.push(Query.offset(offset));

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
      data: {
        scripts: enrichedScripts,
        total: scripts.total,
        hasMore: scripts.documents.length < scripts.total
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Search failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Search failed',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};