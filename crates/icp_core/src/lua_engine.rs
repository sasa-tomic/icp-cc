use mlua::prelude::*;
use mlua::LuaSerdeExt;
use serde_json::Value as JsonValue;

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

    let response = serde_json::json!({
        "ok": true,
        "result": json_value,
    });
    Ok(response.to_string())
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
}
