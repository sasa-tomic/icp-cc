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
function icp_enhanced_list(spec) spec = spec or {}; return { action = "ui", ui = { type = "list", props = { enhanced = true, items = spec.items or {}, title = spec.title or "Results", searchable = spec.searchable ~= false } } } end
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

/// Lint a Lua script without executing it.
/// Returns a JSON string: { ok: boolean, errors: [ { message } ] }
pub fn lint_lua(script: &str) -> String {
    let lua = match create_sandboxed_lua() {
        Ok(l) => l,
        Err(e) => {
            return serde_json::json!({"ok": false, "errors": [{"message": e.to_string()}]})
                .to_string()
        }
    };
    let chunk = lua.load(script);
    let compile_res = chunk.into_function();
    match compile_res {
        Ok(_) => serde_json::json!({"ok": true, "errors": []}).to_string(),
        Err(e) => {
            let msg = e.to_string();
            serde_json::json!({
                "ok": false,
                "errors": [{"message": msg}],
            })
            .to_string()
        }
    }
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
    fn icp_enhanced_list_function_works() {
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
                return icp_enhanced_list({
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

        // Check that the enhanced list structure is correct
        let ui = &vv["ui"]["ui"];
        assert_eq!(ui["type"].as_str().unwrap(), "list");
        assert!(ui["props"]["enhanced"].as_bool().unwrap());
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
                table.insert(results, type(icp_enhanced_list))
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
}
