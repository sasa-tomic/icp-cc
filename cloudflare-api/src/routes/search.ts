import { Env } from './types';
import { JsonResponse, DatabaseService } from '../utils';

export async function handleSearchScriptsRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET' && request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    let query, category, canisterId, minRating, maxPrice, sortBy, order, limit, offset;

    if (request.method === 'GET') {
      const url = new URL(request.url);
      query = url.searchParams.get('q');
      category = url.searchParams.get('category');
      canisterId = url.searchParams.get('canisterId');
      minRating = url.searchParams.get('minRating') != null ? parseFloat(url.searchParams.get('minRating')!) : undefined;
      maxPrice = url.searchParams.get('maxPrice') != null ? parseFloat(url.searchParams.get('maxPrice')!) : undefined;
      sortBy = url.searchParams.get('sortBy') || 'createdAt';
      order = url.searchParams.get('order') || 'desc';
      limit = parseInt(url.searchParams.get('limit') || '20');
      offset = parseInt(url.searchParams.get('offset') || '0');
    } else {
      const body = await request.json();
      query = body.query;
      category = body.category;
      canisterId = body.canisterId;
      minRating = body.minRating;
      maxPrice = body.maxPrice;
      sortBy = body.sortBy || 'createdAt';
      order = body.order || 'desc';
      limit = body.limit || 20;
      offset = body.offset || 0;
    }

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