import { client, databases } from 'node-appwrite';

export default async ({ req, res, log, error }) => {
    const client = new client()
      .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
      .setKey(process.env.APPWRITE_FUNCTION_API_KEY);

    const databases = new databases(client);

    try {
        const { query, category, canisterId, minRating, maxPrice, sortBy = 'createdAt', order = 'desc', limit = 20, offset = 0 } = JSON.parse(req.body);

        let queries = [];

        // Base query for public and approved scripts
        queries.push(appwrite.Query.equal('isPublic', true));
        queries.push(appwrite.Query.equal('isApproved', true));

        // Full-text search across title, description, and tags
        if (query) {
            queries.push(appwrite.Query.search('title', query));
            queries.push(appwrite.Query.search('description', query));
        }

        // Category filter
        if (category) {
            queries.push(appwrite.Query.equal('category', category));
        }

        // Canister ID filter - check if script is compatible with specified canister
        if (canisterId) {
            queries.push(appwrite.Query.search('canisterIds', canisterId));
        }

        // Rating filter
        if (minRating) {
            queries.push(appwrite.Query.greaterThanEqual('rating', minRating));
        }

        // Price filter
        if (maxPrice !== undefined) {
            queries.push(appwrite.Query.lessThanEqual('price', maxPrice));
        }

        // Sort order
        queries.push(appwrite.Query.orderDesc(sortBy === 'rating' || sortBy === 'downloads' || sortBy === 'createdAt' ? sortBy : 'createdAt'));

        // Pagination
        queries.push(appwrite.Query.limit(limit));
        queries.push(appwrite.Query.offset(offset));

        const scripts = await databases.listDocuments(
            process.env.DATABASE_ID,
            process.env.SCRIPTS_COLLECTION_ID,
            queries
        );

        // Get author details for each script
        const enrichedScripts = await Promise.all(
            scripts.documents.map(async (script) => {
                try {
                    const authorDoc = await databases.getDocument(
                        process.env.DATABASE_ID,
                        process.env.USERS_COLLECTION_ID,
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

        return res.json({
            success: true,
            data: {
                scripts: enrichedScripts,
                total: scripts.total,
                hasMore: scripts.documents.length < scripts.total
            }
        });

    } catch (err) {
        error('Search failed: ' + err.message);
        return res.json({
            success: false,
            error: 'Search failed',
            details: err.message
        }, 500);
    }
};