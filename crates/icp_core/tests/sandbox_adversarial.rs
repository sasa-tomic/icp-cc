//! Sandbox adversarial hardening suite.
//!
//! Each `execute_js_json` / `app_*` call spins up a fresh QuickJS `Runtime`, so
//! state mutations in one call cannot leak into another. These tests lock that
//! contract down and document the measured security posture of the bundled build:
//!
//! - Prototype pollution and `__proto__` assignment succeed *within* a single
//!   call but are invisible to subsequent calls (fresh runtime per call).
//! - Static `import "fs"` throws at runtime (no module loader). Dynamic
//!   `import('fs')` returns an inert pending-object (it never resolves to a real
//!   fs module) and is additionally blocked by static analysis.
//! - `eval` / `Function` are present on the standard global object in
//!   `Context::full`; the security gate for them is `validate_js_comprehensive`
//!   (static rejection), so the production flow validate -> execute rejects them
//!   before any code runs.
//! - `require` and `process` are absent (undefined).

use icp_core::{execute_js_json, js_engine::JsValidationContext, validate_js_comprehensive};
use serde_json::Value as JsonValue;

fn result_of(expr: &str) -> JsonValue {
    let out = execute_js_json(expr, None).expect("expression must execute");
    let v: JsonValue = serde_json::from_str(&out).expect("output is JSON");
    assert!(
        v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false),
        "expected ok=true, got: {out}"
    );
    v["result"].clone()
}

fn prod_ctx() -> JsValidationContext {
    JsValidationContext {
        is_example: false,
        is_test: false,
        is_production: true,
    }
}

#[test]
fn prototype_pollution_isolated_per_call() {
    let within = result_of("Object.prototype.x = 1");
    assert_eq!(
        within,
        JsonValue::Number(1.into()),
        "pollution must take effect within its own call"
    );

    let leaked = result_of("({}).x");
    assert!(
        leaked.is_null(),
        "prototype pollution leaked across calls: fresh ({{}}).x == {leaked}"
    );
}

#[test]
fn proto_assignment_contained_per_call() {
    let within = result_of("var o = {}; o.__proto__ = { z: 9 }; o.z");
    assert_eq!(
        within,
        JsonValue::Number(9.into()),
        "__proto__ assignment must apply within its own call"
    );

    let leaked = result_of("({}).z");
    assert!(
        leaked.is_null(),
        "__proto__ mutation leaked across calls: fresh ({{}}).z == {leaked}"
    );
}

#[test]
fn static_import_throws_at_runtime() {
    let err = execute_js_json("import \"fs\"", None).expect_err("static import must throw");
    assert!(matches!(err, icp_core::JsExecError::Js(_)));
}

#[test]
fn dynamic_import_blocked_by_validation_and_inert_at_runtime() {
    let script = "import('fs').then(function(){return 1})";
    let result = validate_js_comprehensive(script, Some(prod_ctx()));
    assert!(
        !result.is_valid,
        "dynamic import() must be rejected by validation: {:?}",
        result.syntax_errors
    );

    let runtime = result_of("typeof import('fs')");
    assert_eq!(
        runtime,
        JsonValue::String("object".into()),
        "dynamic import returns an inert pending object, never a real fs module"
    );
}

#[test]
fn eval_and_function_blocked_by_validation() {
    let eval_script = r#"
        function init(arg) { eval("1"); return { state: {}, effects: [] }; }
        function view(state) { return {}; }
        function update(msg, state) { return { state: state, effects: [] }; }
    "#;
    let result = validate_js_comprehensive(eval_script, Some(prod_ctx()));
    assert!(!result.is_valid);
    assert!(result.syntax_errors.iter().any(|e| e.contains("eval")));

    let func_script = r#"
        function init(arg) { var f = Function("return 1"); return { state: {}, effects: [] }; }
        function view(state) { return {}; }
        function update(msg, state) { return { state: state, effects: [] }; }
    "#;
    let result = validate_js_comprehensive(func_script, Some(prod_ctx()));
    assert!(!result.is_valid);
    assert!(result.syntax_errors.iter().any(|e| e.contains("Function")));
}

#[test]
fn require_and_process_are_undefined() {
    let kind = result_of("typeof require + ',' + typeof process");
    assert_eq!(kind, JsonValue::String("undefined,undefined".into()));
}
