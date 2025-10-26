import { Env, Script } from './types';
import { JsonResponse, DatabaseService } from '../utils';

export async function handleScriptsRequest(request: Request, env: Env): Promise<Response> {
  const db = new DatabaseService(env);
  const url = new URL(request.url);

  switch (request.method) {
    case 'POST':
      return createScript(request, db);
    case 'GET':
      return getScripts(url, db);
    default:
      return JsonResponse.error('Method not allowed', 405);
  }
}

async function createScript(request: Request, db: DatabaseService): Promise<Response> {
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
      is_public = true
    } = await request.json();

    // Validate required fields
    if (!title || !description || !category || !lua_source || !author_name) {
      return JsonResponse.error(
        'Missing required fields: title, description, category, lua_source, author_name',
        400
      );
    }

    const now = new Date().toISOString();
    
    // Calculate SHA256 hash of the script content to use as identifier
    const scriptContent = `${title}|${description}|${category}|${lua_source}|${author_name}|${version}`;
    const encoder = new TextEncoder();
    const data = encoder.encode(scriptContent);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const scriptId = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    await db.env.DB.prepare(`
      INSERT INTO scripts (
        id, title, description, category, tags, lua_source, author_name, author_id,
        canister_ids, icon_url, screenshots, version, compatibility, price,
        is_public, downloads, rating, review_count, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      scriptId,
      title,
      description,
      category,
      JSON.stringify(tags || []),
      lua_source,
      author_name,
      'anonymous', // In a real app, this would come from authentication
      JSON.stringify(canister_ids || []),
      icon_url || null,
      JSON.stringify(screenshots || []),
      version,
      compatibility || null,
      price,
      is_public ? 1 : 0,
      0,
      0,
      0,
      now,
      now
    ).run();

    const script = await db.getScriptWithDetails(scriptId);
    
    console.log('Script created successfully:', { scriptId, title, isPublic: is_public });

    return JsonResponse.success(script, 201);
  } catch (err: any) {
    console.error('Create script failed:', err.message);
    return JsonResponse.error('Failed to create script', 500, err.message);
  }
}

async function getScripts(url: URL, db: DatabaseService): Promise<Response> {
  try {
    const limit = parseInt(url.searchParams.get('limit') || '20');
    const offset = parseInt(url.searchParams.get('offset') || '0');

    const { scripts, total } = await db.searchScripts({
      limit,
      offset,
      sortBy: 'created_at',
      order: 'desc'
    });

    return JsonResponse.success({
      scripts,
      total,
      hasMore: offset + limit < total
    });
  } catch (err: any) {
    console.error('Get scripts failed:', err.message);
    return JsonResponse.error('Failed to get scripts', 500, err.message);
  }
}

export async function handleScriptByIdRequest(request: Request, env: Env, id: string): Promise<Response> {
  const db = new DatabaseService(env);

  switch (request.method) {
    case 'GET':
      return getScript(id, db);
    case 'PUT':
      return updateScript(id, request, db);
    case 'DELETE':
      return deleteScript(id, db);
    default:
      return JsonResponse.error('Method not allowed', 405);
  }
}

export async function handleScriptsByCategoryRequest(request: Request, env: Env, category: string): Promise<Response> {
  if (request.method !== 'GET') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const url = new URL(request.url);
    const limit = parseInt(url.searchParams.get('limit') || '20');
    const offset = parseInt(url.searchParams.get('offset') || '0');
    const sortBy = url.searchParams.get('sort_by') || 'rating';
    const sortOrder = url.searchParams.get('sort_order') || 'desc';

    const { scripts, total } = await db.searchScripts({
      category,
      limit,
      offset,
      sortBy,
      order: sortOrder
    });

    return JsonResponse.success(scripts);
  } catch (err: any) {
    console.error('Get scripts by category failed:', err.message);
    return JsonResponse.error('Failed to get scripts by category', 500, err.message);
  }
}

async function getScript(id: string, db: DatabaseService): Promise<Response> {
  try {
    if (!id) {
      return JsonResponse.error('Script ID is required', 400);
    }

    const script = await db.getScriptWithDetails(id);

    if (!script) {
      return JsonResponse.error('Script not found', 404);
    }

    return JsonResponse.success(script);
  } catch (err: any) {
    console.error('Get script failed:', err.message);
    return JsonResponse.error('Failed to get script', 500, err.message);
  }
}

async function updateScript(id: string, request: Request, db: DatabaseService): Promise<Response> {
  try {
    if (!id) {
      return JsonResponse.error('Script ID is required', 400);
    }

    const updateData = await request.json();
    const now = new Date().toISOString();

    // Build dynamic update query
    const updateFields = [];
    const bindings = [];

    Object.entries(updateData).forEach(([key, value]) => {
      if (key === 'tags' || key === 'canister_ids' || key === 'screenshots') {
        updateFields.push(`${key} = ?`);
        bindings.push(JSON.stringify(value));
      } else if (key === 'is_public') {
        updateFields.push(`${key} = ?`);
        bindings.push(value ? 1 : 0);
      } else if (key !== 'id' && key !== 'created_at') {
        updateFields.push(`${key} = ?`);
        bindings.push(value);
      }
    });

    updateFields.push('updated_at = ?');
    bindings.push(now, id);

    await db.env.DB.prepare(`
      UPDATE scripts SET ${updateFields.join(', ')} WHERE id = ?
    `).bind(...bindings).run();

    const script = await db.getScriptWithDetails(id);

    if (!script) {
      return JsonResponse.error('Script not found', 404);
    }

    return JsonResponse.success(script);
  } catch (err: any) {
    console.error('Update script failed:', err.message);
    return JsonResponse.error('Failed to update script', 500, err.message);
  }
}

async function deleteScript(id: string, db: DatabaseService): Promise<Response> {
  try {
    if (!id) {
      return JsonResponse.error('Script ID is required', 400);
    }

    const result = await db.env.DB.prepare(`
      DELETE FROM scripts WHERE id = ?
    `).bind(id).run();

    if (result.changes === 0) {
      return JsonResponse.error('Script not found', 404);
    }

    return JsonResponse.success({ message: 'Script deleted successfully' });
  } catch (err: any) {
    console.error('Delete script failed:', err.message);
    return JsonResponse.error('Failed to delete script', 500, err.message);
  }
}