import { Env } from '../types';
import { JsonResponse } from '../utils';

export async function handleScriptValidationRequest(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return JsonResponse.error('Method not allowed', 405);
  }

  try {
    const { lua_source } = await request.json();

    if (lua_source === undefined || lua_source === null || typeof lua_source !== 'string') {
      return JsonResponse.error('lua_source is required and must be a string', 400);
    }

    const errors: string[] = [];
    const warnings: string[] = [];

    // Basic validation
    if (lua_source.trim().length === 0) {
      errors.push('Lua source cannot be empty');
    }

    // Check for potentially dangerous functions
    const dangerousPatterns = [
      { pattern: /os\.execute/, message: 'os.execute() - potentially dangerous system call' },
      { pattern: /io\.open/, message: 'io.open() - file system access not allowed' },
      { pattern: /io\.popen/, message: 'io.popen() - process execution not allowed' },
      { pattern: /dofile/, message: 'dofile() - file loading not allowed' },
      { pattern: /loadfile/, message: 'loadfile() - file loading not allowed' },
      { pattern: /require/, message: 'require() - module loading not allowed' },
      { pattern: /debug\.getregistry/, message: 'debug.getregistry() - debug access not allowed' },
      { pattern: /package\.loadlib/, message: 'package.loadlib() - library loading not allowed' },
    ];

    for (const { pattern, message } of dangerousPatterns) {
      if (pattern.test(lua_source)) {
        warnings.push(message);
      }
    }

    // Check for basic Lua syntax errors (simple checks)
    const lines = lua_source.split('\n');
    let openBraces = 0;
    let openParens = 0;
    let openBrackets = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      
      // Skip comments and empty lines
      if (line.startsWith('--') || line === '') continue;

      // Count brackets
      for (const char of line) {
        if (char === '{') openBraces++;
        else if (char === '}') openBraces--;
        else if (char === '(') openParens++;
        else if (char === ')') openParens--;
        else if (char === '[') openBrackets++;
        else if (char === ']') openBrackets--;
      }

      // Check for unclosed brackets at end of line
      if (openBraces < 0) errors.push(`Unmatched closing brace on line ${i + 1}`);
      if (openParens < 0) errors.push(`Unmatched closing parenthesis on line ${i + 1}`);
      if (openBrackets < 0) errors.push(`Unmatched closing bracket on line ${i + 1}`);
    }

    // Check for unclosed brackets at end of file
    if (openBraces > 0) errors.push(`${openBraces} unclosed brace(s)`);
    if (openParens > 0) errors.push(`${openParens} unclosed parenthesis(es)`);
    if (openBrackets > 0) errors.push(`${openBrackets} unclosed bracket(s)`);

    // Check for common Lua patterns
    if (!/function\s+\w+/.test(lua_source) && !/local\s+function\s+\w+/.test(lua_source)) {
      warnings.push('No function definitions found - script may not be executable');
    }

    if (!/return/.test(lua_source)) {
      warnings.push('No return statement found - script may not produce output');
    }

    // Check for ICP-specific patterns
    if (!/icp_/.test(lua_source)) {
      warnings.push('No ICP-specific functions found - script may not interact with canisters');
    }

    const result = {
      is_valid: errors.length === 0,
      errors,
      warnings,
      line_count: lines.length,
      character_count: lua_source.length,
    };

    return JsonResponse.success(result);
  } catch (err: any) {
    console.error('Script validation failed:', err.message);
    return JsonResponse.error('Script validation failed', 500, err.message);
  }
}