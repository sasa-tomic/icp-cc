import { Env } from './types';
import { JsonResponse, DatabaseService } from '../utils';

export async function handleSearchScriptsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const {
      query,
      category,
      canisterId,
      minRating,
      maxPrice,
      sortBy = 'created_at',
      order = 'desc',
      limit = 20,
      offset = 0
    } = await request.json();

    const { scripts, total } = await db.searchScripts({
      query,
      category,
      canisterId,
      minRating,
      maxPrice,
      sortBy,
      order,
      limit,
      offset
    });

    return JsonResponse.success({
      scripts,
      total,
      hasMore: offset + limit < total
    });
  } catch (err: any) {
    console.error('Search scripts failed:', err.message);
    return JsonResponse.error('Search failed', 500, err.message);
  }
}

export async function handleTrendingScriptsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const url = new URL(request.url);
    const limit = parseInt(url.searchParams.get('limit') || '10');

    const { scripts } = await db.searchScripts({
      limit,
      sortBy: 'downloads',
      order: 'desc'
    });

    return JsonResponse.success(scripts);
  } catch (err: any) {
    console.error('Get trending scripts failed:', err.message);
    return JsonResponse.error('Failed to get trending scripts', 500, err.message);
  }
}

export async function handleFeaturedScriptsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const url = new URL(request.url);
    const limit = parseInt(url.searchParams.get('limit') || '10');

    const { scripts } = await db.searchScripts({
      minRating: 4.0,
      limit,
      sortBy: 'rating',
      order: 'desc'
    });

    return JsonResponse.success(scripts);
  } catch (err: any) {
    console.error('Get featured scripts failed:', err.message);
    return JsonResponse.error('Failed to get featured scripts', 500, err.message);
  }
}

export async function handleCompatibleScriptsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const { canisterId, limit = 20, offset = 0 } = await request.json();

    if (!canisterId) {
      return JsonResponse.error('Canister ID is required', 400);
    }

    const { scripts, total } = await db.searchScripts({
      canisterId,
      limit,
      offset,
      sortBy: 'rating',
      order: 'desc'
    });

    return JsonResponse.success({
      scripts,
      total,
      hasMore: offset + limit < total
    });
  } catch (err: any) {
    console.error('Get compatible scripts failed:', err.message);
    return JsonResponse.error('Failed to get compatible scripts', 500, err.message);
  }
}