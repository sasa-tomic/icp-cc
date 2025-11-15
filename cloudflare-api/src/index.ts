import { Env } from './types';
import { CorsHandler } from './utils';
import { 
  handleScriptsRequest, 
  handleScriptByIdRequest,
  handleScriptsByCategoryRequest
} from './routes/scripts';
import { 
  handleSearchScriptsRequest,
  handleTrendingScriptsRequest,
  handleFeaturedScriptsRequest,
  handleCompatibleScriptsRequest
} from './routes/search';
import { 
  handleReviewsRequest,
  handleCreateReviewRequest
} from './routes/reviews';
import { 
  handleScriptValidationRequest
} from './routes/validation';
import { 
  handleMarketplaceStatsRequest,
  handleUpdateScriptStatsRequest
} from './routes/stats';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
      return CorsHandler.handle();
    }

    // API Routes
    try {
      switch (url.pathname) {
        // Scripts endpoints
        case '/api/v1/scripts':
          return handleScriptsRequest(request, env);
        
        case '/api/v1/scripts/search':
          return handleSearchScriptsRequest(request, env);
        
        case '/api/v1/scripts/trending':
          return handleTrendingScriptsRequest(request, env);
        
        case '/api/v1/scripts/featured':
          return handleFeaturedScriptsRequest(request, env);
        
        case '/api/v1/scripts/compatible':
          return handleCompatibleScriptsRequest(request, env);

        case '/api/v1/marketplace-stats':
          return handleMarketplaceStatsRequest(request, env);

        case '/api/v1/update-script-stats':
          return handleUpdateScriptStatsRequest(request, env);

        case '/api/v1/scripts/validate':
          return handleScriptValidationRequest(request, env);

        // Health check
        case '/health':
          return new Response(JSON.stringify({
            success: true,
            message: 'ICP Marketplace API is running',
            environment: env.ENVIRONMENT
          }), {
            headers: { 'Content-Type': 'application/json' }
          });

        default:
          // Handle script by ID or category
          if (url.pathname.startsWith('/api/v1/scripts/')) {
            const pathParts = url.pathname.split('/');
            const id = pathParts[4];
            const action = pathParts[5];
            
            if (id) {
              if (action === 'reviews') {
                if (request.method === 'POST') {
                  return handleCreateReviewRequest(request, env, id);
                } else {
                  return handleReviewsRequest(request, env, id);
                }
              } else if (id === 'category' && pathParts[5]) {
                return handleScriptsByCategoryRequest(request, env, pathParts[5]);
              } else {
                return handleScriptByIdRequest(request, env, id);
              }
            }
          }

          return new Response(JSON.stringify({
            success: false,
            error: 'Not Found'
          }), {
            status: 404,
            headers: { 'Content-Type': 'application/json' }
          });
      }
    } catch (err: any) {
      console.error('API Error:', err.message);
      return new Response(JSON.stringify({
        success: false,
        error: 'Internal Server Error',
        details: err.message
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  },
} satisfies ExportedHandler<Env>;
