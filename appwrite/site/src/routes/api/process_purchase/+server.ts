import * as sdk from 'node-appwrite';
import type { RequestHandler } from './$types';

const appwriteClient = new sdk.Client()
  .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT || 'https://cloud.appwrite.io/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_FUNCTION_API_KEY || '');

const db = new sdk.Databases(appwriteClient);

export const POST: RequestHandler = async ({ request }) => {
  try {
    const { userId, scriptId, paymentMethod, price, transactionId } = await request.json();

    // Validate input
    if (!userId || !scriptId || !paymentMethod || price === undefined || !transactionId) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Missing required fields'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Import Query from the SDK
    const { Query } = sdk;

    // Check if user has already purchased this script
    const existingPurchases = await db.listDocuments(
      process.env.DATABASE_ID || '',
      process.env.PURCHASES_COLLECTION_ID || '',
      [
        Query.equal('userId', userId),
        Query.equal('scriptId', scriptId),
        Query.equal('status', 'completed')
      ]
    );

    if (existingPurchases.total > 0) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script already purchased'
      }), {
        status: 409,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get script details
    const scriptDoc: any = await db.getDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId
    );

    if (!scriptDoc.isPublic || !scriptDoc.isApproved) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Script not available for purchase'
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create purchase record
    const purchase = await db.createDocument(
      process.env.DATABASE_ID || '',
      process.env.PURCHASES_COLLECTION_ID || '',
      'unique()',
      {
        userId,
        scriptId,
        transactionId,
        price: parseFloat(price),
        currency: scriptDoc.currency || 'USD',
        paymentMethod,
        status: 'completed'
      }
    );

    // Update script download count
    await db.updateDocument(
      process.env.DATABASE_ID || '',
      process.env.SCRIPTS_COLLECTION_ID || '',
      scriptId,
      {
        downloads: (scriptDoc.downloads || 0) + 1
      }
    );

    // Update user's total downloads if they are the script author
    if (scriptDoc.authorId === userId) {
      const userDoc = await db.getDocument(
        process.env.DATABASE_ID || '',
        process.env.USERS_COLLECTION_ID || '',
        userId
      );

      await db.updateDocument(
        process.env.DATABASE_ID || '',
        process.env.USERS_COLLECTION_ID || '',
        userId,
        {
          totalDownloads: (userDoc.totalDownloads || 0) + 1
        }
      );
    }

    return new Response(JSON.stringify({
      success: true,
      data: {
        purchase,
        script: {
          id: scriptDoc.$id,
          title: scriptDoc.title,
          description: scriptDoc.description,
          luaSource: scriptDoc.luaSource,
          iconUrl: scriptDoc.iconUrl,
          screenshots: scriptDoc.screenshots,
          version: scriptDoc.version,
          compatibility: scriptDoc.compatibility
        }
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Purchase processing failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Purchase processing failed',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};