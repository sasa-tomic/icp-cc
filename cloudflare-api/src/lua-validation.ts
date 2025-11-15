/**
 * Lua validation using luaparse exclusively
 * Provides comprehensive syntax checking and security validation
 */

interface ValidationResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
  functions: string[];
  missingFunctions: string[];
  syntaxValid: boolean;
  stats: {
    lines: number;
    characters: number;
    functions: number;
  };
}

export async function validateLuaScript(luaSource: string): Promise<ValidationResult> {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Basic validation
  if (!luaSource || luaSource.trim().length === 0) {
    errors.push('Lua source cannot be empty');
    return {
      isValid: false,
      errors,
      warnings,
      functions: [],
      missingFunctions: ['init', 'view', 'update'],
      syntaxValid: false,
      stats: { lines: 0, characters: 0, functions: 0 }
    };
  }

  // Always parse with luaparse for syntax validation - no fallbacks
  try {
    const luaparse = await import('luaparse');
    const ast = luaparse.parse(luaSource);
    const functions = extractFunctionsFromAst(ast);

    // Check required functions
    const requiredFunctions = ['init', 'view', 'update'];
    const missingFunctions = requiredFunctions.filter(func => !functions.has(func));

    if (missingFunctions.length > 0) {
      errors.push(`Missing required functions: ${missingFunctions.join(', ')}`);
    }

    // Security validation
    const securityIssues = checkSecurityPatterns(luaSource);
    errors.push(...securityIssues.errors);
    warnings.push(...securityIssues.warnings);

    return {
      isValid: errors.length === 0 && missingFunctions.length === 0,
      errors,
      warnings,
      functions: Array.from(functions),
      missingFunctions,
      syntaxValid: true,
      stats: {
        lines: luaSource.split('\n').length,
        characters: luaSource.length,
        functions: functions.size
      }
    };

  } catch (parseError: any) {
    errors.push(`Syntax error: ${parseError.message}`);

    // Still check for security patterns even if syntax is invalid
    const securityIssues = checkSecurityPatterns(luaSource);
    errors.push(...securityIssues.errors);
    warnings.push(...securityIssues.warnings);

    return {
      isValid: false,
      errors,
      warnings,
      functions: [],
      missingFunctions: ['init', 'view', 'update'],
      syntaxValid: false,
      stats: {
        lines: luaSource.split('\n').length,
        characters: luaSource.length,
        functions: 0
      }
    };
  }
}

function checkSecurityPatterns(luaSource: string) {
  const errors: string[] = [];
  const warnings: string[] = [];

  const securityPatterns = [
    // Critical security violations (errors)
    { pattern: /loadstring\s*\(/, type: 'error', message: 'loadstring() function detected - potential security risk' },
    { pattern: /dofile\s*\(/, type: 'error', message: 'dofile() function detected - potential security risk' },
    { pattern: /os\.execute/, type: 'error', message: 'os.execute() - system execution not allowed' },
    { pattern: /os\.remove/, type: 'error', message: 'os.remove() - file system access not allowed' },
    { pattern: /os\.rename/, type: 'error', message: 'os.rename() - file system access not allowed' },
    { pattern: /debug\.getregistry/, type: 'error', message: 'debug.getregistry() - debugging functions not allowed' },

    // Questionable patterns (warnings)
    { pattern: /io\.open/, type: 'warning', message: 'io.open() - file system access not available in sandboxed environment' },
    { pattern: /io\.popen/, type: 'warning', message: 'io.popen() - process execution not available in sandboxed environment' },
    { pattern: /loadfile/, type: 'warning', message: 'loadfile() - file loading not available in sandboxed environment' },
    { pattern: /require\s*\(/, type: 'warning', message: 'require() - module loading may not work in sandboxed environment' },
    { pattern: /package\./, type: 'warning', message: 'package library - module system may not work in sandboxed environment' },
    { pattern: /collectgarbage/, type: 'warning', message: 'collectgarbage() - memory management may be restricted' }
  ];

  for (const { pattern, type, message } of securityPatterns) {
    if (pattern.test(luaSource)) {
      if (type === 'error') {
        errors.push(message);
      } else {
        warnings.push(message);
      }
    }
  }

  return { errors, warnings };
}

function extractFunctionsFromAst(ast: any): Set<string> {
  const functions = new Set<string>();

  function traverse(node: any) {
    if (!node) return;

    if (node.type === 'FunctionDeclaration') {
      functions.add(node.identifier?.name || 'anonymous');
    }

    if (node.body) {
      if (Array.isArray(node.body)) {
        node.body.forEach(traverse);
      } else {
        traverse(node.body);
      }
    }

    if (node.arguments) {
      node.arguments.forEach(traverse);
    }

    if (node.parameters) {
      node.parameters.forEach(traverse);
    }
  }

  if (ast.body) {
    ast.body.forEach(traverse);
  }

  return functions;
}

// Simple export for direct usage
export { validateLuaScript as validateLua };