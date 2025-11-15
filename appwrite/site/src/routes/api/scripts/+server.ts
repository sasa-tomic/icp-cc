import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';
import { ID } from 'node-appwrite';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://icp-autorun.appwrite.network/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const POST: RequestHandler = async ({ request }) => {
  try {
    const {
      title,
      description,
      category,
      tags,
      lua_source,
      author_name,
      canister_ids = [],
      icon_url,
      screenshots = [],
      version = '1.0.0',
      compatibility,
      price = 0.0,
      is_public = true,
      is_approved = false
    } = await request.json();

    // Validate required fields
    if (!title || !description || !category || !lua_source || !author_name) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Missing required fields: title, description, category, lua_source, author_name'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create a new script document
    const scriptData = {
      title,
      description,
      category,
      tags: tags || [],
      luaSource: lua_source,
      authorName: author_name,
      authorId: 'anonymous', // In a real app, this would come from authentication
      canisterIds: canister_ids || [],
      iconUrl: icon_url || null,
      screenshots: screenshots || [],
      version,
      compatibility,
      price,
      isPublic: is_public,
      isApproved: is_approved,
      downloads: 0,
      rating: 0,
      reviewCount: 0,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const result = await db.createDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      ID.unique(),
      scriptData
    );

    return new Response(JSON.stringify({
      success: true,
      data: result
    }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Upload script failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to upload script',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};