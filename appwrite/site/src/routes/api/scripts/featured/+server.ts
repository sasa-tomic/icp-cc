import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const GET: RequestHandler = async ({ url }) => {
  try {
    const limit = parseInt(url.searchParams.get('limit') || '10');

    const { Query } = sdk;

    // Get featured scripts (high-rated, recent, and public)
    const scripts = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      [
        Query.equal('isPublic', true),
        Query.equal('isApproved', true),
        Query.greaterThanEqual('rating', 4.0),
        Query.orderDesc('rating'),
        Query.orderDesc('createdAt'),
        Query.limit(limit)
      ]
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
    console.error('Get featured scripts failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to get featured scripts',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};