import { Env } from '../types';
import { JsonResponse } from '../utils';

interface LuaValidationResult {
  isSyntaxValid: boolean;
  hasRequiredFunctions: boolean;
  syntaxError?: string;
  missingFunctions: string[];
}

function validateLuaWithPatterns(lua_source: string): LuaValidationResult {
  const missingFunctions: string[] = [];
  const syntaxErrors: string[] = [];

  // Basic syntax validation using patterns
  const lines = lua_source.split('\n');
  let inString = false;
  let stringChar = '';
  let commentDepth = 0;
  let braceCount = 0;
  let parenCount = 0;
  let bracketCount = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Skip empty lines and comments
    if (trimmed === '' || trimmed.startsWith('--')) {
      continue;
    }

    // Check for basic syntax issues
    for (let j = 0; j < line.length; j++) {
      const char = line[j];
      const prevChar = j > 0 ? line[j - 1] : '';

      // Handle strings
      if (!inString && (char === '"' || char === "'")) {
        inString = true;
        stringChar = char;
      } else if (inString && char === stringChar && prevChar !== '\\') {
        inString = false;
        stringChar = '';
      }

      // Count brackets outside of strings
      if (!inString) {
        if (char === '{') braceCount++;
        else if (char === '}') braceCount--;
        else if (char === '(') parenCount++;
        else if (char === ')') parenCount--;
        else if (char === '[') bracketCount++;
        else if (char === ']') bracketCount--;
      }
    }

    // Check for basic syntax errors
    if (!inString) {
      // Unclosed brackets at line end might indicate syntax issues
      if (braceCount < 0 || parenCount < 0 || bracketCount < 0) {
        syntaxErrors.push(`Line ${i + 1}: Unmatched closing bracket`);
        break;
      }
    }
  }

  // Check for unmatched opening brackets
  if (braceCount !== 0) syntaxErrors.push('Unmatched braces {}');
  if (parenCount !== 0) syntaxErrors.push('Unmatched parentheses ()');
  if (bracketCount !== 0) syntaxErrors.push('Unmatched brackets []');

  // Check for required functions using pattern matching
  const requiredFunctions = ['init', 'view', 'update'];

  for (const funcName of requiredFunctions) {
    // Look for function definition: function name( or function name (
    const functionPattern = new RegExp(`function\\s+${funcName}\\s*\\(`, 'm');
    if (!functionPattern.test(lua_source)) {
      missingFunctions.push(funcName);
    }
  }

  // Additional syntax checks
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

  // Check for basic Lua syntax errors
  if (syntaxErrors.length === 0) {
    // Check for common syntax mistakes
    const commonErrors = [
      { pattern: /function\s+\w+\s*[^(\s]/, message: 'Invalid function definition - missing parentheses' },
      { pattern: /\bif\b.*\bthen\b\s*$/m, message: 'Incomplete if statement' },
      { pattern: /\bthen\b.*\belse\b.*\bthen\b/m, message: 'Invalid if-else structure' },
      { pattern: /\bfor\b.*\bdo\b\s*$/m, message: 'Incomplete for loop' },
      { pattern: /\bwhile\b.*\bdo\b\s*$/m, message: 'Incomplete while loop' },
      { pattern: /\bdo\b.*\bend\b/m, message: 'Loop structure without proper closing' },
    ];

    for (const { pattern, message } of commonErrors) {
      if (pattern.test(lua_source)) {
        syntaxErrors.push(message);
      }
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
    const { lua_source } = await request.json();

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

    // Use lightweight pattern-based validation
    const vmResult = validateLuaWithPatterns(lua_source);

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