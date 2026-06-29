use super::static_analysis;
use super::{JsExecError, JsValidationContext, JsValidationResult};
use rquickjs::{Context, Ctx, Error, Function, Runtime, Value};
use serde_json::{json, Value as JsonValue};
use std::time::{Duration, Instant};

const MEM_LIMIT: usize = 64 * 1024 * 1024;
const STACK_LIMIT: usize = 512 * 1024;
pub(super) const DEFAULT_BUDGET_MS: u64 = 100;

fn js_error_string(e: Error) -> String {
    match e {
        Error::Exception => "JavaScript exception".to_string(),
        other => other.to_string(),
    }
}

pub(super) fn create_sandboxed_js(
    memory_limit: usize,
    deadline: Instant,
) -> rquickjs::Result<(Runtime, Context)> {
    let rt = Runtime::new()?;
    rt.set_memory_limit(memory_limit);
    rt.set_max_stack_size(STACK_LIMIT);
    rt.set_interrupt_handler(Some(Box::new(move || Instant::now() > deadline)));
    let ctx = Context::full(&rt)?;
    Ok((rt, ctx))
}

fn deadline_from_budget(budget_ms: u64) -> Instant {
    let ms = if budget_ms == 0 {
        DEFAULT_BUDGET_MS
    } else {
        budget_ms
    };
    Instant::now() + Duration::from_millis(ms)
}

fn set_arg_global<'js>(
    ctx: &Ctx<'js>,
    json_arg: Option<&str>,
) -> std::result::Result<(), JsExecError> {
    let globals = ctx.globals();
    match json_arg {
        Some(s) => {
            serde_json::from_str::<JsonValue>(s).map_err(|e| JsExecError::Json(e.to_string()))?;
            globals
                .set("__icp_arg_raw__", s)
                .map_err(|e| JsExecError::Js(js_error_string(e)))?;
            ctx.eval::<(), _>("globalThis.arg = JSON.parse(__icp_arg_raw__);")
                .map_err(|e| JsExecError::Js(js_error_string(e)))?;
            globals
                .remove("__icp_arg_raw__")
                .map_err(|e| JsExecError::Js(js_error_string(e)))?;
        }
        None => {
            ctx.eval::<(), _>("globalThis.arg = null;")
                .map_err(|e| JsExecError::Js(js_error_string(e)))?;
        }
    }
    Ok(())
}

const HOST_BOOTSTRAP_JS: &str = r#"
var __icp_messages = [];
function icp_log(msg){ __icp_messages.push(String(msg)); }
function get_arg(){ return arg; }

function icp_call(spec){ spec = spec || {}; spec.action = "call"; return spec; }
function icp_batch(calls){ return { action: "batch", calls: calls || [] }; }
function icp_message(spec){ spec = spec || {}; return { action: "message", text: String((spec && spec.text != null) ? spec.text : ""), type: String((spec && spec.type != null) ? spec.type : "info") }; }
function icp_ui_list(spec){ spec = spec || {}; return { action: "ui", ui: { type: "list", items: (spec && spec.items) || [], buttons: (spec && spec.buttons) || [] } }; }
function icp_result_display(spec){ return { action: "ui", ui: { type: "result_display", props: spec } }; }
function icp_searchable_list(spec){ spec = spec || {}; return { action: "ui", ui: { type: "list", props: { searchable: !spec || spec.searchable !== false, items: (spec && spec.items) || [], title: (spec && spec.title) || "Results" } } }; }
function icp_section(spec){ spec = spec || {}; return { action: "ui", ui: { type: "section", props: { title: (spec && spec.title) || "", content: (spec && spec.content) || "" } } }; }
function icp_table(data){ return { action: "ui", ui: { type: "table", props: data } }; }
function icp_format_number(value, decimals){ return String(Number(value) || 0); }
function icp_format_icp(value, decimals){ var d = (decimals == null) ? 8 : decimals; return String((Number(value) || 0) / Math.pow(10, d)); }
function icp_format_timestamp(value){ return String(Number(value) || 0); }
function icp_format_bytes(value){ return String(Number(value) || 0); }
function icp_truncate(text, maxLen){ return String(text); }
function icp_filter_items(items, field, value){ return (items || []).filter(function(it){ return String((it && it[field] != null) ? it[field] : "").indexOf(String(value)) !== -1; }); }
function icp_sort_items(items, field, ascending){ return (items || []).slice().sort(function(a, b){ var av = String((a && a[field] != null) ? a[field] : ""); var bv = String((b && b[field] != null) ? b[field] : ""); if (ascending) { return av < bv ? -1 : (av > bv ? 1 : 0); } return av > bv ? -1 : (av < bv ? 1 : 0); }); }
function icp_group_by(items, field){ return (items || []).reduce(function(g, it){ var k = String((it && it[field] != null) ? it[field] : "unknown"); if (!g[k]) { g[k] = []; } g[k].push(it); return g; }, {}); }
"#;

const NEUTRALIZE_EVAL_JS: &str = r#"
globalThis.eval = function(){ throw new Error('eval is disabled in sandbox'); };
globalThis.Function = function(){ throw new Error('Function constructor is disabled in sandbox'); };
"#;

pub(super) fn install_host_globals<'js>(
    ctx: &Ctx<'js>,
    json_arg: Option<&str>,
) -> std::result::Result<(), JsExecError> {
    set_arg_global(ctx, json_arg)?;
    ctx.eval::<(), _>(HOST_BOOTSTRAP_JS)
        .map_err(|e| JsExecError::Js(js_error_string(e)))?;
    ctx.eval::<(), _>(NEUTRALIZE_EVAL_JS)
        .map_err(|e| JsExecError::Js(js_error_string(e)))?;
    Ok(())
}

pub(super) fn js_value_to_json_string<'js>(
    ctx: &Ctx<'js>,
    val: Value<'js>,
) -> std::result::Result<String, Error> {
    let globals = ctx.globals();
    globals.set("__icp_res__", val)?;
    let s: String = ctx.eval(
        "(typeof __icp_res__ === 'undefined' || __icp_res__ === null) ? 'null' : JSON.stringify(__icp_res__)",
    )?;
    globals.remove("__icp_res__")?;
    Ok(s)
}

fn messages_to_json<'js>(ctx: &Ctx<'js>) -> std::result::Result<String, Error> {
    let s: String = ctx.eval("JSON.stringify(__icp_messages)")?;
    Ok(s)
}

pub fn execute_js_json(
    script: &str,
    json_arg: Option<&str>,
) -> std::result::Result<String, JsExecError> {
    let arg_str = match json_arg {
        Some(s) => {
            serde_json::from_str::<JsonValue>(s).map_err(|e| JsExecError::Json(e.to_string()))?;
            Some(s)
        }
        None => None,
    };

    let deadline = Instant::now() + Duration::from_millis(DEFAULT_BUDGET_MS);
    let (rt, ctx) = create_sandboxed_js(MEM_LIMIT, deadline).map_err(|e| {
        JsExecError::Js(format!("failed to create runtime: {}", js_error_string(e)))
    })?;

    let outcome = ctx.with(
        |ctx| -> std::result::Result<(String, String), JsExecError> {
            install_host_globals(&ctx, arg_str)?;
            let result_val: Value = ctx
                .eval(script)
                .map_err(|e| JsExecError::Js(js_error_string(e)))?;
            let result_json = js_value_to_json_string(&ctx, result_val)
                .map_err(|e| JsExecError::Js(js_error_string(e)))?;
            let messages_json =
                messages_to_json(&ctx).map_err(|e| JsExecError::Js(js_error_string(e)))?;
            Ok((result_json, messages_json))
        },
    );

    drop(ctx);
    drop(rt);

    let (result_json, messages_json) = outcome?;
    let result_value: JsonValue =
        serde_json::from_str(&result_json).map_err(|e| JsExecError::Js(e.to_string()))?;
    let messages: Vec<String> =
        serde_json::from_str(&messages_json).map_err(|e| JsExecError::Js(e.to_string()))?;
    let response = json!({
        "ok": true,
        "result": result_value,
        "messages": messages,
    });
    Ok(response.to_string())
}

fn check_js_syntax(script: &str) -> std::result::Result<(), String> {
    let rt = Runtime::new().map_err(js_error_string)?;
    let ctx = Context::full(&rt).map_err(js_error_string)?;
    let res = ctx.with(|ctx| -> std::result::Result<(), Error> {
        let val: Value = ctx.eval(script)?;
        let _ = val;
        Ok(())
    });
    res.map_err(|e| format!("Syntax error: {}", e))
}

fn check_js_required_exports<'js>(ctx: &Ctx<'js>) -> std::result::Result<bool, Error> {
    let globals = ctx.globals();
    let has_init: bool = globals.contains_key("init")?;
    let has_view: bool = globals.contains_key("view")?;
    let has_update: bool = globals.contains_key("update")?;
    Ok(has_init && has_view && has_update)
}

pub fn validate_js_comprehensive(
    script: &str,
    context: Option<JsValidationContext>,
) -> JsValidationResult {
    let mut result = static_analysis::run_static_stages(script, context.clone());
    if !result.is_valid {
        return result;
    }

    if let Err(msg) = check_js_syntax(script) {
        result.syntax_errors.push(msg);
        result.is_valid = false;
        return result;
    }

    let rt = match Runtime::new() {
        Ok(r) => r,
        Err(e) => {
            result
                .syntax_errors
                .push(format!("Failed to create JS environment: {}", e));
            result.is_valid = false;
            return result;
        }
    };
    let ctx = match Context::full(&rt) {
        Ok(c) => c,
        Err(e) => {
            result
                .syntax_errors
                .push(format!("Failed to create JS context: {}", e));
            result.is_valid = false;
            return result;
        }
    };

    let mut export_ok = false;
    let mut export_err: Option<String> = None;
    ctx.with(|c| {
        if let Err(e) = c.eval::<(), _>(script) {
            export_err = Some(format!("Failed to execute script: {}", e));
            return;
        }
        match check_js_required_exports(&c) {
            Ok(ok) => export_ok = ok,
            Err(e) => export_err = Some(format!("Export check failed: {}", e)),
        }
    });
    drop(ctx);
    drop(rt);

    if let Some(err) = export_err {
        result.syntax_errors.push(err);
        result.is_valid = false;
        return result;
    }
    if !export_ok {
        for name in ["init", "view", "update"] {
            result.syntax_errors.push(format!(
                "Required function '{}' not found - script will not execute properly",
                name
            ));
        }
    }

    result.is_valid = result.syntax_errors.is_empty();
    result
}

pub fn lint_js(script: &str) -> String {
    let result = validate_js_comprehensive(script, None);
    json!({
        "ok": result.is_valid,
        "errors": result.syntax_errors.iter().map(|e| json!({"message": e})).collect::<Vec<_>>(),
        "warnings": result.warnings,
        "line_count": result.line_count,
        "character_count": result.character_count
    })
    .to_string()
}

pub fn js_app_init(script: &str, json_arg: Option<&str>, budget_ms: u64) -> String {
    let deadline = deadline_from_budget(budget_ms);
    let (rt, ctx) = match create_sandboxed_js(MEM_LIMIT, deadline) {
        Ok(pair) => pair,
        Err(e) => return json!({"ok": false, "error": js_error_string(e)}).to_string(),
    };

    let outcome = ctx.with(
        |ctx| -> std::result::Result<(JsonValue, JsonValue), String> {
            install_host_globals(&ctx, json_arg).map_err(|e| match e {
                JsExecError::Js(m) | JsExecError::Json(m) => m,
            })?;
            ctx.eval::<(), _>(script).map_err(|e| e.to_string())?;
            let globals = ctx.globals();
            let func: Function = globals
                .get("init")
                .map_err(|_| "Required function 'init' not found".to_string())?;
            let arg_val: Value = globals.get("arg").map_err(|e| e.to_string())?;
            let result_val: Value = func.call((arg_val,)).map_err(|e| e.to_string())?;
            let rj = js_value_to_json_string(&ctx, result_val).map_err(|e| e.to_string())?;
            let v: JsonValue =
                serde_json::from_str(&rj).map_err(|e| format!("invalid init result: {}", e))?;
            let state = v.get("state").cloned().unwrap_or(JsonValue::Null);
            let effects = v
                .get("effects")
                .cloned()
                .unwrap_or(JsonValue::Array(vec![]));
            Ok((state, effects))
        },
    );

    drop(ctx);
    drop(rt);

    match outcome {
        Ok((state, effects)) => json!({"ok": true, "state": state, "effects": effects}).to_string(),
        Err(e) => {
            let msg = if Instant::now() > deadline {
                "execution timeout".to_string()
            } else {
                e
            };
            json!({"ok": false, "error": msg}).to_string()
        }
    }
}

pub fn js_app_view(script: &str, state_json: &str, budget_ms: u64) -> String {
    let deadline = deadline_from_budget(budget_ms);
    let (rt, ctx) = match create_sandboxed_js(MEM_LIMIT, deadline) {
        Ok(pair) => pair,
        Err(e) => return json!({"ok": false, "error": js_error_string(e)}).to_string(),
    };

    let outcome = ctx.with(|ctx| -> std::result::Result<JsonValue, String> {
        install_host_globals(&ctx, None).map_err(|e| match e {
            JsExecError::Js(m) | JsExecError::Json(m) => m,
        })?;
        let _state_val: JsonValue =
            serde_json::from_str(state_json).map_err(|e| format!("invalid state JSON: {}", e))?;
        ctx.globals()
            .set("__icp_state_raw__", state_json)
            .map_err(|e| e.to_string())?;
        ctx.eval::<(), _>("globalThis.__icp_state__ = JSON.parse(__icp_state_raw__);")
            .map_err(|e| e.to_string())?;
        ctx.globals()
            .remove("__icp_state_raw__")
            .map_err(|e| e.to_string())?;
        ctx.eval::<(), _>(script).map_err(|e| e.to_string())?;
        let globals = ctx.globals();
        let func: Function = globals
            .get("view")
            .map_err(|_| "Required function 'view' not found".to_string())?;
        let state_val: Value = globals.get("__icp_state__").map_err(|e| e.to_string())?;
        let result_val: Value = func.call((state_val,)).map_err(|e| e.to_string())?;
        let rj = js_value_to_json_string(&ctx, result_val).map_err(|e| e.to_string())?;
        let v: JsonValue =
            serde_json::from_str(&rj).map_err(|e| format!("invalid view result: {}", e))?;
        Ok(v)
    });

    drop(ctx);
    drop(rt);

    match outcome {
        Ok(ui) => json!({"ok": true, "ui": ui}).to_string(),
        Err(e) => {
            let msg = if Instant::now() > deadline {
                "execution timeout".to_string()
            } else {
                e
            };
            json!({"ok": false, "error": msg}).to_string()
        }
    }
}

pub fn js_app_update(script: &str, msg_json: &str, state_json: &str, budget_ms: u64) -> String {
    let deadline = deadline_from_budget(budget_ms);
    let (rt, ctx) = match create_sandboxed_js(MEM_LIMIT, deadline) {
        Ok(pair) => pair,
        Err(e) => return json!({"ok": false, "error": js_error_string(e)}).to_string(),
    };

    let outcome = ctx.with(|ctx| -> std::result::Result<(JsonValue, JsonValue), String> {
        install_host_globals(&ctx, None).map_err(|e| match e {
            JsExecError::Js(m) | JsExecError::Json(m) => m,
        })?;
        let _msg_val: JsonValue =
            serde_json::from_str(msg_json).map_err(|e| format!("invalid msg JSON: {}", e))?;
        let _state_val: JsonValue = serde_json::from_str(state_json)
            .map_err(|e| format!("invalid state JSON: {}", e))?;
        ctx.globals()
            .set("__icp_msg_raw__", msg_json)
            .map_err(|e| e.to_string())?;
        ctx.globals()
            .set("__icp_state_raw__", state_json)
            .map_err(|e| e.to_string())?;
        ctx.eval::<(), _>(
            "globalThis.__icp_msg__ = JSON.parse(__icp_msg_raw__); globalThis.__icp_state__ = JSON.parse(__icp_state_raw__);",
        )
        .map_err(|e| e.to_string())?;
        ctx.globals()
            .remove("__icp_msg_raw__")
            .map_err(|e| e.to_string())?;
        ctx.globals()
            .remove("__icp_state_raw__")
            .map_err(|e| e.to_string())?;
        ctx.eval::<(), _>(script).map_err(|e| e.to_string())?;
        let globals = ctx.globals();
        let func: Function = globals
            .get("update")
            .map_err(|_| "Required function 'update' not found".to_string())?;
        let msg_val: Value = globals.get("__icp_msg__").map_err(|e| e.to_string())?;
        let state_val: Value = globals.get("__icp_state__").map_err(|e| e.to_string())?;
        let result_val: Value = func
            .call((msg_val, state_val))
            .map_err(|e| e.to_string())?;
        let rj = js_value_to_json_string(&ctx, result_val).map_err(|e| e.to_string())?;
        let v: JsonValue =
            serde_json::from_str(&rj).map_err(|e| format!("invalid update result: {}", e))?;
        let state = v.get("state").cloned().unwrap_or(JsonValue::Null);
        let effects = v
            .get("effects")
            .cloned()
            .unwrap_or(JsonValue::Array(vec![]));
        Ok((state, effects))
    });

    drop(ctx);
    drop(rt);

    match outcome {
        Ok((state, effects)) => json!({"ok": true, "state": state, "effects": effects}).to_string(),
        Err(e) => {
            let msg = if Instant::now() > deadline {
                "execution timeout".to_string()
            } else {
                e
            };
            json!({"ok": false, "error": msg}).to_string()
        }
    }
}
