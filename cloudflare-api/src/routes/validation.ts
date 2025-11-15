import { Env } from '../types';
import { JsonResponse } from '../utils';

// @ts-ignore - luaparse doesn't have TypeScript definitions
import luaparse from 'luaparse';

interface LuaValidationResult {
  isSyntaxValid: boolean;
  hasRequiredFunctions: boolean;
  syntaxError?: string;
  missingFunctions: string[];
}

function validateLuaWithLuaparse(lua_source: string): LuaValidationResult {
  const syntaxErrors: string[] = [];
  const missingFunctions: string[] = [];

  if (!luaparse || typeof luaparse.parse !== 'function') {
    throw new Error('Lua parser unavailable: luaparse.parse missing');
  }

  // Use luaparse for proper syntax validation
  const parseStartTime = Date.now();
  const PARSE_TIMEOUT_MS = 5000; // 5 second timeout

  try {
    const ast = luaparse.parse(lua_source, {
      // Configure luaparse to be more permissive and prevent hanging
      locations: true,
      ranges: true,
      strict: false
    });

    // Check if parsing took too long
    const parseTime = Date.now() - parseStartTime;
    if (parseTime > PARSE_TIMEOUT_MS) {
      syntaxErrors.push(`Lua parsing took too long (${parseTime}ms), possible infinite loop or complex syntax`);
      return {
        isSyntaxValid: false,
        hasRequiredFunctions: false,
        syntaxError: syntaxErrors.join('; '),
        missingFunctions
      };
    }

    // Extract function names from AST
    const functions = new Set<string>();

    function extractFunctions(node: any) {
      if (node.type === 'FunctionDeclaration' && node.identifier) {
        functions.add(node.identifier.name);
      }

      // Traverse child nodes
      if (node.body && Array.isArray(node.body)) {
        node.body.forEach(extractFunctions);
      }
      if (node.arguments && Array.isArray(node.arguments)) {
        node.arguments.forEach(extractFunctions);
      }
      if (node.init) {
        extractFunctions(node.init);
      }
      if (node.value) {
        extractFunctions(node.value);
      }
    }

    if (ast.body) {
      ast.body.forEach(extractFunctions);
    }

    // Check for required functions
    const requiredFunctions = ['init', 'view', 'update'];
    for (const funcName of requiredFunctions) {
      if (!functions.has(funcName)) {
        missingFunctions.push(funcName);
      }
    }

  } catch (error: any) {
    // luaparse throws detailed syntax errors with line numbers
    syntaxErrors.push(error.message || 'Lua syntax error');
  }

  // Security checks for dangerous patterns
  const dangerousPatterns = [
    { pattern: /loadstring\s*\(/, message: 'loadstring() function not allowed' },
    { pattern: /dofile\s*\(/, message: 'dofile() function not allowed' },
    { pattern: /os\.execute/, message: 'os.execute() not allowed' },
    { pattern: /io\.open/, message: 'io.open() not allowed' },
    { pattern: /io\.popen/, message: 'io.popen() not allowed' },
    { pattern: /loadfile\s*\(/, message: 'loadfile() not allowed' },
    { pattern: /require\s*\(/, message: 'require() not allowed' },
  ];

  for (const { pattern, message } of dangerousPatterns) {
    if (pattern.test(lua_source)) {
      syntaxErrors.push(message);
    }
  }

  return {
    isSyntaxValid: syntaxErrors.length === 0,
    hasRequiredFunctions: missingFunctions.length === 0,
    syntaxError: syntaxErrors.length > 0 ? syntaxErrors.join('; ') : undefined,
    missingFunctions
  };
}

export async function handleScriptValidationRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const { lua_source } = await request.json() as any;

    if (lua_source === undefined || lua_source === null || typeof lua_source !== 'string') {
      return JsonResponse.error('lua_source is required and must be a string', 400);
    }

    const errors: string[] = [];
    const warnings: string[] = [];

    // Basic validation
    if (lua_source.trim().length === 0) {
      errors.push('Lua source cannot be empty');
      return JsonResponse.success({
        is_valid: false,
        errors,
        warnings,
        line_count: 0,
        character_count: 0,
      });
    }

    // Critical security checks (always block these)
    const criticalSecurityPatterns = [
      { pattern: /loadstring\s*\(/, message: 'loadstring() function detected - potential security risk' },
      { pattern: /dofile\s*\(/, message: 'dofile() function detected - potential security risk' },
      { pattern: /os\.execute/, message: 'os.execute() - system execution not allowed' },
    ];

    for (const { pattern, message } of criticalSecurityPatterns) {
      if (pattern.test(lua_source)) {
        errors.push(message);
      }
    }

    // Use proper Lua parsing with luaparse
    const vmResult = validateLuaWithLuaparse(lua_source);

    // Add syntax errors if any
    if (!vmResult.isSyntaxValid) {
      errors.push(vmResult.syntaxError || 'Syntax error in Lua script');
    }

    // Add missing function errors
    for (const missingFunc of vmResult.missingFunctions) {
      errors.push(`Required function '${missingFunc}' not found - script will not execute properly`);
    }

    // Additional warnings for potentially problematic patterns
    const warningPatterns = [
      { pattern: /io\.open/, message: 'io.open() - file system access not allowed in sandboxed environment' },
      { pattern: /io\.popen/, message: 'io.popen() - process execution not allowed in sandboxed environment' },
      { pattern: /loadfile/, message: 'loadfile() - file loading not allowed in sandboxed environment' },
      { pattern: /require/, message: 'require() - module loading not allowed in sandboxed environment' },
    ];

    for (const { pattern, message } of warningPatterns) {
      if (pattern.test(lua_source)) {
        warnings.push(message);
      }
    }

    const result = {
      is_valid: errors.length === 0,
      errors,
      warnings,
      line_count: lua_source.split('\n').length,
      character_count: lua_source.length,
      vm_validation: {
        syntax_valid: vmResult.isSyntaxValid,
        has_required_functions: vmResult.hasRequiredFunctions,
        missing_functions: vmResult.missingFunctions,
      }
    };

    return JsonResponse.success(result);
  } catch (err: any) {
    console.error('Script validation failed:', err.message);
    return JsonResponse.error('Script validation failed', 500, err.message);
  }
}
