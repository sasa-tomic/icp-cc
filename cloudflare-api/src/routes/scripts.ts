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
      is_public = true,
      author_principal,
      author_public_key,
      signature
    } = await request.json();

    // Validate required fields
    if (!title || !description || !category || !lua_source || !author_name) {
      return JsonResponse.error(
        'Missing required fields: title, description, category, lua_source, author_name',
        400
      );
    }

    const now = new Date().toISOString();

    // Calculate SHA256 hash of the script content + timestamp to ensure uniqueness
    const timestamp = Date.now().toString();
    const scriptContent = `${title}|${description}|${category}|${lua_source}|${author_name}|${version}|${timestamp}`;
    const encoder = new TextEncoder();
    const data = encoder.encode(scriptContent);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const scriptId = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    const database = db.getDatabase();

    // TODO: Implement signature verification if provided
    if (signature && author_principal && author_public_key) {
      console.log('Signature verification requested for script creation:', {
        scriptId,
        authorPrincipal: author_principal,
        signature: signature?.substring(0, 20) + '...',
        hasPublicKey: !!author_public_key
      });

      // In a production implementation, you would verify the signature here
      // For now, we'll store the signature and public key for later verification
    }

    await database.prepare(`
      INSERT INTO scripts (
        id, title, description, category, tags, lua_source, author_name, author_id,
        author_principal, author_public_key, upload_signature, canister_ids, icon_url,
        screenshots, version, compatibility, price, is_public, downloads, rating,
        review_count, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      scriptId,
      title,
      description,
      category,
      JSON.stringify(tags || []),
      lua_source,
      author_name,
      'anonymous', // In a real app, this would come from authentication
      author_principal || null,
      author_public_key || null,
      signature || null,
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

    const script = await db.getScriptWithDetails(scriptId, true);

    console.log('Script created successfully:', { scriptId, title, isPublic: is_public, hasSignature: !!signature });

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
    const isPublic = url.searchParams.get('public') === 'true';

    const searchParams: any = {
      limit,
      offset,
      sortBy: 'created_at',
      order: 'desc'
    };

    if (isPublic) {
      searchParams.isPublic = true;
    }

    const { scripts, total } = await db.searchScripts(searchParams);

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
  const url = new URL(request.url);
  const includePrivate = url.searchParams.get('includePrivate') === 'true';

  switch (request.method) {
    case 'GET':
      return getScript(id, db, includePrivate);
    case 'PUT':
      return updateScript(id, request, db);
    case 'DELETE':
      return deleteScript(id, request, db);
    default:
      return JsonResponse.error('Method not allowed', 405);
  }
}

export async function handleScriptsCountRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const database = db.getDatabase();
    
    const result = await database.prepare(`
      SELECT COUNT(*) as count FROM scripts
    `).first();

    const count = result?.count as number || 0;

    return JsonResponse.success({ count });
  } catch (err: any) {
    console.error('Get scripts count failed:', err.message);
    return JsonResponse.error('Failed to get scripts count', 500, err.message);
  }
}

export async function handlePublishScriptRequest(request: Request, env: Env, id: string): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const db = new DatabaseService(env);
    const database = db.getDatabase();
    
    // Check if script exists
    const existingScript = await database.prepare(`
      SELECT id FROM scripts WHERE id = ?
    `).bind(id).first();

    if (!existingScript) {
      return JsonResponse.error('Script not found', 404);
    }

    // Update script to make it public
    const now = new Date().toISOString();
    const result = await database.prepare(`
      UPDATE scripts SET is_public = 1, updated_at = ? WHERE id = ?
    `).bind(now, id).run();

    if (result.changes === 0) {
      return JsonResponse.error('Failed to publish script', 500);
    }

    const script = await db.getScriptWithDetails(id, true);
    
    return JsonResponse.success(script);
  } catch (err: any) {
    console.error('Publish script failed:', err.message);
    return JsonResponse.error('Failed to publish script', 500, err.message);
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

async function getScript(id: string, db: DatabaseService, includePrivate = false): Promise<Response> {
  try {
    if (!id) {
      return JsonResponse.error('Script ID is required', 400);
    }

    const script = await db.getScriptWithDetails(id, includePrivate);

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

    // Check if signature and author_principal are provided
    if (!updateData.signature || !updateData.author_principal) {
      return JsonResponse.error('Signature and author_principal are required for script updates', 401);
    }

    // Get the existing script to verify ownership
    const database = db.getDatabase();
    const existingScript = await database.prepare(`
      SELECT author_principal, author_public_key FROM scripts WHERE id = ?
    `).bind(id).first();

    if (!existingScript) {
      return JsonResponse.error('Script not found', 404);
    }

    // Verify that the author_principal matches the existing script's author
    if (updateData.author_principal !== existingScript.author_principal) {
      return JsonResponse.error('Author principal does not match script author', 403);
    }

    // TODO: Implement proper signature verification using stored public key
    if (existingScript.author_public_key) {
      console.log('Signature verification requested for script update:', {
        scriptId: id,
        authorPrincipal: updateData.author_principal,
        hasStoredPublicKey: !!existingScript.author_public_key,
        signature: updateData.signature?.substring(0, 20) + '...'
      });

      // In a production implementation, you would:
      // 1. Create the canonical payload for verification
      // 2. Verify the signature using the stored public key
      // 3. Only proceed if verification succeeds

      // For now, we'll log the verification request and proceed
      console.log('Signature verification would be performed here with stored public key');
    } else {
      console.warn('No public key stored for script, cannot verify signature:', id);
    }

    // Build dynamic update query (excluding signature from database update)
    const updateFields = [];
    const bindings = [];

    Object.entries(updateData).forEach(([key, value]) => {
      if (key === 'tags' || key === 'canister_ids' || key === 'screenshots') {
        updateFields.push(`${key} = ?`);
        bindings.push(JSON.stringify(value));
      } else if (key === 'is_public') {
        updateFields.push(`${key} = ?`);
        bindings.push(value ? 1 : 0);
      } else if (key !== 'id' && key !== 'created_at' && key !== 'signature' && key !== 'timestamp') {
        updateFields.push(`${key} = ?`);
        bindings.push(value);
      }
    });

    // Update author_principal if provided
    if (updateData.author_principal) {
      updateFields.push('author_principal = ?');
      bindings.push(updateData.author_principal);
    }

    updateFields.push('updated_at = ?');
    bindings.push(now, id);

    await database.prepare(`
      UPDATE scripts SET ${updateFields.join(', ')} WHERE id = ?
    `).bind(...bindings).run();

    const script = await db.getScriptWithDetails(id, true);

    if (!script) {
      return JsonResponse.error('Script not found', 404);
    }

    return JsonResponse.success(script);
  } catch (err: any) {
    console.error('Update script failed:', err.message);
    return JsonResponse.error('Failed to update script', 500, err.message);
  }
}

async function deleteScript(id: string, request: Request, db: DatabaseService): Promise<Response> {
  try {
    if (!id) {
      return JsonResponse.error('Script ID is required', 400);
    }

    const deleteData = await request.json();

    // Check if signature and author_principal are provided
    if (!deleteData.signature || !deleteData.author_principal) {
      return JsonResponse.error('Signature and author_principal are required for script deletion', 401);
    }

    // Get the existing script to verify ownership
    const database = db.getDatabase();
    const existingScript = await database.prepare(`
      SELECT author_principal, author_public_key FROM scripts WHERE id = ?
    `).bind(id).first();

    if (!existingScript) {
      return JsonResponse.error('Script not found', 404);
    }

    // Verify that the author_principal matches the existing script's author
    if (deleteData.author_principal !== existingScript.author_principal) {
      return JsonResponse.error('Author principal does not match script author', 403);
    }

    // TODO: Implement proper signature verification using stored public key
    if (existingScript.author_public_key) {
      console.log('Signature verification requested for script deletion:', {
        scriptId: id,
        authorPrincipal: deleteData.author_principal,
        hasStoredPublicKey: !!existingScript.author_public_key,
        signature: deleteData.signature?.substring(0, 20) + '...'
      });

      // In a production implementation, you would:
      // 1. Create the canonical payload for verification
      // 2. Verify the signature using the stored public key
      // 3. Only proceed if verification succeeds

      // For now, we'll log the verification request and proceed
      console.log('Signature verification would be performed here with stored public key');
    } else {
      console.warn('No public key stored for script, cannot verify signature:', id);
    }

    const result = await database.prepare(`
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