//! Golden parity vectors: the single source of truth for `icp_*` helper output
//! on the TypeScript/QuickJS runtime. See `parity/README.md` for the schema and
//! how to extend. `parity/vectors.json` is the contract; this test enforces it.

use icp_core::{execute_js_json, SDK_CONTRACT_VERSION};
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
        let js_actual = canonicalize(run_helper_in_js(case));
        assert_eq!(
            js_actual, expected_js,
            "JS mismatch [{}]: expected {} got {}",
            case.helper, expected_js, js_actual,
        );
    }
}
