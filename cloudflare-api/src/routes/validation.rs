use crate::types::*;
use crate::utils::*;
use serde::Serialize;
use worker::{Request, Response, Result, Method};

pub async fn handle_script_validation_request(mut req: Request, _env: &AppEnv) -> Result<Response> {
    // Only accept POST requests for validation
    if req.method() != Method::Post {
        return Ok(JsonResponse::error("Method not allowed", 405));
    }

    // Parse request body
    let validation_data = match req.json::<serde_json::Value>().await {
        Ok(data) => data,
        Err(_) => return Ok(JsonResponse::error("Invalid JSON body", 400)),
    };

    let lua_source = match validation_data.get("luaSource").and_then(|v| v.as_str()) {
        Some(source) => source,
        None => return Ok(JsonResponse::error("luaSource is required", 400)),
    };

    if lua_source.is_empty() {
        return Ok(JsonResponse::error("luaSource cannot be empty", 400));
    }

    // Perform basic Lua syntax validation
    let validation_result = validate_lua_syntax(lua_source);

    let response_data = serde_json::json!({
        "valid": validation_result.is_valid,
        "message": validation_result.message,
        "line": validation_result.line,
        "column": validation_result.column,
        "securityChecks": validation_result.security_checks,
        "syntaxChecks": validation_result.syntax_checks
    });

    Ok(JsonResponse::success(response_data, 200))
}

#[derive(Serialize)]
struct ValidationResult {
    is_valid: bool,
    message: String,
    line: Option<u32>,
    column: Option<u32>,
    security_checks: Vec<SecurityCheck>,
    syntax_checks: Vec<SyntaxCheck>,
}

#[derive(Serialize)]
struct SecurityCheck {
    name: String,
    passed: bool,
    message: String,
}

#[derive(Serialize)]
struct SyntaxCheck {
    name: String,
    passed: bool,
    message: String,
}

fn validate_lua_syntax(lua_source: &str) -> ValidationResult {
    let mut security_checks = Vec::new();
    let mut syntax_checks = Vec::new();
    let mut is_valid = true;
    let mut message = "Script validation passed".to_string();
    let mut error_line = None;
    let mut error_column = None;

    // Basic syntax checks
    syntax_checks.push(check_balanced_delimiters(lua_source));
    syntax_checks.push(check_lua_keywords(lua_source));
    syntax_checks.push(check_function_structure(lua_source));

    // Security checks
    security_checks.push(check_for_dangerous_functions(lua_source));
    security_checks.push(check_for_infinite_loops(lua_source));
    security_checks.push(check_for_large_operations(lua_source));

    // Check if any syntax checks failed
    for check in &syntax_checks {
        if !check.passed {
            is_valid = false;
            message = format!("Syntax error: {}", check.message);
            break;
        }
    }

    // Check if any security checks failed
    if is_valid {
        for check in &security_checks {
            if !check.passed {
                is_valid = false;
                message = format!("Security issue: {}", check.message);
                break;
            }
        }
    }

    // If we have a more specific error location, try to parse it
    if !is_valid {
        // Try to extract line/column from common error patterns
        for (line_num, line) in lua_source.lines().enumerate() {
            if line.trim().is_empty() {
                continue;
            }

            // Look for obvious syntax issues
            if line.contains("end") && !line.trim_start().starts_with("--") {
                let open_count = line.matches("do").count() + line.matches("if").count() + line.matches("for").count() + line.matches("while").count() + line.matches("function").count();
                let close_count = line.matches("end").count();

                if close_count > open_count {
                    error_line = Some(line_num as u32 + 1);
                    error_column = Some(line.find("end").unwrap_or(0) as u32);
                    break;
                }
            }
        }
    }

    ValidationResult {
        is_valid,
        message,
        line: error_line,
        column: error_column,
        security_checks,
        syntax_checks,
    }
}

fn check_balanced_delimiters(source: &str) -> SyntaxCheck {
    let mut parentheses = 0;
    let mut braces = 0;
    let mut brackets = 0;

    for (i, ch) in source.chars().enumerate() {
        match ch {
            '(' => parentheses += 1,
            ')' => {
                if parentheses == 0 {
                    return SyntaxCheck {
                        name: "Balanced Parentheses".to_string(),
                        passed: false,
                        message: format!("Unmatched closing parenthesis at character {}", i + 1),
                    };
                }
                parentheses -= 1;
            }
            '{' => braces += 1,
            '}' => {
                if braces == 0 {
                    return SyntaxCheck {
                        name: "Balanced Braces".to_string(),
                        passed: false,
                        message: format!("Unmatched closing brace at character {}", i + 1),
                    };
                }
                braces -= 1;
            }
            '[' => brackets += 1,
            ']' => {
                if brackets == 0 {
                    return SyntaxCheck {
                        name: "Balanced Brackets".to_string(),
                        passed: false,
                        message: format!("Unmatched closing bracket at character {}", i + 1),
                    };
                }
                brackets -= 1;
            }
            _ => {}
        }
    }

    if parentheses != 0 {
        return SyntaxCheck {
            name: "Balanced Parentheses".to_string(),
            passed: false,
            message: format!("{} unclosed parentheses", parentheses),
        };
    }

    if braces != 0 {
        return SyntaxCheck {
            name: "Balanced Braces".to_string(),
            passed: false,
            message: format!("{} unclosed braces", braces),
        };
    }

    if brackets != 0 {
        return SyntaxCheck {
            name: "Balanced Brackets".to_string(),
            passed: false,
            message: format!("{} unclosed brackets", brackets),
        };
    }

    SyntaxCheck {
        name: "Balanced Delimiters".to_string(),
        passed: true,
        message: "All delimiters are properly balanced".to_string(),
    }
}

fn check_lua_keywords(source: &str) -> SyntaxCheck {
    let _valid_keywords = [
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if",
        "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"
    ];

    let lines = source.lines();
    for (line_num, line) in lines.enumerate() {
        let trimmed = line.trim();
        if trimmed.starts_with("--") || trimmed.is_empty() {
            continue;
        }

        // Simple check for obviously invalid constructs
        if trimmed.contains("++") || trimmed.contains("--") && !trimmed.starts_with("--") {
            return SyntaxCheck {
                name: "Lua Keywords".to_string(),
                passed: false,
                message: format!("Invalid operators found on line {}", line_num + 1),
            };
        }
    }

    SyntaxCheck {
        name: "Lua Keywords".to_string(),
        passed: true,
        message: "No invalid Lua constructs found".to_string(),
    }
}

fn check_function_structure(source: &str) -> SyntaxCheck {
    let lines = source.lines();
    let mut function_depth = 0;

    for (line_num, line) in lines.enumerate() {
        let trimmed = line.trim();
        if trimmed.starts_with("--") || trimmed.is_empty() {
            continue;
        }

        // Count function declarations and ends
        let function_count = line.matches("function").count();
        let end_count = line.matches("end").count();

        function_depth += function_count;
        function_depth = function_depth.saturating_sub(end_count);

        if function_depth < 0 {
            return SyntaxCheck {
                name: "Function Structure".to_string(),
                passed: false,
                message: format!("Unexpected 'end' statement on line {}", line_num + 1),
            };
        }
    }

    if function_depth > 0 {
        return SyntaxCheck {
            name: "Function Structure".to_string(),
            passed: false,
            message: format!("{} unclosed function(s)", function_depth),
        };
    }

    SyntaxCheck {
        name: "Function Structure".to_string(),
        passed: true,
        message: "Function structure is valid".to_string(),
    }
}

fn check_for_dangerous_functions(source: &str) -> SecurityCheck {
    let dangerous_functions = [
        "os.execute", "io.open", "io.popen", "loadfile", "dofile", "require",
        "debug.getregistry", "debug.getmetatable", "debug.setmetatable",
        "collectgarbage", "getfenv", "setfenv", "rawget", "rawset"
    ];

    for dangerous in &dangerous_functions {
        if source.contains(dangerous) {
            return SecurityCheck {
                name: "Dangerous Functions".to_string(),
                passed: false,
                message: format!("Potentially dangerous function found: {}", dangerous),
            };
        }
    }

    SecurityCheck {
        name: "Dangerous Functions".to_string(),
        passed: true,
        message: "No dangerous functions detected".to_string(),
    }
}

fn check_for_infinite_loops(source: &str) -> SecurityCheck {
    let lines = source.lines();

    for (line_num, line) in lines.enumerate() {
        let trimmed = line.trim();
        if trimmed.starts_with("--") || trimmed.is_empty() {
            continue;
        }

        // Check for obvious infinite loops
        if (trimmed.contains("while true do") || trimmed.contains("while 1 do"))
            && !trimmed.contains("break")
            && !trimmed.contains("return") {

            // Look for break in the next few lines
            let mut next_lines = source.lines().skip(line_num + 1).take(10);
            let has_break = next_lines.any(|l| l.trim().contains("break") || l.trim().contains("return"));

            if !has_break {
                return SecurityCheck {
                    name: "Infinite Loops".to_string(),
                    passed: false,
                    message: format!("Potential infinite loop detected near line {}", line_num + 1),
                };
            }
        }
    }

    SecurityCheck {
        name: "Infinite Loops".to_string(),
        passed: true,
        message: "No obvious infinite loops detected".to_string(),
    }
}

fn check_for_large_operations(source: &str) -> SecurityCheck {
    // Check for operations that might consume excessive resources
    let large_operations = [
        "string.rep", "table.insert", "string.dump", "string.format",
        "math.randomseed"
    ];

    for operation in &large_operations {
        if source.contains(operation) {
            // Additional context checking could be added here
            // For now, just warn about potential issues
            return SecurityCheck {
                name: "Large Operations".to_string(),
                passed: false,
                message: format!("Potentially resource-intensive operation found: {}", operation),
            };
        }
    }

    SecurityCheck {
        name: "Large Operations".to_string(),
        passed: true,
        message: "No obviously resource-intensive operations detected".to_string(),
    }
}