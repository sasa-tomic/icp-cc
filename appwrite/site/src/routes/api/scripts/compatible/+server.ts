import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const GET: RequestHandler = async ({ url }) => {
  try {
    const canisterIdsParam = url.searchParams.get('canister_ids');
    const limit = parseInt(url.searchParams.get('limit') || '50');

    if (!canisterIdsParam) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Canister IDs are required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const canisterIds = canisterIdsParam.split(',').map(id => id.trim());
    const { Query } = sdk;

    // Build search queries for each canister ID
    let scripts: any[] = [];

    for (const canisterId of canisterIds) {
      const scriptsResult = await db.listDocuments(
        process.env.DATABASE_ID || '',
        process.env.SCRIPTS_COLLECTION_ID || '',
        [
          Query.equal('isPublic', true),
          Query.equal('isApproved', true),
          Query.search('canisterIds', canisterId),
          Query.limit(limit)
        ]
      );

      scripts = scripts.concat(scriptsResult.documents);
    }

    // Remove duplicates and get author details
    const uniqueScripts = scripts.filter((script, index, self) =>
      index === self.findIndex((s) => s.$id === script.$id)
    );

    const enrichedScripts = await Promise.all(
      uniqueScripts.map(async (script: any) => {
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
    console.error('Get compatible scripts failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to get compatible scripts',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};