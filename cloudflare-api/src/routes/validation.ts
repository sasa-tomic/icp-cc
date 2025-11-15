import { Env } from '../types';
import { JsonResponse } from '../utils';
import { validateLua } from '../lua-validation';

interface LuaValidationRequest {
  lua_source: string;
}

export async function handleScriptValidationRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const { lua_source } = await request.json() as LuaValidationRequest;

    if (lua_source === undefined || lua_source === null || typeof lua_source !== 'string') {
      return JsonResponse.error('lua_source is required and must be a string', 400);
    }

    // Always use luaparse validation - no mode selection
    console.log('Validating Lua script with luaparse...');

    const validationResult = await validateLua(lua_source);

    // Format response to match existing API structure
    const result = {
      is_valid: validationResult.isValid,
      errors: validationResult.errors,
      warnings: validationResult.warnings,
      line_count: validationResult.stats.lines,
      character_count: validationResult.stats.characters,
      vm_validation: {
        syntax_valid: validationResult.syntaxValid,
        has_required_functions: validationResult.missingFunctions.length === 0,
        missing_functions: validationResult.missingFunctions,
        validation_method: 'luaparse',
        functions_found: validationResult.functions,
        function_count: validationResult.stats.functions
      }
    };

    return JsonResponse.success(result);
  } catch (err: any) {
    console.error('Script validation failed:', err.message);
    return JsonResponse.error('Script validation failed', 500, err.message);
  }
}
