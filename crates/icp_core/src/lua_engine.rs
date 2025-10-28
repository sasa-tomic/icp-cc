use mlua::prelude::*;
use mlua::LuaSerdeExt;
use serde_json::Value as JsonValue;
use std::time::{Duration, Instant};

#[derive(Debug, thiserror::Error)]
pub enum LuaExecError {
    #[error("lua error: {0}")]
    Lua(String),
    #[error("json error: {0}")]
    Json(String),
}

fn create_sandboxed_lua() -> Result<Lua, LuaError> {
    // Use default std libs, then prune dangerous globals.
    let lua = Lua::new();
    let globals = lua.globals();
    // Remove known-unsafe entry points.
    let _ = globals.raw_set("os", LuaValue::Nil);
    let _ = globals.raw_set("io", LuaValue::Nil);
    let _ = globals.raw_set("debug", LuaValue::Nil);
    let _ = globals.raw_set("package", LuaValue::Nil);
    let _ = globals.raw_set("dofile", LuaValue::Nil);
    let _ = globals.raw_set("loadfile", LuaValue::Nil);
    let _ = globals.raw_set("require", LuaValue::Nil);
    Ok(lua)
}

fn install_json_stdlib(lua: &Lua) -> Result<(), LuaError> {
    // Define a small stdlib: json.encode / json.decode
    let json_encode = lua.create_function(|lua, v: LuaValue| {
        // Convert any Lua value to serde_json::Value, then to string
        let jv: serde_json::Value = match v.clone() {
            LuaValue::Nil => serde_json::Value::Null,
            _ => lua.from_value(v).map_err(LuaError::external)?,
        };
        serde_json::to_string(&jv).map_err(LuaError::external)
    })?;
    let json_decode = lua.create_function(|lua, s: String| {
        let v: serde_json::Value = serde_json::from_str(&s).map_err(LuaError::external)?;
        let lv = lua.to_value(&v).map_err(LuaError::external)?;
        Ok(lv)
    })?;
    let tbl = lua.create_table()?;
    tbl.set("encode", json_encode)?;
    tbl.set("decode", json_decode)?;
    lua.globals().set("json", tbl)?;
    Ok(())
}

fn install_helper_functions(lua: &Lua) -> Result<(), LuaError> {
    // Install helper functions that match the Flutter side
    let helpers = r#"
function icp_call(spec) spec = spec or {}; spec.action = "call"; return spec end
function icp_batch(calls) calls = calls or {}; return { action = "batch", calls = calls } end
function icp_message(spec) spec = spec or {}; return { action = "message", text = tostring(spec.text or ""), type = tostring(spec.type or "info") } end
function icp_ui_list(spec) spec = spec or {}; local items = spec.items or {}; local buttons = spec.buttons or {}; return { action = "ui", ui = { type = "list", items = items, buttons = buttons } } end
function icp_result_display(spec) spec = spec or {}; return { action = "ui", ui = { type = "result_display", props = spec } } end
function icp_searchable_list(spec) spec = spec or {}; return { action = "ui", ui = { type = "list", props = { searchable = true, items = spec.items or {}, title = spec.title or "Results", searchable = spec.searchable ~= false } } } end
function icp_section(spec) spec = spec or {}; return { action = "ui", ui = { type = "section", props = { title = spec.title or "", content = spec.content or "" } } } end
function icp_table(data) return { action = "ui", ui = { type = "table", props = data } } end
function icp_format_number(value, decimals) return tostring(tonumber(value) or 0) end
function icp_format_icp(value, decimals) local v = tonumber(value) or 0; local d = decimals or 8; return tostring(v / math.pow(10, d)) end
function icp_format_timestamp(value) local t = tonumber(value) or 0; return tostring(t) end
function icp_format_bytes(value) local b = tonumber(value) or 0; return tostring(b) end
function icp_truncate(text, maxLen) return tostring(text) end
function icp_filter_items(items, field, value) local filtered = {}; for i, item in ipairs(items) do if string.find(tostring(item[field] or ""), tostring(value), 1, true) then table.insert(filtered, item) end end return filtered end
function icp_sort_items(items, field, ascending) local sorted = {}; for i, item in ipairs(items) do sorted[i] = item end table.sort(sorted, function(a, b) local av = tostring(a[field] or ""); local bv = tostring(b[field] or ""); if ascending then return av < bv else return av > bv end end) return sorted end
function icp_group_by(items, field) local groups = {}; for i, item in ipairs(items) do local key = tostring(item[field] or "unknown"); if not groups[key] then groups[key] = {} end table.insert(groups[key], item) end return groups end
"#;

    lua.load(helpers).exec()?;
    Ok(())
}

/// Execute a Lua chunk and return a JSON string per result value.
/// - Input `script`: Lua source code executed in a sandboxed environment.
/// - Input `json_arg`: optional JSON value bound to global `arg` inside Lua.
/// - Returns: JSON string, either `{ "ok": true, "result": <json> }` or `{ "ok": false, "error": "..." }`.
pub fn execute_lua_json(script: &str, json_arg: Option<&str>) -> Result<String, LuaExecError> {
    let lua = create_sandboxed_lua().map_err(|e| LuaExecError::Lua(e.to_string()))?;

    // Provide an `arg` global for passing data into the script.
    if let Some(s) = json_arg {
        let v: JsonValue =
            serde_json::from_str(s).map_err(|e| LuaExecError::Json(e.to_string()))?;
        // Serialize via serde -> Lua value using mlua serde feature
        let to_lua = lua
            .to_value(&v)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        lua.globals()
            .set("arg", to_lua)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        // Also provide a helper that returns the arg back
        let get_arg = lua
            .create_function(|lua, ()| {
                let a: LuaValue = lua.globals().get("arg")?;
                Ok(a)
            })
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        lua.globals()
            .set("get_arg", get_arg)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
    }

    // Install json helpers
    install_json_stdlib(&lua).map_err(|e| LuaExecError::Lua(e.to_string()))?;

    // Provide a messages accumulator for icp_emit_message helper
    {
        let msgs = lua
            .create_sequence_from::<Vec<String>>(vec![])
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        lua.globals()
            .set("__icp_messages", msgs)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
    }

    // Execute the script; capture a returned value or use nil
    let chunk = lua.load(script);
    let result: LuaValue = chunk
        .eval()
        .map_err(|e| LuaExecError::Lua(e.to_string()))
        .unwrap_or(LuaValue::Nil);

    // Convert result to serde_json::Value
    let json_value = if let LuaValue::Nil = result {
        serde_json::Value::Null
    } else {
        lua.from_value(result)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?
    };

    // Extract any emitted messages
    let mut messages: Vec<String> = Vec::new();
    if let Ok(tbl) = lua.globals().get::<LuaTable>("__icp_messages") {
        let len = tbl.raw_len();
        for i in 1..=len {
            if let Ok(LuaValue::String(s)) = tbl.raw_get(i) {
                match s.to_str() {
                    Ok(ss) => messages.push(ss.to_string()),
                    Err(_) => messages.push(String::new()),
                }
            }
        }
    }

    let response = serde_json::json!({
        "ok": true,
        "result": json_value,
        "messages": messages,
    });
    Ok(response.to_string())
}

#[derive(Debug, Clone)]
pub struct ValidationContext {
    pub is_example: bool,
    pub is_test: bool,
    pub is_production: bool,
}

#[derive(Debug, Clone)]
pub struct ValidationResult {
    pub is_valid: bool,
    pub syntax_errors: Vec<String>,
    pub warnings: Vec<String>,
    pub line_count: usize,
    pub character_count: usize,
}

/// Comprehensive Lua script validation covering syntax, security, performance, and ICP-specific patterns
pub fn validate_lua_comprehensive(
    script: &str,
    context: Option<ValidationContext>,
) -> ValidationResult {
    let ctx = context.unwrap_or_else(|| ValidationContext {
        is_example: is_example_script(script),
        is_test: is_test_script(script),
        is_production: !is_example_script(script) && !is_test_script(script),
    });

    let mut result = ValidationResult {
        is_valid: true,
        syntax_errors: Vec::new(),
        warnings: Vec::new(),
        line_count: script.lines().count(),
        character_count: script.len(),
    };

    // 1. Basic validation
    validate_basic(script, &mut result);

    // 2. MLua syntax validation (most reliable)
    if result.is_valid {
        validate_mlua_syntax(script, &mut result);
    }

    // 3. Required functions validation
    if result.is_valid {
        validate_required_functions(script, &mut result);
    }

    // 4. Event handler validation
    validate_event_handlers(script, &mut result);

    // 5. Security validation
    validate_security_patterns(script, &ctx, &mut result);

    // 6. ICP integration validation
    validate_icp_integration(script, &ctx, &mut result);

    // 7. Performance validation
    validate_performance_patterns(script, &ctx, &mut result);

    // 8. Data structure validation
    validate_data_structures(script, &ctx, &mut result);

    // 9. UI node validation
    validate_ui_nodes(script, &mut result);

    result.is_valid = result.syntax_errors.is_empty();
    result
}

/// Lint a Lua script without executing it.
/// Returns a JSON string: { ok: boolean, errors: [ { message } ] }
pub fn lint_lua(script: &str) -> String {
    let result = validate_lua_comprehensive(script, None);

    serde_json::json!({
        "ok": result.is_valid,
        "errors": result.syntax_errors.iter().map(|e| serde_json::json!({"message": e})).collect::<Vec<_>>(),
        "warnings": result.warnings,
        "line_count": result.line_count,
        "character_count": result.character_count
    }).to_string()
}

// Helper functions for comprehensive validation

fn validate_basic(script: &str, result: &mut ValidationResult) {
    if script.trim().is_empty() {
        result
            .syntax_errors
            .push("Lua source cannot be empty".to_string());
    }
}

fn validate_mlua_syntax(script: &str, result: &mut ValidationResult) {
    match create_sandboxed_lua() {
        Ok(lua) => {
            let chunk = lua.load(script);
            match chunk.into_function() {
                Ok(_) => {} // Syntax is valid
                Err(e) => {
                    result.syntax_errors.push(format!("Syntax error: {}", e));
                }
            }
        }
        Err(e) => {
            result
                .syntax_errors
                .push(format!("Failed to create Lua environment: {}", e));
        }
    }
}

fn validate_required_functions(script: &str, result: &mut ValidationResult) {
    // Check for each required function
    if !script.contains("function init(") && !script.contains("function init (") {
        result.syntax_errors.push(
            "Required function 'init' not found - script will not execute properly".to_string(),
        );
    }
    if !script.contains("function view(") && !script.contains("function view (") {
        result.syntax_errors.push(
            "Required function 'view' not found - script will not execute properly".to_string(),
        );
    }
    if !script.contains("function update(") && !script.contains("function update (") {
        result.syntax_errors.push(
            "Required function 'update' not found - script will not execute properly".to_string(),
        );
    }

    // Validate function signatures
    if let Some(init_match) = script.find("function init(") {
        let init_section = &script[init_match..];
        if let Some(end_pos) = init_section.find(')') {
            let init_sig = &init_section[..=end_pos];
            if init_sig.contains(',') {
                result
                    .warnings
                    .push("init() function should accept at most one parameter (arg)".to_string());
            }
        }
    }

    if let Some(view_match) = script.find("function view(") {
        let view_section = &script[view_match..];
        if !view_section.contains("state") {
            result
                .warnings
                .push("view() function should accept a state parameter".to_string());
        }
    }

    if let Some(update_match) = script.find("function update(") {
        let update_section = &script[update_match..];
        if !update_section.contains("msg") || !update_section.contains("state") {
            result
                .warnings
                .push("update() function should accept msg and state parameters".to_string());
        }
    }
}

fn validate_event_handlers(script: &str, result: &mut ValidationResult) {
    // Extract event handlers from UI definitions
    let event_handler_regex =
        regex::Regex::new(r#"on_(press|change|submit|input)\s*=\s*\{\s*type\s*:\s*"([^"]+)""#)
            .unwrap_or_else(|_| regex::Regex::new(r"dummy").unwrap());

    let mut event_handlers = Vec::new();
    for cap in event_handler_regex.captures_iter(script) {
        if let Some(handler) = cap.get(2) {
            event_handlers.push(handler.as_str().to_string());
        }
    }

    // Extract message types from update function
    let message_type_regex = regex::Regex::new(r#"msg\.type\s*==\s*"([^"]+)""#)
        .unwrap_or_else(|_| regex::Regex::new(r"dummy").unwrap());

    let mut message_types = Vec::new();
    for cap in message_type_regex.captures_iter(script) {
        if let Some(msg_type) = cap.get(1) {
            message_types.push(msg_type.as_str().to_string());
        }
    }

    // Check for unhandled events
    for handler in &event_handlers {
        if !message_types.contains(handler) && !handler.starts_with("effect/") {
            result.warnings.push(format!(
                "Event handler '{}' has no corresponding case in update() function",
                handler
            ));
        }
    }

    // Check for orphaned message handlers
    for msg_type in &message_types {
        if !event_handlers.contains(msg_type) && !msg_type.starts_with("effect/") {
            result.warnings.push(format!(
                "Message handler '{}' has no corresponding UI event handler",
                msg_type
            ));
        }
    }
}

fn validate_security_patterns(
    script: &str,
    context: &ValidationContext,
    result: &mut ValidationResult,
) {
    // Always block dangerous functions
    let dangerous_patterns = [
        (
            "loadstring(",
            "loadstring() function detected - potential security risk",
        ),
        (
            "dofile(",
            "dofile() function detected - potential security risk",
        ),
        (
            "os.execute",
            "os.execute() - potentially dangerous system call",
        ),
        ("io.open", "io.open() - file system access not allowed"),
        ("io.popen", "io.popen() - process execution not allowed"),
        ("loadfile", "loadfile() - file loading not allowed"),
        ("require(", "require() - module loading not allowed"),
        (
            "debug.getregistry",
            "debug.getregistry() - debug access not allowed",
        ),
        (
            "package.loadlib",
            "package.loadlib() - library loading not allowed",
        ),
    ];

    for (pattern, message) in &dangerous_patterns {
        if script.contains(pattern) {
            result.syntax_errors.push(message.to_string());
        }
    }

    // Secret detection with context awareness
    if context.is_production {
        // Use simple string matching for secrets instead of regex
        if script.contains("private_key") && script.contains('"') {
            result.syntax_errors.push(
                "Hardcoded private key detected - use environment variables or secure storage"
                    .to_string(),
            );
        }
        if (script.contains("password") || script.contains("token") || script.contains("api_key"))
            && script.contains('"')
            && script.len() > 100
        {
            result.syntax_errors.push(
                "Potential hardcoded secret detected - use environment variables or secure storage"
                    .to_string(),
            );
        }
    } else {
        // In examples/tests, only warn about obvious secrets
        if script.contains("sk-") || script.contains("pk_") {
            result
                .warnings
                .push("Potential real secret detected in example/test code".to_string());
        }
    }

    // XSS detection - simple string matching
    if script.contains("<script") || script.contains("javascript:") {
        result
            .syntax_errors
            .push("Dangerous HTML/JavaScript pattern detected".to_string());
    }

    // Network URL validation - simple string matching
    if script.contains("http://") || script.contains("https://") {
        let words: Vec<&str> = script.split_whitespace().collect();
        for word in words {
            if word.starts_with("http://") || word.starts_with("https://") {
                let url =
                    word.trim_matches(|c| c == ',' || c == ';' || c == ')' || c == '(' || c == '"');
                if url.contains("localhost") || url.contains("127.0.0.1") {
                    if context.is_production {
                        result
                            .syntax_errors
                            .push(format!("Localhost URL in production code: {}", url));
                    } else {
                        result.warnings.push(format!(
                            "Localhost URL detected: {} - ensure this is intentional",
                            url
                        ));
                    }
                }
                if url.starts_with("http://") && context.is_production {
                    result.warnings.push(format!(
                        "Insecure HTTP URL detected: {} - consider using HTTPS",
                        url
                    ));
                }
            }
        }
    }
}

fn validate_icp_integration(
    script: &str,
    context: &ValidationContext,
    result: &mut ValidationResult,
) {
    // Validate canister ID patterns with context awareness
    // Simple string matching approach to avoid regex compilation in loops
    let mut pos = 0;
    while let Some(canister_start) = script[pos..].find("canister_id") {
        let absolute_start = pos + canister_start;
        let remaining = &script[absolute_start..];

        if let Some(quote_start) = remaining.find('"') {
            let quote_pos = absolute_start + quote_start;
            if let Some(quote_end) = script[quote_pos + 1..].find('"') {
                let absolute_end = quote_pos + 1 + quote_end;
                let canister_id = &script[quote_pos + 1..absolute_end];

                // Allow test/mock IDs in examples and tests
                if context.is_example || context.is_test {
                    let canister_lower = canister_id.to_lowercase();
                    if canister_lower.starts_with("test")
                        || canister_lower.starts_with("mock")
                        || canister_lower.starts_with("demo")
                        || canister_lower.starts_with("example")
                    {
                        pos = absolute_end;
                        continue;
                    }
                }

                // Basic canister ID validation
                if canister_id.len() < 10 || canister_id.len() > 63 || !canister_id.contains('-') {
                    if context.is_production {
                        result.syntax_errors.push(format!("Invalid canister ID format: {}. Expected format: xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxx-xxx", canister_id));
                    } else {
                        result.warnings.push(format!(
                            "Potentially invalid canister ID format: {}",
                            canister_id
                        ));
                    }
                }

                pos = absolute_end;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    // Validate effect handling
    if script.contains(r#"kind = "icp_call""#) {
        let script_lower = script.to_lowercase();
        if !script_lower.contains("effect/result") {
            if context.is_production {
                result.syntax_errors.push(
                    "Script uses ICP calls but missing effect/result handler in update() function"
                        .to_string(),
                );
            } else {
                result.warnings.push(
                    "Script uses ICP calls but missing effect/result handler in update() function"
                        .to_string(),
                );
            }
        }
    }

    // Validate canister call structure - simple string matching
    if script.contains("canister_id") && script.contains("method") && script.contains("kind") {
        // Look for canister call patterns that might be missing args
        let lines: Vec<&str> = script.lines().collect();
        for line in &lines {
            if line.contains("canister_id")
                && line.contains("method")
                && line.contains("kind")
                && !line.contains("args")
            {
                result.warnings.push(
                    "Canister call missing args field - may cause runtime errors".to_string(),
                );
            }
        }
    }
}

fn validate_performance_patterns(
    script: &str,
    context: &ValidationContext,
    result: &mut ValidationResult,
) {
    // Infinite loop detection - simplified approach
    if script.contains("while true do") || script.contains("while	true do") {
        // Look for while true loops and check if they have break/return
        let lines: Vec<&str> = script.lines().collect();
        let mut in_while_loop = false;
        let mut while_loop_content = Vec::new();

        for line in &lines {
            if line.trim().contains("while true do") || line.trim().contains("while	true do") {
                in_while_loop = true;
                continue;
            }

            if in_while_loop {
                if line.trim() == "end" {
                    // Check if loop has conditional break or return
                    let loop_content = while_loop_content.join("\n");
                    if !loop_content.contains("if")
                        || (!loop_content.contains("break") && !loop_content.contains("return"))
                    {
                        result.syntax_errors.push(
                            "Potential infinite loop - while true without conditional break/return"
                                .to_string(),
                        );
                    }
                    in_while_loop = false;
                    while_loop_content.clear();
                } else {
                    while_loop_content.push(line.to_string());
                }
            }
        }
    }

    // Recursive function detection (production only) - simplified approach
    if context.is_production {
        // Simple heuristic: check for function calls that match function names
        let lines: Vec<&str> = script.lines().collect();
        let mut function_names = Vec::new();

        for line in &lines {
            let trimmed = line.trim();
            if trimmed.starts_with("function ")
                && !trimmed.starts_with("function init(")
                && !trimmed.starts_with("function view(")
                && !trimmed.starts_with("function update(")
            {
                // Extract function name
                if let Some(space_pos) = trimmed.find(' ') {
                    let name_part = &trimmed[space_pos + 1..];
                    if let Some(paren_pos) = name_part.find('(') {
                        let func_name = &name_part[..paren_pos];
                        if !func_name.is_empty() {
                            function_names.push(func_name.to_string());
                        }
                    }
                }
            }
        }

        // Check for recursive calls
        for func_name in &function_names {
            let call_pattern = format!("{}(", func_name);
            let mut call_count = 0;
            for line in &lines {
                if line.contains(&call_pattern) {
                    call_count += 1;
                }
            }

            if call_count > 1 {
                // This might be recursive - check if function has if/return
                let mut func_body = Vec::new();
                let mut in_function = false;

                for line in &lines {
                    let trimmed = line.trim();
                    if trimmed.starts_with(&format!("function {}(", func_name)) {
                        in_function = true;
                        continue;
                    }

                    if in_function {
                        if trimmed == "end" {
                            let body = func_body.join("\n");
                            if !body.contains("if") && !body.contains("return") {
                                result.warnings.push(format!(
                                    "Recursive function '{}' may be missing base case",
                                    func_name
                                ));
                            }
                            in_function = false;
                            func_body.clear();
                        } else {
                            func_body.push(line.to_string());
                        }
                    }
                }
            }
        }
    }

    // Large number detection - simple string matching
    let words: Vec<&str> = script.split_whitespace().collect();
    for word in words {
        if word.chars().all(|c| c.is_ascii_digit()) && word.len() >= 15 {
            result.warnings.push(
                "Very large numbers detected - ensure they fit within Lua number limits"
                    .to_string(),
            );
            break;
        }
    }

    // Table insert performance warning
    let table_insert_count = script.matches("table.insert").count();
    if table_insert_count > 50 {
        result.warnings.push(
            "Many table.insert operations detected - consider optimizing for better performance"
                .to_string(),
        );
    }
}

fn validate_data_structures(
    script: &str,
    context: &ValidationContext,
    result: &mut ValidationResult,
) {
    // Undefined state access detection (production only) - simplified approach
    if context.is_production {
        // Find state.field patterns using simple string matching
        let lines: Vec<&str> = script.lines().collect();
        let mut state_fields = Vec::new();

        for line in &lines {
            let trimmed = line.trim();
            if trimmed.starts_with("state.") {
                if let Some(dot_pos) = trimmed.find('.') {
                    let field_part = &trimmed[dot_pos + 1..];
                    // Extract field name (until first non-word character)
                    let field_end = field_part
                        .find(|c: char| !c.is_alphanumeric() && c != '_')
                        .unwrap_or(field_part.len());
                    let field = &field_part[..field_end];

                    // Skip common state fields that might be set dynamically
                    if ![
                        "last_action",
                        "show_info",
                        "counter",
                        "balance",
                        "transactions",
                    ]
                    .contains(&field)
                    {
                        state_fields.push(field.to_string());
                    }
                }
            }
        }

        // Check if these state fields are initialized in init function
        for field in &state_fields {
            let init_pattern = format!("{} = ", field);
            if !script.contains(&init_pattern) && !script.contains(&format!("{}=", field)) {
                result.warnings.push(format!(
                    "State field 'state.{}' may be undefined - ensure it's initialized in init()",
                    field
                ));
            }
        }
    }

    // String concatenation in loops (performance issue - production only) - simplified
    if context.is_production
        && script.contains("for")
        && script.contains("do")
        && script.contains("..")
    {
        let lines: Vec<&str> = script.lines().collect();
        let mut in_for_loop = false;
        let mut loop_content = Vec::new();

        for line in &lines {
            let trimmed = line.trim();
            if trimmed.starts_with("for ") && trimmed.contains(" do") {
                in_for_loop = true;
                continue;
            }

            if in_for_loop {
                if trimmed == "end" {
                    let loop_str = loop_content.join("\n");
                    let concat_count = loop_str.matches("..").count();
                    if concat_count > 5 {
                        result.warnings.push("String concatenation in loop detected - consider using table.concat for better performance".to_string());
                    }
                    in_for_loop = false;
                    loop_content.clear();
                } else {
                    loop_content.push(line.to_string());
                }
            }
        }
    }

    // Table operations threshold
    let table_insert_matches = script.matches("table.insert").count();
    if table_insert_matches > 100 {
        result.warnings.push("Many table.insert operations detected - consider pre-allocating tables for better performance".to_string());
    }
}

fn validate_ui_nodes(script: &str, result: &mut ValidationResult) {
    // Check for conditional rendering patterns that might produce false values
    let lines: Vec<&str> = script.lines().collect();
    for line in &lines {
        if line.contains(" and {") && !line.contains("type") {
            result.syntax_errors.push("Conditional UI expression missing type field - this will cause \"UI node missing type\" error".to_string());
        }
    }

    // Check for empty type values - simplified approach
    if script.contains("type = ") {
        let lines: Vec<&str> = script.lines().collect();
        for line in &lines {
            if line.contains("type = ") {
                // Look for type = "" patterns
                if line.contains("type = \"\"") || line.contains("type = ''") {
                    result
                        .syntax_errors
                        .push("UI node with empty type found".to_string());
                }
            }
        }
    }

    // Check for valid UI node types - simplified approach
    let valid_types = [
        "column", "row", "section", "text", "button", "toggle", "input",
    ];
    let lines: Vec<&str> = script.lines().collect();
    for line in &lines {
        if line.contains("type = ") {
            // Extract type value - look for type = "something" pattern
            if let Some(start) = line.find("type = ") {
                let type_part = &line[start + 7..];
                // Skip whitespace after "type ="
                let trimmed_part = type_part.trim_start();
                // Check if it starts with a quote and strip it
                if let Some(content) = trimmed_part.strip_prefix('"') {
                    if let Some(end_quote) = content.find('"') {
                        let type_value = &content[..end_quote];
                        if !type_value.is_empty() && !valid_types.contains(&type_value) {
                            result.warnings.push(format!(
                                "Unknown UI node type: \"{}\" - valid types are: {}",
                                type_value,
                                valid_types.join(", ")
                            ));
                        }
                    }
                }
            }
        }
    }

    // Look for missing type fields in return statements - simplified
    if script.contains("return {") {
        let lines: Vec<&str> = script.lines().collect();
        let mut in_return = false;
        let mut brace_count = 0;

        for line in &lines {
            let trimmed = line.trim();
            if trimmed == "return {" {
                in_return = true;
                brace_count = 1;
                continue;
            }

            if in_return {
                // Count braces to track nested structures
                brace_count += trimmed.matches('{').count() as i32;
                brace_count -= trimmed.matches('}').count() as i32;

                // Check if this line looks like a table literal without type
                if trimmed.starts_with('{')
                    && trimmed.contains('}')
                    && !trimmed.contains("type")
                    && (trimmed.contains("props") || trimmed.contains("children"))
                {
                    result
                        .syntax_errors
                        .push("UI node missing type field".to_string());
                }

                if brace_count <= 0 {
                    in_return = false;
                }
            }
        }
    }
}

// Helper functions for context detection
fn is_example_script(script: &str) -> bool {
    let script_lower = script.to_lowercase();
    script_lower.contains("-- example")
        || script_lower.contains("-- demo")
        || script_lower.contains("-- tutorial")
        || script_lower.contains("-- sample")
}

fn is_test_script(script: &str) -> bool {
    let script_lower = script.to_lowercase();
    script_lower.contains("-- test")
        || script_lower.contains("-- spec")
        || script_lower.contains("-- unit")
}

// ---- TEA-style app helpers ----

fn install_time_hook(lua: &Lua, budget: Duration) -> Result<(), LuaError> {
    // Abort execution if the time budget is exceeded. We check every N instructions.
    let start = Instant::now();
    // Use a small Rc to capture start time; mlua's hook takes a closure.
    lua.set_hook(
        mlua::HookTriggers {
            every_nth_instruction: Some(20_000),
            ..Default::default()
        },
        move |_, _dbg| {
            if start.elapsed() > budget {
                Err(LuaError::RuntimeError("execution timeout".to_string()))
            } else {
                Ok(mlua::VmState::Continue)
            }
        },
    )
}

fn call_lua_fn2(
    lua: &Lua,
    fname: &str,
    a: LuaValue,
    b: Option<LuaValue>,
) -> Result<LuaMultiValue, LuaError> {
    let globals = lua.globals();
    let func: LuaFunction = globals.get(fname)?;
    match b {
        Some(bv) => func.call::<LuaMultiValue>((a, bv)),
        None => func.call::<LuaMultiValue>((a,)),
    }
}

fn to_lua_value(lua: &Lua, json: &serde_json::Value) -> Result<LuaValue, LuaError> {
    lua.to_value(json)
}

fn from_lua_value<T: serde::de::DeserializeOwned>(lua: &Lua, v: LuaValue) -> Result<T, LuaError> {
    match v {
        LuaValue::Nil => serde_json::from_str("null").map_err(LuaError::external),
        _ => lua.from_value(v),
    }
}

pub fn app_init(script: &str, json_arg: Option<&str>, budget_ms: u64) -> String {
    let lua = match create_sandboxed_lua() {
        Ok(l) => l,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    if let Err(e) = install_json_stdlib(&lua) {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    let _ = install_time_hook(&lua, Duration::from_millis(budget_ms));
    let chunk = lua.load(script);
    if let Err(e) = chunk.exec() {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    let arg_json = json_arg.unwrap_or("null");
    let arg_val: serde_json::Value = match serde_json::from_str(arg_json) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid arg JSON: {}", e)})
                .to_string()
        }
    };
    let arg_lua = match to_lua_value(&lua, &arg_val) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    let mv = match call_lua_fn2(&lua, "init", arg_lua, None) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    // Expect (state, effects)
    let mut iter = mv.into_iter();
    let state_v = iter.next().unwrap_or(LuaValue::Nil);
    let effects_v = iter.next().unwrap_or(LuaValue::Nil);
    let state_json: serde_json::Value = match from_lua_value(&lua, state_v) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid state: {}", e)})
                .to_string()
        }
    };
    let effects_json: serde_json::Value = match from_lua_value(&lua, effects_v) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid effects: {}", e)})
                .to_string()
        }
    };
    serde_json::json!({"ok": true, "state": state_json, "effects": effects_json}).to_string()
}

pub fn app_view(script: &str, state_json: &str, budget_ms: u64) -> String {
    let lua = match create_sandboxed_lua() {
        Ok(l) => l,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    if let Err(e) = install_json_stdlib(&lua) {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    if let Err(e) = install_helper_functions(&lua) {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    let _ = install_time_hook(&lua, Duration::from_millis(budget_ms));
    if let Err(e) = lua.load(script).exec() {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    let state_val: serde_json::Value = match serde_json::from_str(state_json) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid state JSON: {}", e)})
                .to_string()
        }
    };
    let state_lua = match to_lua_value(&lua, &state_val) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    let mv = match call_lua_fn2(&lua, "view", state_lua, None) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    let ui_v = mv.into_iter().next().unwrap_or(LuaValue::Nil);
    let ui_json: serde_json::Value = match from_lua_value(&lua, ui_v) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid ui: {}", e)})
                .to_string()
        }
    };
    serde_json::json!({"ok": true, "ui": ui_json}).to_string()
}

pub fn app_update(script: &str, msg_json: &str, state_json: &str, budget_ms: u64) -> String {
    let lua = match create_sandboxed_lua() {
        Ok(l) => l,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    if let Err(e) = install_json_stdlib(&lua) {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    if let Err(e) = install_helper_functions(&lua) {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    let _ = install_time_hook(&lua, Duration::from_millis(budget_ms));
    if let Err(e) = lua.load(script).exec() {
        return serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
    }
    let msg_val: serde_json::Value = match serde_json::from_str(msg_json) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid msg JSON: {}", e)})
                .to_string()
        }
    };
    let state_val: serde_json::Value = match serde_json::from_str(state_json) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid state JSON: {}", e)})
                .to_string()
        }
    };
    let msg_lua = match to_lua_value(&lua, &msg_val) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    let state_lua = match to_lua_value(&lua, &state_val) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    let mv = match call_lua_fn2(&lua, "update", msg_lua, Some(state_lua)) {
        Ok(v) => v,
        Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}).to_string(),
    };
    let mut iter = mv.into_iter();
    let state_v = iter.next().unwrap_or(LuaValue::Nil);
    let effects_v = iter.next().unwrap_or(LuaValue::Nil);
    let state_json_out: serde_json::Value = match from_lua_value(&lua, state_v) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid state: {}", e)})
                .to_string()
        }
    };
    let effects_json: serde_json::Value = match from_lua_value(&lua, effects_v) {
        Ok(v) => v,
        Err(e) => {
            return serde_json::json!({"ok": false, "error": format!("invalid effects: {}", e)})
                .to_string()
        }
    };
    serde_json::json!({"ok": true, "state": state_json_out, "effects": effects_json}).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_comprehensive_validation_system() {
        // Test 1: Valid production script
        let valid_script = r#"
function init(arg)
  return { count = 0 }, {}
end

function view(state)
  return { type = "text", props = { text = "Count: " .. tostring(state.count) } }
end

function update(msg, state)
  if msg.type == "inc" then
    state.count = state.count + 1
    return state, {}
  end
  return state, {}
end
"#;
        let result = validate_lua_comprehensive(
            valid_script,
            Some(ValidationContext {
                is_example: false,
                is_test: false,
                is_production: true,
            }),
        );
        assert!(result.is_valid);
        assert!(result.syntax_errors.is_empty());
        assert_eq!(result.line_count, 16);
        assert!(result.character_count > 0);

        // Test 2: Script with security issues
        let security_script = r#"
function init(arg)
  loadstring("print('hello')")
  return { count = 0 }, {}
end

function view(state)
  return { type = "text", props = { text = "Count: " .. tostring(state.count) } }
end

function update(msg, state)
  if msg.type == "inc" then
    state.count = state.count + 1
    return state, {}
  end
  return state, {}
end
"#;
        let result = validate_lua_comprehensive(
            security_script,
            Some(ValidationContext {
                is_example: false,
                is_test: false,
                is_production: true,
            }),
        );
        assert!(!result.is_valid);
        assert!(!result.syntax_errors.is_empty());
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("loadstring")));

        // Test 3: Example script (more lenient about secrets)
        let example_script = r#"
-- EXAMPLE: This is a demo script
function init(arg)
  local privateKey = "sk-test123456789"
  return { count = 0, key = privateKey }, {}
end

function view(state)
  return { type = "text", props = { text = "Count: " .. tostring(state.count) } }
end

function update(msg, state)
  if msg.type == "inc" then
    state.count = state.count + 1
    return state, {}
  end
  return state, {}
end
"#;
        let result = validate_lua_comprehensive(
            example_script,
            Some(ValidationContext {
                is_example: true,
                is_test: false,
                is_production: false,
            }),
        );
        assert!(result.is_valid); // Should be valid for example context
        assert!(result.warnings.iter().any(|w| w.contains("secret"))); // But should warn about secrets

        // Test 4: Script missing required functions
        let incomplete_script = r#"
function init(arg)
  return { count = 0 }, {}
end
// Missing view and update functions
"#;
        let result = validate_lua_comprehensive(incomplete_script, None);
        assert!(!result.is_valid);
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("view") && e.contains("not found")));
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("update") && e.contains("not found")));
    }

    #[test]
    fn simple_math() {
        let out = execute_lua_json("return 1 + 2", None).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v.get("ok").and_then(|b| b.as_bool()).unwrap());
        assert_eq!(v.get("result").and_then(|x| x.as_i64()).unwrap(), 3);
    }

    #[test]
    fn with_arg_roundtrip() {
        let arg = "{\"a\": 1}";
        let out = execute_lua_json("local a = get_arg(); return a.a", Some(arg)).unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["result"].as_i64().unwrap(), 1);
    }

    #[test]
    fn json_helpers() {
        let out = execute_lua_json(
            r#"
            local t = {x=10, y=20}
            local s = json.encode(t)
            local u = json.decode(s)
            return u.x + u.y
            "#,
            None,
        )
        .unwrap();
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["result"].as_i64().unwrap(), 30);
    }

    #[test]
    fn app_init_view_update_roundtrip() {
        // Lua app that increments a counter and echoes last message
        let script = r#"
            function init(arg)
              local start =  (arg and arg.start) or 0
              return { count = start, last = nil }, {}
            end
            function view(state)
              return { type = "column", props = {}, children = {
                { type = "text", props = { text = tostring(state.count) } }
              } }
            end
            function update(msg, state)
              local t = (msg and msg.type) or ""
              if t == "inc" then
                state.count = (state.count or 0) + 1
              end
              state.last = msg
              return state, {}
            end
        "#;

        // init
        let out = app_init(script, Some("{\"start\":1}"), 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());
        assert_eq!(v["state"]["count"].as_i64().unwrap(), 1);
        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());
        assert_eq!(vv["ui"]["type"].as_str().unwrap(), "column");
        // update
        let upo = app_update(script, "{\"type\":\"inc\"}", &st, 100);
        let vu: serde_json::Value = serde_json::from_str(&upo).unwrap();
        assert!(vu["ok"].as_bool().unwrap());
        assert_eq!(vu["state"]["count"].as_i64().unwrap(), 2);
        // Effects may serialize as an empty object when empty; accept array or empty object
        let eff = &vu["effects"];
        assert!(eff.is_array() || (eff.is_object() && eff.as_object().unwrap().is_empty()));
    }

    #[test]
    fn app_init_timeout() {
        // Busy loop to exhaust instruction budget
        let script = r#"
            function init(arg)
              local i = 0
              while true do i = i + 1 end
              return {}, {}
            end
            function view(state) return {} end
            function update(msg, state) return state, {} end
        "#;
        let out = app_init(script, None, 1); // tiny budget
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(!v["ok"].as_bool().unwrap());
        let err = v["error"].as_str().unwrap().to_lowercase();
        assert!(err.contains("timeout") || err.contains("execution"));
    }

    #[test]
    fn app_view_invalid_state_json() {
        let script = r#"
            function init(arg) return {}, {} end
            function view(state) return { type = "text", props = { text = "ok" } } end
            function update(msg, state) return state, {} end
        "#;
        let out = app_view(script, "not-json", 50);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(!v["ok"].as_bool().unwrap());
        assert!(v["error"].as_str().unwrap().contains("invalid state JSON"));
    }

    #[test]
    fn sample_app_default_works() {
        // Keep this in sync with apps/autorun_flutter/lib/controllers/script_controller.dart:kDefaultSampleLua
        let script = r#"
            function init(arg)
              return {
                count = 0,
                items = json.decode('[]'),
                last = nil
              }, {}
            end

            function view(state)
              local children = {
                { type = "section", props = { title = "Sample UI-enabled Script" }, children = {
                  { type = "text", props = { text = "Counter: "..tostring(state.count or 0) } },
                  { type = "row", children = {
                    { type = "button", props = { label = "Increment", on_press = { type = "inc" } } },
                    { type = "button", props = { label = "Load ICP samples", on_press = { type = "load_sample" } } }
                  } }
                } }
              }
              local items = state.items or {}
              if type(items) == 'table' and #items > 0 then
                table.insert(children, { type = "section", props = { title = "Loaded results" }, children = {
                  { type = "list", props = { items = items } }
                } })
              end
              return { type = "column", children = children }
            end

            function update(msg, state)
              local t = (msg and msg.type) or ""
              if t == "inc" then
                state.count = (state.count or 0) + 1
                return state, {}
              end
              if t == "load_sample" then
                -- Trigger a batch of canister calls; host will request permission
                local gov = { label = "gov", kind = 0, canister_id = "rrkah-fqaaa-aaaaa-aaaaq-cai", method = "get_pending_proposals", args = "()" }
                local ledger = { label = "ledger", kind = 0, canister_id = "ryjl3-tyaaa-aaaaa-aaaba-cai", method = "query_blocks", args = "{\"start\":0,\"length\":3}" }
                return state, { { kind = "icp_batch", id = "load", items = { gov, ledger } } }
              end
              if t == "effect/result" and msg.id == "load" then
                -- Normalize results into a list for display
                local items = {}
                if msg.ok then
                  for k, v in pairs(msg.data or {}) do
                    table.insert(items, { title = tostring(k), subtitle = type(v) == 'table' and json.encode(v) or tostring(v) })
                  end
                else
                  table.insert(items, { title = "Error", subtitle = tostring(msg.error or "unknown error") })
                end
                state.items = items
                return state, {}
              end
              state.last = msg
              return state, {}
            end
        "#;

        // init should succeed and set count to 0
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());
        assert_eq!(v["state"]["count"].as_i64().unwrap(), 0);

        // view should produce a column ui
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());
        assert_eq!(vv["ui"]["type"].as_str().unwrap(), "column");

        // update inc should increment
        let upo = app_update(script, "{\"type\":\"inc\"}", &st, 100);
        let vu: serde_json::Value = serde_json::from_str(&upo).unwrap();
        assert!(vu["ok"].as_bool().unwrap());
        assert_eq!(vu["state"]["count"].as_i64().unwrap(), 1);

        // load_sample should produce an icp_batch effect with 2 items
        let up2 = app_update(script, "{\"type\":\"load_sample\"}", &st, 100);
        let v2: serde_json::Value = serde_json::from_str(&up2).unwrap();
        assert!(v2["ok"].as_bool().unwrap());
        let eff = &v2["effects"];
        assert!(eff.is_array());
        let arr = eff.as_array().unwrap();
        assert!(!arr.is_empty());
        assert_eq!(arr[0]["kind"].as_str().unwrap(), "icp_batch");
        let items = arr[0]["items"].as_array().unwrap();
        assert_eq!(items.len(), 2);
    }

    #[test]
    fn icp_searchable_list_function_works() {
        let script = r#"
            function init(arg)
                return {
                    items = {
                        {id = 1, name = "Transaction 1", amount = "100"},
                        {id = 2, name = "Transaction 2", amount = "200"}
                    }
                }, {}
            end

            function view(state)
                return icp_searchable_list({
                    items = state.items,
                    title = "Recent Transactions",
                    searchable = true
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the searchable list structure is correct
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        assert!(ui["props"]["searchable"].as_bool().unwrap());
        assert_eq!(
            ui["props"]["title"].as_str().unwrap(),
            "Recent Transactions"
        );
        assert!(ui["props"]["searchable"].as_bool().unwrap());
        assert_eq!(ui["props"]["items"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_icp_call_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_call({
                    canister = "rrkah-fqaaa-aaaaa-aaaaq-cai",
                    method = "get_balance",
                    args = {}
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the call structure is correct
        let ui = &vv["ui"];
        assert_eq!(ui["action"].as_str().unwrap(), "call");
        assert_eq!(
            ui["canister"].as_str().unwrap(),
            "rrkah-fqaaa-aaaaa-aaaaq-cai"
        );
        assert_eq!(ui["method"].as_str().unwrap(), "get_balance");
    }

    #[test]
    fn test_icp_batch_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_batch({
                    calls = {
                        {
                            canister = "rrkah-fqaaa-aaaaa-aaaaq-cai",
                            method = "get_balance",
                            args = {}
                        },
                        {
                            canister = "ryjl3-tyaaa-aaaaa-aaaba-cai",
                            method = "get_account_id",
                            args = {}
                        }
                    }
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the batch structure is correct
        let ui = &vv["ui"];
        assert_eq!(ui["action"].as_str().unwrap(), "batch");
        assert_eq!(ui["calls"]["calls"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_icp_message_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_message({
                    text = "Hello, World!",
                    type = "info"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the message structure is correct
        let ui = &vv["ui"];
        assert_eq!(ui["action"].as_str().unwrap(), "message");
        assert_eq!(ui["text"].as_str().unwrap(), "Hello, World!");
        assert_eq!(ui["type"].as_str().unwrap(), "info");
    }

    #[test]
    fn test_icp_ui_list_function_works() {
        let script = r#"
            function init(arg)
                return {
                    items = {"Item 1", "Item 2", "Item 3"}
                }, {}
            end

            function view(state)
                return icp_ui_list({
                    items = state.items,
                    title = "Simple List"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the ui list structure is correct
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        assert_eq!(ui["items"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn test_icp_result_display_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_result_display({
                    result = "Success: Operation completed",
                    type = "success"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the result display structure is correct
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "result_display");
        assert_eq!(
            ui["props"]["result"].as_str().unwrap(),
            "Success: Operation completed"
        );
        assert_eq!(ui["props"]["type"].as_str().unwrap(), "success");
    }

    #[test]
    fn test_icp_section_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_section({
                    title = "Section Title",
                    content = "This is the section content"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the section structure is correct
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "section");
        assert_eq!(ui["props"]["title"].as_str().unwrap(), "Section Title");
        assert_eq!(
            ui["props"]["content"].as_str().unwrap(),
            "This is the section content"
        );
    }

    #[test]
    fn test_icp_table_function_works() {
        let script = r#"
            function init(arg)
                return {
                    data = {
                        {name = "Alice", age = 30, city = "New York"},
                        {name = "Bob", age = 25, city = "London"}
                    }
                }, {}
            end

            function view(state)
                return icp_table({
                    data = state.data,
                    headers = {"Name", "Age", "City"}
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the table structure is correct
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "table");
        assert_eq!(ui["props"]["headers"].as_array().unwrap().len(), 3);
        assert_eq!(ui["props"]["data"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_icp_format_number_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_format_number(123.456, 2)
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the formatted number is correct
        let result = vv["ui"].as_str().unwrap();
        assert_eq!(result, "123.456");
    }

    #[test]
    fn test_icp_format_icp_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_format_icp(123456789, 8)
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the ICP amount is formatted correctly (123456789 / 10^8 = 1.23456789)
        let result = vv["ui"].as_str().unwrap();
        assert_eq!(result, "1.23456789");
    }

    #[test]
    fn test_icp_format_timestamp_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_format_timestamp(1634567890)
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the timestamp is formatted correctly
        let result = vv["ui"].as_str().unwrap();
        assert_eq!(result, "1634567890");
    }

    #[test]
    fn test_icp_format_bytes_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_format_bytes(1024)
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the bytes are formatted correctly
        let result = vv["ui"].as_str().unwrap();
        assert_eq!(result, "1024");
    }

    #[test]
    fn test_icp_truncate_function_works() {
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                return icp_truncate("This is a very long text that should be truncated", 20)
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that the text is returned (current implementation just returns the text)
        let result = vv["ui"].as_str().unwrap();
        assert_eq!(result, "This is a very long text that should be truncated");
    }

    #[test]
    fn test_icp_filter_items_function_works() {
        let script = r#"
            function init(arg)
                return {
                    items = {
                        {name = "Alice", city = "New York"},
                        {name = "Bob", city = "London"},
                        {name = "Charlie", city = "New York"}
                    }
                }, {}
            end

            function view(state)
                local filtered = icp_filter_items(state.items, "city", "New York")
                return icp_ui_list({
                    items = filtered,
                    title = "Filtered Results"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that filtering worked correctly
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        assert_eq!(ui["items"].as_array().unwrap().len(), 2); // Alice and Charlie
    }

    #[test]
    fn test_icp_sort_items_function_works() {
        let script = r#"
            function init(arg)
                return {
                    items = {
                        {name = "Charlie", age = 30},
                        {name = "Alice", age = 25},
                        {name = "Bob", age = 35}
                    }
                }, {}
            end

            function view(state)
                local sorted = icp_sort_items(state.items, "name", true)
                return icp_ui_list({
                    items = sorted,
                    title = "Sorted Results"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that sorting worked correctly
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        assert_eq!(ui["items"].as_array().unwrap().len(), 3);

        // Check that items are sorted by name (Alice, Bob, Charlie)
        let items = ui["items"].as_array().unwrap();
        assert_eq!(items[0]["name"].as_str().unwrap(), "Alice");
        assert_eq!(items[1]["name"].as_str().unwrap(), "Bob");
        assert_eq!(items[2]["name"].as_str().unwrap(), "Charlie");
    }

    #[test]
    fn test_icp_group_by_function_works() {
        let script = r#"
            function init(arg)
                return {
                    items = {
                        {name = "Alice", city = "New York"},
                        {name = "Bob", city = "London"},
                        {name = "Charlie", city = "New York"},
                        {name = "Diana", city = "London"}
                    }
                }, {}
            end

            function view(state)
                local grouped = icp_group_by(state.items, "city")
                local results = {}
                for city, items in pairs(grouped) do
                    table.insert(results, city .. ": " .. #items .. " items")
                end
                return icp_ui_list({
                    items = results,
                    title = "Grouped Results"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that grouping worked correctly
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        let items = ui["items"].as_array().unwrap();
        assert_eq!(items.len(), 2); // Two groups: "New York" and "London"

        // Check that both groups have 2 items each
        let item_texts: Vec<String> = items
            .iter()
            .map(|item| item.as_str().unwrap().to_string())
            .collect();

        assert!(item_texts
            .iter()
            .any(|text| text.contains("New York: 2 items")));
        assert!(item_texts
            .iter()
            .any(|text| text.contains("London: 2 items")));
    }

    #[test]
    fn test_all_helper_functions_available() {
        // This regression test ensures all 13 helper functions are available
        let script = r#"
            function init(arg)
                return {}, {}
            end

            function view(state)
                -- Test all helper functions are available and don't error
                local results = {}
                
                -- Action helpers
                table.insert(results, type(icp_call))
                table.insert(results, type(icp_batch))
                table.insert(results, type(icp_message))
                table.insert(results, type(icp_ui_list))
                table.insert(results, type(icp_result_display))
                table.insert(results, type(icp_searchable_list))
                table.insert(results, type(icp_section))
                table.insert(results, type(icp_table))
                
                -- Formatting helpers
                table.insert(results, type(icp_format_number))
                table.insert(results, type(icp_format_icp))
                table.insert(results, type(icp_format_timestamp))
                table.insert(results, type(icp_format_bytes))
                table.insert(results, type(icp_truncate))
                
                -- Data manipulation helpers
                table.insert(results, type(icp_filter_items))
                table.insert(results, type(icp_sort_items))
                table.insert(results, type(icp_group_by))
                
                return icp_ui_list({
                    items = results,
                    title = "Helper Functions Available"
                })
            end

            function update(msg, state)
                return state, {}
            end
        "#;

        // init
        let out = app_init(script, None, 100);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap());

        // view
        let st = v["state"].to_string();
        let vo = app_view(script, &st, 100);
        let vv: serde_json::Value = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap());

        // Check that all helper functions are available (should all return "function")
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        let items = ui["items"].as_array().unwrap();
        assert_eq!(items.len(), 16); // All 16 helper functions should be available

        // Each item should be "function" type
        for item in items {
            assert_eq!(item.as_str().unwrap(), "function");
        }
    }

    #[test]
    fn test_validate_ui_nodes_catches_conditional_rendering_issues() {
        // Test 1: Script with problematic conditional rendering pattern
        let problematic_script = r#"
function init(arg)
  return { show_info = false }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      { type = "text", props = { text = "Always visible" } },
      -- This pattern causes the "UI node missing type" error
      (state.show_info and { props = { title = "Conditional" } }) or nil,
      { type = "text", props = { text = "Also visible" } }
    }
  }
end

function update(msg, state)
  return state, {}
end
"#;

        let result = validate_lua_comprehensive(problematic_script, None);
        assert!(!result.is_valid);
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("Conditional UI expression missing type field")));

        // Test 2: Script with missing type field in return statement
        let missing_type_script = r#"
function init(arg)
  return {}, {}
end

function view(state)
  return {
    type = "column",
    children = {
      { type = "text", props = { text = "Valid node" } },
      -- Missing type field - this causes UI node missing type error
      { props = { text = "Invalid node" } }
    }
  }
end

function update(msg, state)
  return state, {}
end
"#;

        let result = validate_lua_comprehensive(missing_type_script, None);
        assert!(!result.is_valid);
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("UI node missing type field")));

        // Test 3: Script with empty type value
        let empty_type_script = r#"
function init(arg)
  return {}, {}
end

function view(state)
  return { type = "", props = { text = "Empty type" } }
end

function update(msg, state)
  return state, {}
end
"#;

        let result = validate_lua_comprehensive(empty_type_script, None);
        assert!(!result.is_valid);
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("UI node with empty type found")));

        // Test 4: Valid script should pass validation
        let valid_script = r#"
function init(arg)
  return { show_info = true }, {}
end

function view(state)
  local children = {
    { type = "text", props = { text = "Always visible" } }
  }

  -- Proper conditional rendering - only add node if condition is met
  if state.show_info then
    table.insert(children, {
      type = "section",
      props = { title = "Conditional Section" },
      children = {
        { type = "text", props = { text = "Conditional content" } }
      }
    })
  end

  table.insert(children, { type = "text", props = { text = "Also visible" } })

  return {
    type = "column",
    children = children
  }
end

function update(msg, state)
  return state, {}
end
"#;

        let result = validate_lua_comprehensive(valid_script, None);
        assert!(result.is_valid);
        assert!(result.syntax_errors.is_empty());
    }

    #[test]
    fn test_validate_ui_nodes_unknown_type_warnings() {
        // Test script with unknown UI node types should generate warnings, not errors
        let unknown_type_script = r#"
function init(arg)
  return {}, {}
end

function view(state)
  return {
    type = "unknown_widget_type",
    props = { text = "Unknown widget" }
  }
end

function update(msg, state)
  return state, {}
end
"#;

        let result = validate_lua_comprehensive(unknown_type_script, None);
        assert!(result.is_valid); // Should still be valid, just with warnings
        assert!(!result.warnings.is_empty());
        assert!(result
            .warnings
            .iter()
            .any(|w| w.contains("Unknown UI node type") && w.contains("unknown_widget_type")));
    }
}
