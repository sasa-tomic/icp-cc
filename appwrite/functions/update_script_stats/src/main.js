import { client, databases } from 'node-appwrite';

export default async ({ req, res, log, error }) => {
    const client = new client()
      .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
      .setKey(process.env.APPWRITE_FUNCTION_API_KEY);

    const databases = new databases(client);

    try {
        // Extract event data
        const { payload } = JSON.parse(req.body);

        // Only process new review documents
        if (payload.$collectionId !== process.env.REVIEWS_COLLECTION_ID || payload.$operation !== 'create') {
            return res.json({
                success: true,
                message: 'Event not relevant for script stats update'
            });
        }

        const { scriptId, rating, userId } = payload;

        // Get all reviews for the script
        const reviews = await databases.listDocuments(
            process.env.DATABASE_ID,
            process.env.REVIEWS_COLLECTION_ID,
            [
                appwrite.Query.equal('scriptId', scriptId),
                appwrite.Query.equal('status', 'approved')
            ]
        );

        // Calculate new average rating and review count
        let totalRating = 0;
        let verifiedCount = 0;
        reviews.documents.forEach(review => {
            totalRating += review.rating;
            if (review.isVerifiedPurchase) {
                verifiedCount++;
            }
        });

        const averageRating = reviews.total > 0 ? totalRating / reviews.total : 0;
        const reviewCount = reviews.total;
        const verifiedReviewCount = verifiedCount;

        // Update script document with new stats
        await databases.updateDocument(
            process.env.DATABASE_ID,
            process.env.SCRIPTS_COLLECTION_ID,
            scriptId,
            {
                rating: parseFloat(averageRating.toFixed(2)),
                reviewCount: reviewCount,
                verifiedReviewCount: verifiedReviewCount
            }
        );

        // Update author stats if this is their first script
        const scriptDoc = await databases.getDocument(
            process.env.DATABASE_ID,
            process.env.SCRIPTS_COLLECTION_ID,
            scriptId
        );

        const userDoc = await databases.getDocument(
            process.env.DATABASE_ID,
            process.env.USERS_COLLECTION_ID,
            scriptDoc.authorId
        );

        // Count all scripts by this author
        const authorScripts = await databases.listDocuments(
            process.env.DATABASE_ID,
            process.env.SCRIPTS_COLLECTION_ID,
            [
                appwrite.Query.equal('authorId', scriptDoc.authorId),
                appwrite.Query.equal('isPublic', true),
                appwrite.Query.equal('isApproved', true)
            ]
        );

        // Calculate author's average rating across all scripts
        let authorTotalRating = 0;
        authorScripts.documents.forEach(script => {
            authorTotalRating += script.rating || 0;
        });

        const authorAverageRating = authorScripts.total > 0 ? authorTotalRating / authorScripts.total : 0;

        await databases.updateDocument(
            process.env.DATABASE_ID,
            process.env.USERS_COLLECTION_ID,
            scriptDoc.authorId,
            {
                scriptsPublished: authorScripts.total,
                averageRating: parseFloat(authorAverageRating.toFixed(2)),
                totalDownloads: userDoc.totalDownloads || 0 // Keep existing downloads
            }
        );

        return res.json({
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
        });

    } catch (err) {
        error('Stats update failed: ' + err.message);
        return res.json({
            success: false,
            error: 'Stats update failed',
            details: err.message
        }, 500);
    }
};