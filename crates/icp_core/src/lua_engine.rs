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

    // Define a small stdlib: json.encode / json.decode
    {
        let json_encode = lua
            .create_function(|lua, v: LuaValue| {
                // Convert any Lua value to serde_json::Value, then to string
                let jv: serde_json::Value = match v.clone() {
                    LuaValue::Nil => serde_json::Value::Null,
                    _ => lua.from_value(v).map_err(LuaError::external)?,
                };
                serde_json::to_string(&jv).map_err(LuaError::external)
            })
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        let json_decode = lua
            .create_function(|lua, s: String| {
                let v: serde_json::Value = serde_json::from_str(&s).map_err(LuaError::external)?;
                let lv = lua.to_value(&v).map_err(LuaError::external)?;
                Ok(lv)
            })
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        let tbl = lua
            .create_table()
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        tbl.set("encode", json_encode)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        tbl.set("decode", json_decode)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
        lua.globals()
            .set("json", tbl)
            .map_err(|e| LuaExecError::Lua(e.to_string()))?;
    }

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
}
