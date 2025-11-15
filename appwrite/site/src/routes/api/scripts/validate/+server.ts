import type { RequestHandler } from './$types';

// Simple Lua syntax validation
function validateLuaSyntax(luaSource: string): { isValid: boolean; errors: string[]; warnings: string[] } {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Basic syntax checks
  if (!luaSource || luaSource.trim().length === 0) {
    errors.push('Lua source code cannot be empty');
    return { isValid: false, errors, warnings };
  }

  // Check for balanced parentheses
  let parenCount = 0;
  let bracketCount = 0;
  let braceCount = 0;

  for (let i = 0; i < luaSource.length; i++) {
    const char = luaSource[i];

    if (char === '(') parenCount++;
    else if (char === ')') parenCount--;
    else if (char === '[') bracketCount++;
    else if (char === ']') bracketCount--;
    else if (char === '{') braceCount++;
    else if (char === '}') braceCount--;

    if (parenCount < 0) {
      errors.push(`Unmatched closing parenthesis at position ${i}`);
      parenCount = 0;
    }
    if (bracketCount < 0) {
      errors.push(`Unmatched closing bracket at position ${i}`);
      bracketCount = 0;
    }
    if (braceCount < 0) {
      errors.push(`Unmatched closing brace at position ${i}`);
      braceCount = 0;
    }
  }

  if (parenCount > 0) errors.push(`Unmatched opening parentheses: ${parenCount}`);
  if (bracketCount > 0) errors.push(`Unmatched opening brackets: ${bracketCount}`);
  if (braceCount > 0) errors.push(`Unmatched opening braces: ${braceCount}`);

  // Check for basic Lua keywords and structure
  const lines = luaSource.split('\n');
  let hasFunction = false;
  let hasEnd = false;

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('function ') || trimmed.includes('function ')) {
      hasFunction = true;
    }
    if (trimmed === 'end') {
      hasEnd = true;
    }
  }

  if (hasFunction && !hasEnd) {
    warnings.push('Function found but no "end" statement detected');
  }

  // Check for potential security issues
  const dangerousPatterns = [
    /os\.execute/i,
    /io\.popen/i,
    /loadstring/i,
    /dofile/i,
    /require/i
  ];

  for (const pattern of dangerousPatterns) {
    if (pattern.test(luaSource)) {
      warnings.push(`Potentially dangerous function detected: ${pattern.source}`);
    }
  }

  // Basic size check
  if (luaSource.length > 100000) { // 100KB
    warnings.push('Large script size may impact performance');
  }

  return {
    isValid: errors.length === 0,
    errors,
    warnings
  };
}

export const POST: RequestHandler = async ({ request }) => {
  try {
    const { lua_source } = await request.json();

    if (!lua_source) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Lua source code is required'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const validation = validateLuaSyntax(lua_source);

    return new Response(JSON.stringify({
      success: true,
      data: validation
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err: any) {
    console.error('Script validation failed:', err.message);

    return new Response(JSON.stringify({
      success: false,
      error: 'Script validation failed',
      details: err.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};