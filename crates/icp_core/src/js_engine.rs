#[derive(Debug, thiserror::Error)]
pub enum JsExecError {
    #[error("js error: {0}")]
    Js(String),
    #[error("json error: {0}")]
    Json(String),
}

#[derive(Debug, Clone)]
pub struct JsValidationContext {
    pub is_example: bool,
    pub is_test: bool,
    pub is_production: bool,
}

#[derive(Debug, Clone)]
pub struct JsValidationResult {
    pub is_valid: bool,
    pub syntax_errors: Vec<String>,
    pub warnings: Vec<String>,
    pub line_count: usize,
    pub character_count: usize,
}

pub mod static_analysis {
    use super::{JsValidationContext, JsValidationResult};

    pub fn fresh_result(script: &str) -> JsValidationResult {
        JsValidationResult {
            is_valid: true,
            syntax_errors: Vec::new(),
            warnings: Vec::new(),
            line_count: script.lines().count(),
            character_count: script.len(),
        }
    }

    pub fn default_context(script: &str) -> JsValidationContext {
        let is_example = is_example_script(script);
        let is_test = is_test_script(script);
        JsValidationContext {
            is_example,
            is_test,
            is_production: !is_example && !is_test,
        }
    }

    pub fn is_example_script(script: &str) -> bool {
        let lower = script.to_lowercase();
        lower.contains("// example")
            || lower.contains("// demo")
            || lower.contains("// tutorial")
            || lower.contains("// sample")
            || lower.contains("/* example")
            || lower.contains("/* demo")
    }

    pub fn is_test_script(script: &str) -> bool {
        let lower = script.to_lowercase();
        lower.contains("// test") || lower.contains("// spec") || lower.contains("// unit")
    }

    pub fn validate_basic(script: &str, result: &mut JsValidationResult) {
        if script.trim().is_empty() {
            result
                .syntax_errors
                .push("JavaScript source cannot be empty".to_string());
        }
    }

    pub fn validate_event_handlers(script: &str, result: &mut JsValidationResult) {
        let event_handler_regex =
            regex::Regex::new(r#"on(Press|Change|Submit|Input)\s*:\s*\{\s*type\s*:\s*"([^"]+)""#)
                .expect("valid regex");
        let mut event_handlers = Vec::new();
        for cap in event_handler_regex.captures_iter(script) {
            if let Some(handler) = cap.get(2) {
                event_handlers.push(handler.as_str().to_string());
            }
        }

        let message_type_regex =
            regex::Regex::new(r#"msg\.type\s*===?\s*"([^"]+)""#).expect("valid regex");
        let mut message_types = Vec::new();
        for cap in message_type_regex.captures_iter(script) {
            if let Some(msg_type) = cap.get(1) {
                message_types.push(msg_type.as_str().to_string());
            }
        }

        for handler in &event_handlers {
            if !message_types.contains(handler) && !handler.starts_with("effect/") {
                result.warnings.push(format!(
                    "Event handler '{}' has no corresponding case in update() function",
                    handler
                ));
            }
        }
        for msg_type in &message_types {
            if !event_handlers.contains(msg_type) && !msg_type.starts_with("effect/") {
                result.warnings.push(format!(
                    "Message handler '{}' has no corresponding UI event handler",
                    msg_type
                ));
            }
        }
    }

    pub fn validate_security_patterns(
        script: &str,
        context: &JsValidationContext,
        result: &mut JsValidationResult,
    ) {
        let dangerous_patterns: &[(&str, &str)] = &[
            (
                "eval(",
                "eval() detected - dynamic code execution not allowed",
            ),
            (
                "Function(",
                "Function() constructor detected - dynamic code execution not allowed",
            ),
            ("import(", "dynamic import() not allowed"),
            ("require(", "require() - module loading not allowed"),
            ("process.", "process access not allowed"),
            (
                "globalThis[",
                "globalThis property access by key not allowed",
            ),
            ("delete globalThis", "globalThis tampering not allowed"),
        ];
        for (pattern, message) in dangerous_patterns {
            if script.contains(pattern) {
                result.syntax_errors.push(message.to_string());
            }
        }

        if context.is_production {
            if script.contains("private_key") && (script.contains('"') || script.contains('\'')) {
                result.syntax_errors.push(
                    "Hardcoded private key detected - use environment variables or secure storage"
                        .to_string(),
                );
            }
            if (script.contains("password")
                || script.contains("token")
                || script.contains("api_key"))
                && (script.contains('"') || script.contains('\''))
                && script.len() > 100
            {
                result.syntax_errors.push(
                    "Potential hardcoded secret detected - use environment variables or secure storage"
                        .to_string(),
                );
            }
        } else if script.contains("sk-") || script.contains("pk_") {
            result
                .warnings
                .push("Potential real secret detected in example/test code".to_string());
        }

        if script.contains("<script") || script.contains("javascript:") {
            result
                .syntax_errors
                .push("Dangerous HTML/JavaScript pattern detected".to_string());
        }

        if script.contains("http://") || script.contains("https://") {
            let words: Vec<&str> = script.split_whitespace().collect();
            for word in words {
                if word.starts_with("http://") || word.starts_with("https://") {
                    let url = word.trim_matches(|c| {
                        c == ',' || c == ';' || c == ')' || c == '(' || c == '"' || c == '\''
                    });
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

    pub fn validate_icp_integration(
        script: &str,
        context: &JsValidationContext,
        result: &mut JsValidationResult,
    ) {
        let mut pos = 0;
        while let Some(canister_start) = script[pos..].find("canister_id") {
            let absolute_start = pos + canister_start;
            let remaining = &script[absolute_start..];

            if let Some(quote_start) = remaining.find(['"', '\'']) {
                let quote_char = remaining.as_bytes()[quote_start] as char;
                let quote_pos = absolute_start + quote_start;
                let after_quote = &script[quote_pos + 1..];
                if let Some(rel_end) = after_quote.find(quote_char) {
                    let absolute_end = quote_pos + 1 + rel_end;
                    let canister_id = &script[quote_pos + 1..absolute_end];

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

                    if canister_id.len() < 10
                        || canister_id.len() > 63
                        || !canister_id.contains('-')
                    {
                        if context.is_production {
                            result.syntax_errors.push(format!(
                                "Invalid canister ID format: {}. Expected format: xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxx-xxx",
                                canister_id
                            ));
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

        if script.contains(r#"kind: "icp_call""#)
            || script.contains(r#"kind:"icp_call""#)
            || script.contains(r#"kind: "icp_batch""#)
            || script.contains(r#"kind:"icp_batch""#)
        {
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

        if script.contains("canister_id") && script.contains("method") && script.contains("kind") {
            for line in script.lines() {
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

    pub fn validate_performance_patterns(
        script: &str,
        context: &JsValidationContext,
        result: &mut JsValidationResult,
    ) {
        if context.is_production {
            let infinite_loop_patterns = ["while (true)", "while(true)", "for (;;)", "for(;;)"];
            for pat in infinite_loop_patterns {
                if script.contains(pat) {
                    result
                        .warnings
                        .push("Possible infinite loop detected - ensure termination".to_string());
                    break;
                }
            }

            for line in script.lines().take(100) {
                let trimmed = line.trim();
                if let Some(rest) = trimmed
                    .strip_prefix("function ")
                    .or_else(|| trimmed.strip_prefix("const "))
                    .or_else(|| trimmed.strip_prefix("let "))
                {
                    if let Some(paren_start) = rest.find('(') {
                        let name_part = rest[..paren_start].trim();
                        let func_name = name_part.rsplit([' ', '=']).next().unwrap_or("").trim();
                        if !func_name.is_empty()
                            && func_name != "init"
                            && func_name != "view"
                            && func_name != "update"
                        {
                            let call_pattern = format!("{}(", func_name);
                            if script.matches(&call_pattern).count() > 1 {
                                result.warnings.push(format!(
                                    "Function '{}' may be recursive - ensure base case exists",
                                    func_name
                                ));
                            }
                        }
                    }
                }
            }
        }

        for word in script.split_whitespace() {
            if word.chars().all(|c| c.is_ascii_digit()) && word.len() >= 15 {
                result.warnings.push(
                    "Very large numbers detected - ensure they fit within safe integer limits"
                        .to_string(),
                );
                break;
            }
        }

        let push_count = script.matches(".push(").count();
        if push_count > 50 {
            result.warnings.push(
                "Many array.push operations detected - consider optimizing for better performance"
                    .to_string(),
            );
        }
    }

    pub fn validate_data_structures(
        script: &str,
        context: &JsValidationContext,
        result: &mut JsValidationResult,
    ) {
        if context.is_production {
            let mut state_fields = Vec::new();
            for line in script.lines() {
                let trimmed = line.trim();
                if let Some(rest) = trimmed.strip_prefix("state.") {
                    let field_end = rest
                        .find(|c: char| !c.is_alphanumeric() && c != '_')
                        .unwrap_or(rest.len());
                    let field = &rest[..field_end];
                    if !field.is_empty()
                        && ![
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

            for field in &state_fields {
                let init_pattern = format!("{}:", field);
                let init_pattern2 = format!("{} =", field);
                if !script.contains(&init_pattern) && !script.contains(&init_pattern2) {
                    result.warnings.push(format!(
                        "State field 'state.{}' may be undefined - ensure it's initialized in init()",
                        field
                    ));
                }
            }
        }

        if context.is_production
            && (script.contains("for (") || script.contains("for("))
            && script.contains("+")
            && script.contains("{")
        {
            let mut in_loop = false;
            let mut depth = 0i32;
            let mut concat_count = 0usize;
            for line in script.lines() {
                let trimmed = line.trim();
                if (trimmed.starts_with("for (") || trimmed.starts_with("for("))
                    && trimmed.contains('{')
                {
                    in_loop = true;
                    depth = 1;
                    concat_count = 0;
                    continue;
                }
                if in_loop {
                    depth += trimmed.matches('{').count() as i32;
                    depth -= trimmed.matches('}').count() as i32;
                    concat_count += trimmed.matches(".concat(").count();
                    if depth <= 0 {
                        if concat_count > 5 {
                            result.warnings.push(
                                "String concatenation in loop detected - consider using array.join for better performance"
                                    .to_string(),
                            );
                        }
                        in_loop = false;
                    }
                }
            }
        }

        let push_matches = script.matches(".push(").count();
        if push_matches > 100 {
            result.warnings.push(
                "Many array.push operations detected - consider pre-allocating arrays for better performance"
                    .to_string(),
            );
        }
    }

    pub fn validate_ui_nodes(script: &str, result: &mut JsValidationResult) {
        for line in script.lines() {
            if (line.contains("&& {") || line.contains("||{")) && !line.contains("type") {
                result.syntax_errors.push(
                    "Conditional UI expression missing type field - this will cause \"UI node missing type\" error"
                        .to_string(),
                );
            }
        }

        for line in script.lines() {
            if (line.contains("type:") || line.contains("type :"))
                && (line.contains("\"type\":\"\"")
                    || line.contains("\"type\": \"\"")
                    || line.contains("type: \"\"")
                    || line.contains("type:\"\"")
                    || line.contains("type: ''")
                    || line.contains("type:''"))
            {
                result
                    .syntax_errors
                    .push("UI node with empty type found".to_string());
            }
        }

        let valid_types = [
            "column", "row", "section", "text", "button", "toggle", "input",
        ];
        for line in script.lines() {
            if let Some(idx) = line.find("type:") {
                let after = &line[idx + "type:".len()..];
                let trimmed_part = after.trim_start();
                let quote = match trimmed_part.chars().next() {
                    Some('"') => '"',
                    Some('\'') => '\'',
                    _ => continue,
                };
                let rest = &trimmed_part[quote.len_utf8()..];
                if let Some(end) = rest.find(quote) {
                    let type_value = &rest[..end];
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

        if script.contains("return {") || script.contains("return{") {
            let mut in_return = false;
            let mut brace_count = 0i32;
            for line in script.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("return {") || trimmed.starts_with("return{") {
                    in_return = true;
                    brace_count =
                        trimmed.matches('{').count() as i32 - trimmed.matches('}').count() as i32;
                    continue;
                }
                if in_return {
                    brace_count += trimmed.matches('{').count() as i32;
                    brace_count -= trimmed.matches('}').count() as i32;
                    if trimmed.contains('{')
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

    pub fn run_static_stages(
        script: &str,
        context: Option<JsValidationContext>,
    ) -> JsValidationResult {
        let ctx = context.unwrap_or_else(|| default_context(script));
        let mut result = fresh_result(script);
        validate_basic(script, &mut result);
        validate_event_handlers(script, &mut result);
        validate_security_patterns(script, &ctx, &mut result);
        validate_icp_integration(script, &ctx, &mut result);
        validate_performance_patterns(script, &ctx, &mut result);
        validate_data_structures(script, &ctx, &mut result);
        validate_ui_nodes(script, &mut result);
        result.is_valid = result.syntax_errors.is_empty();
        result
    }
}

#[cfg(not(target_arch = "wasm32"))]
mod runtime;

#[cfg(not(target_arch = "wasm32"))]
pub use runtime::{
    execute_js_json, js_app_init, js_app_update, js_app_view, lint_js, validate_js_comprehensive,
};

#[cfg(test)]
#[cfg(not(target_arch = "wasm32"))]
mod tests {
    use super::*;
    use crate::lua_engine;
    use rquickjs::{Ctx, Value};
    use runtime::{
        create_sandboxed_js, install_host_globals, js_value_to_json_string, DEFAULT_BUDGET_MS,
    };
    use serde_json::Value as JsonValue;
    use std::time::{Duration, Instant};

    fn far_deadline() -> Instant {
        Instant::now() + Duration::from_secs(5)
    }

    #[test]
    fn rquickjs_links() {
        let rt = rquickjs::Runtime::new().expect("quickjs runtime");
        let ctx = rquickjs::Context::full(&rt).expect("quickjs context");
        let v: i64 = ctx.with(|c| c.eval::<i64, _>("6 * 7")).expect("eval works");
        assert_eq!(v, 42);
        let _ = rt;
    }

    #[test]
    fn eval_returns_value() {
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, far_deadline()).unwrap();
        let v: i64 = ctx.with(|c| c.eval::<i64, _>("1 + 2 + 3")).expect("eval");
        assert_eq!(v, 6);
    }

    #[test]
    fn memory_limit_aborts_oom() {
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, far_deadline()).unwrap();
        let res = ctx.with(|c| c.eval::<(), _>("new Uint8Array(100 * 1024 * 1024).length"));
        assert!(res.is_err(), "expected allocation to be aborted");
    }

    #[test]
    fn interrupt_aborts_infinite_loop() {
        let deadline = Instant::now() + Duration::from_millis(50);
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, deadline).unwrap();
        let res = ctx.with(|c| c.eval::<(), _>("var i = 0; while (true) { i = i + 1; }"));
        assert!(res.is_err(), "expected infinite loop to be interrupted");
    }

    #[test]
    fn os_and_require_disabled() {
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, far_deadline()).unwrap();
        let kind: String = ctx
            .with(|c| {
                c.eval::<String, _>("typeof os + ',' + typeof require + ',' + typeof process")
            })
            .expect("eval");
        assert_eq!(kind, "undefined,undefined,undefined");
    }

    #[test]
    fn arg_roundtrip() {
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, far_deadline()).unwrap();
        ctx.with(|c| {
            install_host_globals(&c, Some(r#"{"a": 1}"#)).unwrap();
            let v: i64 = c.eval::<i64, _>("get_arg().a").unwrap();
            assert_eq!(v, 1);
        });
    }

    #[test]
    fn native_json_available() {
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, far_deadline()).unwrap();
        ctx.with(|c| {
            install_host_globals(&c, None).unwrap();
            let v: i64 = c
                .eval::<i64, _>("JSON.parse(JSON.stringify({x: 10, y: 20})).x + 10")
                .unwrap();
            assert_eq!(v, 20);
        });
    }

    #[test]
    fn icp_log_populates_messages() {
        let (_rt, ctx) = create_sandboxed_js(8 * 1024 * 1024, far_deadline()).unwrap();
        ctx.with(|c: Ctx| {
            install_host_globals(&c, None).unwrap();
            c.eval::<(), _>("icp_log('hello'); icp_log('world');")
                .unwrap();
            let s =
                js_value_to_json_string(&c, c.globals().get::<_, Value>("__icp_messages").unwrap())
                    .unwrap();
            let arr: JsonValue = serde_json::from_str(&s).unwrap();
            assert_eq!(arr, serde_json::json!(["hello", "world"]));
        });
    }

    #[test]
    fn simple_math() {
        let out = execute_js_json("1 + 2", None).unwrap();
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(v.get("ok").and_then(|b| b.as_bool()).unwrap());
        assert_eq!(v.get("result").and_then(|x| x.as_i64()).unwrap(), 3);
        assert_eq!(v.get("messages").unwrap(), &serde_json::json!([]));
    }

    #[test]
    fn with_arg_roundtrip() {
        let out = execute_js_json("get_arg().a", Some(r#"{"a": 1}"#)).unwrap();
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert_eq!(v["result"].as_i64().unwrap(), 1);
    }

    #[test]
    fn json_helpers() {
        let out = execute_js_json(
            "JSON.parse(JSON.stringify({x: 10, y: 20})).x + JSON.parse(JSON.stringify({x: 10, y: 20})).y",
            None,
        )
        .unwrap();
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert_eq!(v["result"].as_i64().unwrap(), 30);
    }

    #[test]
    fn execute_returns_err_on_syntax_error() {
        let err = execute_js_json("function(}", None).unwrap_err();
        assert!(matches!(err, JsExecError::Js(_)));
    }

    #[test]
    fn execute_returns_err_on_runtime_error() {
        let err = execute_js_json("(function(){ null.x; })()", None).unwrap_err();
        assert!(matches!(err, JsExecError::Js(_)));
    }

    #[test]
    fn execute_returns_json_error_on_bad_arg() {
        let err = execute_js_json("1", Some("not-json")).unwrap_err();
        assert!(matches!(err, JsExecError::Json(_)));
    }

    fn run_helper_in_js(helper_call: &str) -> JsonValue {
        let script = format!("({})", helper_call);
        let out = execute_js_json(&script, None).unwrap();
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        v["result"].clone()
    }

    fn run_helper_in_lua(lua_call: &str) -> JsonValue {
        let script = format!(
            r#"
                function init(arg) return {{}}, {{}} end
                function view(state) return {} end
                function update(msg, state) return state, {{}} end
            "#,
            lua_call
        );
        let out = lua_engine::app_view(&script, "{}", 1000);
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        v["ui"].clone()
    }

    #[test]
    fn helper_icp_call() {
        let js = run_helper_in_js("icp_call({ canister: 'a-b', method: 'm', args: {} })");
        assert_eq!(js["action"], "call");
        assert_eq!(js["canister"], "a-b");
        assert_eq!(js["method"], "m");
    }

    #[test]
    fn helper_icp_call_no_arg() {
        let js = run_helper_in_js("icp_call()");
        assert_eq!(js["action"], "call");
    }

    #[test]
    fn helper_icp_batch() {
        let js = run_helper_in_js("icp_batch({ calls: [ { canister: 'a' }, { canister: 'b' } ] })");
        assert_eq!(js["action"], "batch");
        assert_eq!(js["calls"]["calls"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn helper_icp_message() {
        let js = run_helper_in_js("icp_message({ text: 'Hello', type: 'info' })");
        assert_eq!(js["action"], "message");
        assert_eq!(js["text"], "Hello");
        assert_eq!(js["type"], "info");
    }

    #[test]
    fn helper_icp_message_defaults() {
        let js = run_helper_in_js("icp_message()");
        assert_eq!(js["text"], "");
        assert_eq!(js["type"], "info");
    }

    #[test]
    fn helper_icp_ui_list() {
        let js = run_helper_in_js("icp_ui_list({ items: ['a', 'b', 'c'] })");
        assert_eq!(js["ui"]["type"], "list");
        assert_eq!(js["ui"]["items"].as_array().unwrap().len(), 3);
        assert!(js["ui"]["buttons"].is_array());
    }

    #[test]
    fn helper_icp_result_display() {
        let js = run_helper_in_js("icp_result_display({ result: 'ok', type: 'success' })");
        assert_eq!(js["ui"]["type"], "result_display");
        assert_eq!(js["ui"]["props"]["result"], "ok");
        assert_eq!(js["ui"]["props"]["type"], "success");
    }

    #[test]
    fn helper_icp_searchable_list() {
        let js = run_helper_in_js(
            "icp_searchable_list({ items: [1, 2], title: 'Recent', searchable: true })",
        );
        assert_eq!(js["ui"]["type"], "list");
        assert_eq!(js["ui"]["props"]["searchable"], true);
        assert_eq!(js["ui"]["props"]["title"], "Recent");
        assert_eq!(js["ui"]["props"]["items"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn helper_icp_searchable_list_default_true() {
        let js = run_helper_in_js("icp_searchable_list({ items: [1] })");
        assert_eq!(js["ui"]["props"]["searchable"], true);
    }

    #[test]
    fn helper_icp_section() {
        let js = run_helper_in_js("icp_section({ title: 'T', content: 'C' })");
        assert_eq!(js["ui"]["type"], "section");
        assert_eq!(js["ui"]["props"]["title"], "T");
        assert_eq!(js["ui"]["props"]["content"], "C");
    }

    #[test]
    fn helper_icp_table() {
        let js = run_helper_in_js("icp_table({ data: [{a:1}], headers: ['a'] })");
        assert_eq!(js["ui"]["type"], "table");
        assert_eq!(js["ui"]["props"]["headers"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn helper_icp_format_number() {
        assert_eq!(run_helper_in_js("icp_format_number(123.456, 2)"), "123.456");
    }

    #[test]
    fn helper_icp_format_number_invalid() {
        assert_eq!(run_helper_in_js("icp_format_number('abc')"), "0");
    }

    #[test]
    fn helper_icp_format_icp() {
        assert_eq!(
            run_helper_in_js("icp_format_icp(123456789, 8)"),
            "1.23456789"
        );
    }

    #[test]
    fn helper_icp_format_timestamp() {
        assert_eq!(
            run_helper_in_js("icp_format_timestamp(1634567890)"),
            "1634567890"
        );
    }

    #[test]
    fn helper_icp_format_bytes() {
        assert_eq!(run_helper_in_js("icp_format_bytes(1024)"), "1024");
    }

    #[test]
    fn helper_icp_truncate_is_identity() {
        assert_eq!(
            run_helper_in_js("icp_truncate('a long text here', 5)"),
            "a long text here"
        );
    }

    #[test]
    fn helper_icp_filter_items() {
        let js = run_helper_in_js("icp_filter_items([{c:'NY'},{c:'LA'},{c:'NY'}], 'c', 'NY')");
        assert_eq!(js.as_array().unwrap().len(), 2);
    }

    #[test]
    fn helper_icp_sort_items_ascending() {
        let js = run_helper_in_js("icp_sort_items([{n:'C'},{n:'A'},{n:'B'}], 'n', true)");
        let arr = js.as_array().unwrap();
        assert_eq!(arr[0]["n"], "A");
        assert_eq!(arr[1]["n"], "B");
        assert_eq!(arr[2]["n"], "C");
    }

    #[test]
    fn helper_icp_sort_items_descending() {
        let js = run_helper_in_js("icp_sort_items([{n:'A'},{n:'C'},{n:'B'}], 'n', false)");
        let arr = js.as_array().unwrap();
        assert_eq!(arr[0]["n"], "C");
        assert_eq!(arr[1]["n"], "B");
        assert_eq!(arr[2]["n"], "A");
    }

    #[test]
    fn helper_icp_group_by() {
        let js =
            run_helper_in_js("icp_group_by([{c:'NY',n:'A'},{c:'LA',n:'B'},{c:'NY',n:'C'}], 'c')");
        assert_eq!(js["NY"].as_array().unwrap().len(), 2);
        assert_eq!(js["LA"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn parity_oracle_helpers_match_lua() {
        let cases: &[(&str, &str)] = &[
            ("icp_call({ canister: 'rrkah-fqaaa-aaaaa-aaaaq-cai', method: 'get_balance', args: {} })",
             "icp_call({ canister = 'rrkah-fqaaa-aaaaa-aaaaq-cai', method = 'get_balance', args = {} })"),
            ("icp_batch({ calls: [{ canister: 'a' }, { canister: 'b' }] })",
             "icp_batch({ calls = { { canister = 'a' }, { canister = 'b' } } })"),
            ("icp_message({ text: 'Hello', type: 'info' })",
             "icp_message({ text = 'Hello', type = 'info' })"),
            ("icp_ui_list({ items: ['a','b','c'], buttons: ['click'] })",
             "icp_ui_list({ items = {'a','b','c'}, buttons = {'click'} })"),
            ("icp_result_display({ result: 'ok', type: 'success' })",
             "icp_result_display({ result = 'ok', type = 'success' })"),
            ("icp_searchable_list({ items: [1,2], title: 'Recent', searchable: true })",
             "icp_searchable_list({ items = {1,2}, title = 'Recent', searchable = true })"),
            ("icp_section({ title: 'T', content: 'C' })",
             "icp_section({ title = 'T', content = 'C' })"),
            ("icp_table({ data: [{a:1}], headers: ['a'] })",
             "icp_table({ data = {{a=1}}, headers = {'a'} })"),
            ("icp_format_number(123.456, 2)", "icp_format_number(123.456, 2)"),
            ("icp_format_icp(123456789, 8)", "icp_format_icp(123456789, 8)"),
            ("icp_format_timestamp(1634567890)", "icp_format_timestamp(1634567890)"),
            ("icp_format_bytes(1024)", "icp_format_bytes(1024)"),
            ("icp_truncate('text', 5)", "icp_truncate('text', 5)"),
            ("icp_filter_items([{c:'NY'},{c:'LA'}], 'c', 'NY')",
             "icp_filter_items({{c='NY'},{c='LA'}}, 'c', 'NY')"),
            ("icp_sort_items([{n:'C'},{n:'A'},{n:'B'}], 'n', true)",
             "icp_sort_items({{n='C'},{n='A'},{n='B'}}, 'n', true)"),
            ("icp_group_by([{c:'NY'},{c:'LA'},{c:'NY'}], 'c')",
             "icp_group_by({{c='NY'},{c='LA'},{c='NY'}}, 'c')"),
        ];
        for (js_call, lua_call) in cases {
            let js_result = run_helper_in_js(js_call);
            let lua_result = run_helper_in_lua(lua_call);
            assert_eq!(
                js_result, lua_result,
                "parity mismatch for `{}` vs `{}`\n JS: {}\nLua: {}",
                js_call, lua_call, js_result, lua_result,
            );
        }
    }

    #[test]
    fn app_init_view_update_roundtrip() {
        let script = r#"
            function init(arg) {
                var start = (arg && arg.start) || 0;
                return { state: { count: start, last: null }, effects: [] };
            }
            function view(state) {
                return { type: "column", props: {}, children: [
                    { type: "text", props: { text: String(state.count) } }
                ] };
            }
            function update(msg, state) {
                var t = (msg && msg.type) || "";
                if (t === "inc") { state.count = (state.count || 0) + 1; }
                state.last = msg;
                return { state: state, effects: [] };
            }
        "#;

        let out = js_app_init(script, Some(r#"{"start":1}"#), 200);
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap(), "init ok: {}", out);
        assert_eq!(v["state"]["count"].as_i64().unwrap(), 1);

        let st = v["state"].to_string();
        let vo = js_app_view(script, &st, 200);
        let vv: JsonValue = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap(), "view ok: {}", vo);
        assert_eq!(vv["ui"]["type"].as_str().unwrap(), "column");

        let upo = js_app_update(script, r#"{"type":"inc"}"#, &st, 200);
        let vu: JsonValue = serde_json::from_str(&upo).unwrap();
        assert!(vu["ok"].as_bool().unwrap(), "update ok: {}", upo);
        assert_eq!(vu["state"]["count"].as_i64().unwrap(), 2);
        assert!(vu["effects"].is_array());
    }

    #[test]
    fn app_init_timeout() {
        let script = r#"
            function init(arg) {
                var i = 0;
                while (true) { i = i + 1; }
                return { state: {}, effects: [] };
            }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let out = js_app_init(script, None, 1);
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(!v["ok"].as_bool().unwrap());
        let err = v["error"].as_str().unwrap().to_lowercase();
        assert!(
            err.contains("timeout") || err.contains("execution"),
            "error was: {}",
            err
        );
    }

    #[test]
    fn app_view_invalid_state_json() {
        let script = r#"
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return { type: "text", props: { text: "ok" } }; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let out = js_app_view(script, "not-json", 50);
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(!v["ok"].as_bool().unwrap());
        assert!(v["error"].as_str().unwrap().contains("invalid state JSON"));
    }

    #[test]
    fn app_update_invalid_msg_json() {
        let script = r#"
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let out = js_app_update(script, "not-json", "{}", 50);
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(!v["ok"].as_bool().unwrap());
        assert!(v["error"].as_str().unwrap().contains("invalid msg JSON"));
    }

    #[test]
    fn sample_app_default_works() {
        let script = r#"
            function init(arg) {
                return {
                    state: { count: 0, items: [], last: null },
                    effects: []
                };
            }
            function view(state) {
                var children = [{
                    type: "section", props: { title: "Sample UI-enabled Script" }, children: [
                        { type: "text", props: { text: "Counter: " + String(state.count || 0) } },
                        { type: "row", children: [
                            { type: "button", props: { label: "Increment", onPress: { type: "inc" } } },
                            { type: "button", props: { label: "Load ICP samples", onPress: { type: "load_sample" } } }
                        ] }
                    ]
                }];
                var items = state.items || [];
                if (Array.isArray(items) && items.length > 0) {
                    children.push({ type: "section", props: { title: "Loaded results" }, children: [
                        { type: "list", props: { items: items } }
                    ] });
                }
                return { type: "column", children: children };
            }
            function update(msg, state) {
                var t = (msg && msg.type) || "";
                if (t === "inc") {
                    state.count = (state.count || 0) + 1;
                    return { state: state, effects: [] };
                }
                if (t === "load_sample") {
                    var gov = { label: "gov", kind: 0, canister_id: "rrkah-fqaaa-aaaaa-aaaaq-cai", method: "get_pending_proposals", args: "()" };
                    var ledger = { label: "ledger", kind: 0, canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai", method: "query_blocks", args: '{"start":0,"length":3}' };
                    return { state: state, effects: [{ kind: "icp_batch", id: "load", items: [gov, ledger] }] };
                }
                state.last = msg;
                return { state: state, effects: [] };
            }
        "#;

        let out = js_app_init(script, None, 200);
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(v["ok"].as_bool().unwrap(), "{}", out);
        assert_eq!(v["state"]["count"].as_i64().unwrap(), 0);

        let st = v["state"].to_string();
        let vo = js_app_view(script, &st, 200);
        let vv: JsonValue = serde_json::from_str(&vo).unwrap();
        assert!(vv["ok"].as_bool().unwrap(), "{}", vo);
        assert_eq!(vv["ui"]["type"].as_str().unwrap(), "column");

        let upo = js_app_update(script, r#"{"type":"inc"}"#, &st, 200);
        let vu: JsonValue = serde_json::from_str(&upo).unwrap();
        assert!(vu["ok"].as_bool().unwrap(), "{}", upo);
        assert_eq!(vu["state"]["count"].as_i64().unwrap(), 1);

        let up2 = js_app_update(script, r#"{"type":"load_sample"}"#, &st, 200);
        let v2: JsonValue = serde_json::from_str(&up2).unwrap();
        assert!(v2["ok"].as_bool().unwrap(), "{}", up2);
        let eff = &v2["effects"];
        assert!(eff.is_array());
        let arr = eff.as_array().unwrap();
        assert!(!arr.is_empty());
        assert_eq!(arr[0]["kind"].as_str().unwrap(), "icp_batch");
        assert_eq!(arr[0]["items"].as_array().unwrap().len(), 2);
    }

    fn prod_ctx() -> JsValidationContext {
        JsValidationContext {
            is_example: false,
            is_test: false,
            is_production: true,
        }
    }

    #[test]
    fn validate_valid_production_script() {
        let script = r#"
            function init(arg) {
                return { state: { count: 0 }, effects: [] };
            }
            function view(state) {
                return { type: "text", props: { text: "Count: " + String(state.count) } };
            }
            function update(msg, state) {
                if (msg.type === "inc") {
                    state.count = state.count + 1;
                    return { state: state, effects: [] };
                }
                return { state: state, effects: [] };
            }
        "#;
        let result = validate_js_comprehensive(script, Some(prod_ctx()));
        assert!(result.is_valid, "errors: {:?}", result.syntax_errors);
        assert!(result.syntax_errors.is_empty());
        assert!(result.character_count > 0);
    }

    #[test]
    fn validate_blocks_eval() {
        let script = r#"
            function init(arg) { eval("1"); return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let result = validate_js_comprehensive(script, Some(prod_ctx()));
        assert!(!result.is_valid);
        assert!(result.syntax_errors.iter().any(|e| e.contains("eval")));
    }

    #[test]
    fn validate_blocks_function_constructor_and_require() {
        let script = r#"
            var x = Function("return 1");
            var y = require("fs");
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let result = validate_js_comprehensive(script, Some(prod_ctx()));
        assert!(result.syntax_errors.iter().any(|e| e.contains("Function")));
        assert!(result.syntax_errors.iter().any(|e| e.contains("require")));
    }

    #[test]
    fn validate_example_warns_on_secret_not_error() {
        let script = r#"
            // EXAMPLE: demo
            function init(arg) {
                var pk = "sk-test123456789";
                return { state: { key: pk }, effects: [] };
            }
            function view(state) { return {}; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let result = validate_js_comprehensive(
            script,
            Some(JsValidationContext {
                is_example: true,
                is_test: false,
                is_production: false,
            }),
        );
        assert!(result.is_valid, "errors: {:?}", result.syntax_errors);
        assert!(result.warnings.iter().any(|w| w.contains("secret")));
    }

    #[test]
    fn validate_missing_required_functions() {
        let script = r#"
            function init(arg) { return { state: {}, effects: [] }; }
        "#;
        let result = validate_js_comprehensive(script, Some(prod_ctx()));
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
    fn validate_syntax_error_reported() {
        let result = validate_js_comprehensive("function init(arg) {", Some(prod_ctx()));
        assert!(!result.is_valid);
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("Syntax error")));
    }

    #[test]
    fn validate_ui_nodes_unknown_type_warns() {
        let script = r#"
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) {
                return { type: "unknown_widget_type", props: { text: "x" } };
            }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let result = validate_js_comprehensive(script, Some(prod_ctx()));
        assert!(result.is_valid, "errors: {:?}", result.syntax_errors);
        assert!(result
            .warnings
            .iter()
            .any(|w| w.contains("Unknown UI node type") && w.contains("unknown_widget_type")));
    }

    #[test]
    fn validate_ui_nodes_empty_type_errors() {
        let script = r#"
            function init(arg) { return { state: {}, effects: [] }; }
            function view(state) { return { type: "", props: { text: "x" } }; }
            function update(msg, state) { return { state: state, effects: [] }; }
        "#;
        let result = validate_js_comprehensive(script, Some(prod_ctx()));
        assert!(!result.is_valid);
        assert!(result
            .syntax_errors
            .iter()
            .any(|e| e.contains("empty type")));
    }

    #[test]
    fn lint_js_returns_json_shape() {
        let out = lint_js("function init(arg){ return {state:{},effects:[]}; }\nfunction view(s){return {};}\nfunction update(m,s){return {state:s,effects:[]};}");
        let v: JsonValue = serde_json::from_str(&out).unwrap();
        assert!(v.get("ok").is_some());
        assert!(v.get("errors").unwrap().is_array());
        assert!(v.get("warnings").unwrap().is_array());
        assert!(v.get("line_count").is_some());
        assert!(v.get("character_count").is_some());
    }

    #[test]
    fn static_analysis_runs_without_rquickjs() {
        let result = static_analysis::run_static_stages(
            "function init(arg){ return {state:{},effects:[]}; }",
            None,
        );
        assert!(result.character_count > 0);
    }

    #[test]
    fn static_analysis_catches_eval_without_engine() {
        let result = static_analysis::run_static_stages(
            "eval('1'); function init(){} function view(){} function update(){}",
            Some(JsValidationContext {
                is_example: false,
                is_test: false,
                is_production: true,
            }),
        );
        assert!(!result.is_valid);
        assert!(result.syntax_errors.iter().any(|e| e.contains("eval")));
    }

    #[test]
    fn static_analysis_context_detection() {
        assert!(static_analysis::is_example_script("// Example script"));
        assert!(static_analysis::is_test_script("// test case"));
        assert!(!static_analysis::is_example_script("function init(){}"));
    }

    #[test]
    fn budget_default_applied_when_zero() {
        assert_eq!(DEFAULT_BUDGET_MS, 100);
    }
}
