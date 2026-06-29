use icp_core::{js_app_init, js_app_update, js_app_view};
use serde_json::Value as JsonValue;

const BUNDLE: &str = include_str!("fixtures/pilot_sample.bundle.js");
const BUDGET_MS: u64 = 1000;

fn default_state_json() -> String {
    let out = js_app_init(BUNDLE, None, BUDGET_MS);
    let v: JsonValue = serde_json::from_str(&out).expect("init output is JSON");
    assert!(
        v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false),
        "pilot bundle init must succeed to seed state: {out}"
    );
    v["state"].to_string()
}

#[test]
fn pilot_bundle_init_returns_default_state() {
    let out = js_app_init(BUNDLE, None, BUDGET_MS);
    let v: JsonValue = serde_json::from_str(&out).expect("init output is JSON");
    assert!(v["ok"].as_bool().unwrap(), "init must succeed: {out}");

    let state = &v["state"];
    assert_eq!(state["count"].as_i64().unwrap(), 0);
    assert!(
        state["items"].is_array(),
        "items must be an array, got: {state}"
    );
    assert!(
        state["items"].as_array().unwrap().is_empty(),
        "items must be empty"
    );
    assert_eq!(state["name"].as_str().unwrap(), "");
    assert_eq!(state["email"].as_str().unwrap(), "");
    assert!(state["enabled"].as_bool().unwrap());
    assert_eq!(state["role"].as_str().unwrap(), "user");
    assert!(!state["showImage"].as_bool().unwrap());

    assert!(v["effects"].is_array(), "effects must be an array");
    assert!(
        v["effects"].as_array().unwrap().is_empty(),
        "effects must be empty"
    );
}

#[test]
fn pilot_bundle_view_renders_column_with_section() {
    let state = default_state_json();
    let out = js_app_view(BUNDLE, &state, BUDGET_MS);
    let v: JsonValue = serde_json::from_str(&out).expect("view output is JSON");
    assert!(v["ok"].as_bool().unwrap(), "view must succeed: {out}");

    let ui = &v["ui"];
    assert_eq!(ui["type"].as_str().unwrap(), "column");
    let children = ui["children"]
        .as_array()
        .expect("ui.children must be an array");
    assert!(
        children
            .iter()
            .any(|c| c["type"].as_str() == Some("section")),
        "ui.children must contain a section node, got: {ui}"
    );
}

#[test]
fn pilot_bundle_update_inc_increments_count() {
    let state = default_state_json();
    let out = js_app_update(BUNDLE, r#"{"type":"inc"}"#, &state, BUDGET_MS);
    let v: JsonValue = serde_json::from_str(&out).expect("update output is JSON");
    assert!(v["ok"].as_bool().unwrap(), "update inc must succeed: {out}");
    assert_eq!(v["state"]["count"].as_i64().unwrap(), 1);
}

#[test]
fn pilot_bundle_update_load_sample_emits_icp_batch() {
    let state = default_state_json();
    let out = js_app_update(BUNDLE, r#"{"type":"load_sample"}"#, &state, BUDGET_MS);
    let v: JsonValue = serde_json::from_str(&out).expect("update output is JSON");
    assert!(
        v["ok"].as_bool().unwrap(),
        "update load_sample must succeed: {out}"
    );

    let arr = v["effects"].as_array().expect("effects must be an array");
    assert!(!arr.is_empty(), "effects must not be empty");
    assert_eq!(arr[0]["kind"].as_str().unwrap(), "icp_batch");
    let items = arr[0]["items"]
        .as_array()
        .expect("effect items must be an array");
    assert_eq!(items.len(), 2);
}
