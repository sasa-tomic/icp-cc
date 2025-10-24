import { client, databases } from 'node-appwrite';

export default async ({ req, res, log, error }) => {
    const client = new client()
      .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
      .setKey(process.env.APPWRITE_FUNCTION_API_KEY);

    const databases = new databases(client);

    try {
        const { userId, scriptId, paymentMethod, price, transactionId } = JSON.parse(req.body);

        // Validate input
        if (!userId || !scriptId || !paymentMethod || price === undefined || !transactionId) {
            return res.json({
                success: false,
                error: 'Missing required fields'
            }, 400);
        }

        // Check if user has already purchased this script
        const existingPurchases = await databases.listDocuments(
            process.env.DATABASE_ID,
            process.env.PURCHASES_COLLECTION_ID,
            [
                appwrite.Query.equal('userId', userId),
                appwrite.Query.equal('scriptId', scriptId),
                appwrite.Query.equal('status', 'completed')
            ]
        );

        if (existingPurchases.total > 0) {
            return res.json({
                success: false,
                error: 'Script already purchased'
            }, 409);
        }

        // Get script details
        const scriptDoc = await databases.getDocument(
            process.env.DATABASE_ID,
            process.env.SCRIPTS_COLLECTION_ID,
            scriptId
        );

        if (!scriptDoc.isPublic || !scriptDoc.isApproved) {
            return res.json({
                success: false,
                error: 'Script not available for purchase'
            }, 404);
        }

        // Create purchase record
        const purchase = await databases.createDocument(
            process.env.DATABASE_ID,
            process.env.PURCHASES_COLLECTION_ID,
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
        await databases.updateDocument(
            process.env.DATABASE_ID,
            process.env.SCRIPTS_COLLECTION_ID,
            scriptId,
            {
                downloads: (scriptDoc.downloads || 0) + 1
            }
        );

        // Update user's total downloads if they are the script author
        if (scriptDoc.authorId === userId) {
            const userDoc = await databases.getDocument(
                process.env.DATABASE_ID,
                process.env.USERS_COLLECTION_ID,
                userId
            );

            await databases.updateDocument(
                process.env.DATABASE_ID,
                process.env.USERS_COLLECTION_ID,
                userId,
                {
                    totalDownloads: (userDoc.totalDownloads || 0) + 1
                }
            );
        }

        return res.json({
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
        });

    } catch (err) {
        error('Purchase processing failed: ' + err.message);
        return res.json({
            success: false,
            error: 'Purchase processing failed',
            details: err.message
        }, 500);
    }
};