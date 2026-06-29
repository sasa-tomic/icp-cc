//! Golden parity vectors: the single source of truth for `icp_*` helper output
//! across the QuickJS and Lua runtimes. See `parity/README.md` for the schema and
//! how to extend. `parity/vectors.json` is the contract; this test enforces it.

use icp_core::{execute_js_json, lua_engine, SDK_CONTRACT_VERSION};
use serde::Deserialize;
use serde_json::Value as JsonValue;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Vectors {
    #[allow(dead_code)]
    schema_version: u32,
    sdk_contract_version: String,
    #[allow(dead_code)]
    notes: Option<String>,
    cases: Vec<Case>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Case {
    #[allow(dead_code)]
    id: String,
    helper: String,
    args: Vec<JsonValue>,
    expected_js: JsonValue,
    expected_lua: Option<JsonValue>,
    #[allow(dead_code)]
    notes: Option<String>,
}

const VECTORS_JSON: &str = include_str!("../../../parity/vectors.json");

fn canonicalize(v: JsonValue) -> JsonValue {
    match v {
        JsonValue::Object(map) => {
            let mut entries: Vec<(String, JsonValue)> = map.into_iter().collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            let canon: serde_json::Map<String, JsonValue> = entries
                .into_iter()
                .map(|(k, val)| (k, canonicalize(val)))
                .collect();
            JsonValue::Object(canon)
        }
        JsonValue::Array(arr) => JsonValue::Array(arr.into_iter().map(canonicalize).collect()),
        other => other,
    }
}

fn run_helper_in_js(case: &Case) -> JsonValue {
    let joined = case
        .args
        .iter()
        .map(JsonValue::to_string)
        .collect::<Vec<_>>()
        .join(",");
    let script = format!("({}({}))", case.helper, joined);
    let out = execute_js_json(&script, None)
        .unwrap_or_else(|e| panic!("JS exec failed for `{script}`: {e:?}"));
    let v: JsonValue = serde_json::from_str(&out).expect("JS output is JSON");
    assert!(
        v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false),
        "JS reported !ok for `{script}`: {out}"
    );
    v["result"].clone()
}

fn run_helper_in_lua(case: &Case) -> JsonValue {
    let args_json = serde_json::to_string(&case.args).expect("args serialize");
    let escaped = args_json.replace('\\', "\\\\").replace('\'', "\\'");
    let script = format!(
        r#"
            function init(arg) return {{}}, {{}} end
            function view(state) return {helper}(table.unpack(json.decode('{args}'))) end
            function update(msg, state) return state, {{}} end
        "#,
        helper = case.helper,
        args = escaped,
    );
    let out = lua_engine::app_view(&script, "{}", 2000);
    let v: JsonValue = serde_json::from_str(&out).expect("Lua output is JSON");
    assert!(
        v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false),
        "Lua reported !ok for case `{}`: {out}",
        case.helper
    );
    v["ui"].clone()
}

#[test]
fn sdk_contract_version_matches_vectors() {
    let vectors: Vectors = serde_json::from_str(VECTORS_JSON).expect("vectors.json parses");
    assert_eq!(
        SDK_CONTRACT_VERSION, vectors.sdk_contract_version,
        "SDK_CONTRACT_VERSION must match parity/vectors.json sdkContractVersion"
    );
}

#[test]
fn all_helpers_match_golden_vectors() {
    let vectors: Vectors = serde_json::from_str(VECTORS_JSON).expect("vectors.json parses");
    assert!(
        !vectors.cases.is_empty(),
        "vectors.json must contain at least one case"
    );

    for case in &vectors.cases {
        let expected_js = canonicalize(case.expected_js.clone());
        let expected_lua = canonicalize(
            case.expected_lua
                .clone()
                .unwrap_or_else(|| case.expected_js.clone()),
        );

        let js_actual = canonicalize(run_helper_in_js(case));
        assert_eq!(
            js_actual, expected_js,
            "JS mismatch [{}]: expected {} got {}",
            case.helper, expected_js, js_actual,
        );

        let lua_actual = canonicalize(run_helper_in_lua(case));
        assert_eq!(
            lua_actual, expected_lua,
            "Lua mismatch [{}]: expected {} got {}",
            case.helper, expected_lua, lua_actual,
        );
    }
}
