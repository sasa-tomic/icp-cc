import { Env } from '../types';
import { JsonResponse } from '../utils';

function validateRequiredFunctions(lua_source: string, errors: string[], warnings: string[]) {
  // Check for required functions
  const requiredFunctions = ['init', 'view', 'update'];
  for (const func of requiredFunctions) {
    const functionPattern = new RegExp(`function\\s+${func}\\s*\\([^)]*\\)`, 'i');
    if (!functionPattern.test(lua_source)) {
      errors.push(`Required function '${func}' not found - script will not execute properly`);
    }
  }
  
  // Validate function signatures
  const initMatch = lua_source.match(/function\s+init\s*\([^)]*\)/i);
  if (initMatch && initMatch[0].includes(',')) {
    errors.push('init() function should accept at most one parameter (arg)');
  }
  
  const viewMatch = lua_source.match(/function\s+view\s*\([^)]*\)/i);
  if (!viewMatch || !viewMatch[0].includes('state')) {
    warnings.push('view() function should accept a state parameter');
  }
  
  const updateMatch = lua_source.match(/function\s+update\s*\([^)]*\)/i);
  if (!updateMatch || !updateMatch[0].includes('msg') || !updateMatch[0].includes('state')) {
    warnings.push('update() function should accept msg and state parameters');
  }
}

function validateEventHandlers(lua_source: string, errors: string[], warnings: string[]) {
  // Extract event handlers from UI definitions
  const eventHandlerPattern = /on_(press|change|submit|input)\s*=\s*\{\s*type\s*:\s*["']([^"']+)["']/g;
  const eventHandlers: string[] = [];
  let match;
  
  while ((match = eventHandlerPattern.exec(lua_source)) !== null) {
    eventHandlers.push(match[2]);
  }
  
  // Extract message types from update function
  const messageTypePattern = /msg\.type\s*==\s*["']([^"']+)["']/g;
  const messageTypes: string[] = [];
  
  while ((match = messageTypePattern.exec(lua_source)) !== null) {
    messageTypes.push(match[1]);
  }
  
  // Check for unhandled events
  for (const handler of eventHandlers) {
    if (!messageTypes.includes(handler)) {
      warnings.push(`Event handler '${handler}' has no corresponding case in update() function`);
    }
  }
  
  // Check for orphaned message handlers
  for (const messageType of messageTypes) {
    if (!eventHandlers.includes(messageType) && !messageType.startsWith('effect/')) {
      warnings.push(`Message handler '${messageType}' has no corresponding UI event handler`);
    }
  }
}

function validateICPIntegration(lua_source: string, errors: string[], warnings: string[]) {
  // Validate canister ID patterns
  const canisterIdPattern = /canister_id\s*=\s*["']([^"']+)["']/g;
  let match;
  
  while ((match = canisterIdPattern.exec(lua_source)) !== null) {
    const canisterId = match[1];
    // Basic canister ID validation (ICP canister IDs follow specific patterns)
    if (!/^[a-z0-9-]{27,63}$/.test(canisterId) || !canisterId.includes('-')) {
      errors.push(`Invalid canister ID format: ${canisterId}. Expected format: xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxx-xxx`);
    }
  }
  
  // Validate effect handling
  const effectCallPattern = /kind\s*=\s*["']icp_call["']/g;
  const hasEffectCalls = effectCallPattern.test(lua_source);
  
  if (hasEffectCalls) {
    const effectHandlerPattern = /effect\/result/i;
    if (!effectHandlerPattern.test(lua_source)) {
      errors.push('Script uses ICP calls but missing effect/result handler in update() function');
    }
  }
  
  // Validate canister call structure
  const canisterCallPattern = /\{\s*canister_id\s*:\s*["'][^"']+["'][^}]*method\s*:\s*["'][^"']+["'][^}]*kind\s*:\s*\d+/g;
  const calls = lua_source.match(canisterCallPattern);
  
  if (calls) {
    for (const call of calls) {
      if (!call.includes('args')) {
        warnings.push('Canister call missing args field - may cause runtime errors');
      }
    }
  }
}

function validateUINodes(lua_source: string, errors: string[], warnings: string[]) {
  // Look for UI nodes with type field using Lua syntax
  // Only match type fields that are likely UI nodes (in return statements or function calls)
  const returnStatements = lua_source.match(/return\s*\{[\s\S]*?\}/g) || [];
  const functionCalls = lua_source.match(/\w+\s*\([^)]*\)\s*\{[\s\S]*?\}/g) || [];
  
  const uiContexts = [...returnStatements, ...functionCalls];
  
  for (const context of uiContexts) {
    const typeMatches = context.match(/type\s*=\s*["']([^"']*)["']/g);
    
    if (typeMatches) {
      for (const typeMatch of typeMatches) {
        const type = typeMatch.match(/["']([^"']*)["']/)?.[1];
        if (!type || type.trim() === '') {
          errors.push('UI node with empty type found');
        }
      }
    }
  }
  
  // Look for conditional rendering patterns that might produce false values
  const conditionalPatterns = lua_source.match(/\w+\s+and\s*\{[^}]*\}/g);
  if (conditionalPatterns) {
    for (const pattern of conditionalPatterns) {
      // Check if the conditional might produce false instead of nil
      if (!pattern.includes('type')) {
        errors.push('Conditional UI expression missing type field - this will cause "UI node missing type" error');
      }
    }
  }
  
  // Check for common UI node types
  const validTypes = ['column', 'row', 'section', 'text', 'button', 'toggle', 'input'];
  const allTypeMatches = lua_source.match(/type\s*=\s*["']([^"']+)["']/g);
  
  if (allTypeMatches) {
    for (const typeMatch of allTypeMatches) {
      const type = typeMatch.match(/["']([^"']+)["']/)?.[1];
      if (type && !validTypes.includes(type)) {
        warnings.push(`Unknown UI node type: "${type}" - valid types are: ${validTypes.join(', ')}`);
      }
    }
  }
  
  // Look for table literals that might be UI nodes without type
  // This is a simple heuristic - look for tables in return statements
  const returnMatches = lua_source.match(/return\s*\{[\s\S]*?\}/g);
  if (returnMatches) {
    for (const match of returnMatches) {
      // Find nested tables that don't have type
      const nestedTables = match.match(/\{[^{}]*\}/g);
      if (nestedTables) {
        for (const table of nestedTables) {
          // Skip if this is a props or children table
          if (!table.includes('props') && !table.includes('children') && 
              table.includes('{') && table.includes('}') && !table.includes('type')) {
            // Check if this looks like a UI node (has other UI properties)
            if (table.includes('props') || table.includes('children')) {
              errors.push('UI node missing type field');
  }
}
        }
      }
    }
  }
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

    // Check for basic Lua syntax errors (improved checks)
    const lines = lua_source.split('\n');
    let openBraces = 0;
    let openParens = 0;
    let openBrackets = 0;
    let inString = false;
    let stringChar = '';
    let inComment = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      
      // Reset comment state for each line
      inComment = false;
      
      for (let j = 0; j < line.length; j++) {
        const char = line[j];
        const prevChar = j > 0 ? line[j - 1] : '';
        
        // Handle comments
        if (!inString && !inComment && char === '-' && prevChar === '-') {
          inComment = true;
          break; // Skip rest of line
        }
        
        // Handle strings
        if (!inComment) {
          if (!inString && (char === '"' || char === "'")) {
            inString = true;
            stringChar = char;
          } else if (inString && char === stringChar && prevChar !== '\\') {
            inString = false;
            stringChar = '';
          }
        }
        
        // Count brackets only when not in strings or comments
        if (!inString && !inComment) {
          if (char === '{') openBraces++;
          else if (char === '}') openBraces--;
          else if (char === '(') openParens++;
          else if (char === ')') openParens--;
          else if (char === '[') openBrackets++;
          else if (char === ']') openBrackets--;
          
          // Check for immediate unmatched closing
          if (openBraces < 0) {
            errors.push(`Unmatched closing brace on line ${i + 1}`);
            openBraces = 0;
          }
          if (openParens < 0) {
            errors.push(`Unmatched closing parenthesis on line ${i + 1}`);
            openParens = 0;
          }
          if (openBrackets < 0) {
            errors.push(`Unmatched closing bracket on line ${i + 1}`);
            openBrackets = 0;
          }
        }
      }
    }

    // Check for unclosed brackets at end of file
    if (openBraces > 0) errors.push(`${openBraces} unclosed brace(s) at end of file`);
    if (openParens > 0) errors.push(`${openParens} unclosed parenthesis(es) at end of file`);
    if (openBrackets > 0) errors.push(`${openBrackets} unclosed bracket(s) at end of file`);

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

    // Static validations
    validateUINodes(lua_source, errors, warnings);
    validateRequiredFunctions(lua_source, errors, warnings);
    validateEventHandlers(lua_source, errors, warnings);
    validateICPIntegration(lua_source, errors, warnings);

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