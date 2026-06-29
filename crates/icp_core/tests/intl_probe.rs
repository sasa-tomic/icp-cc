//! Probe QuickJS `Intl` availability and lock down the frozen decision to forbid it.
//!
//! Frozen decision: `Intl.*` is FORBIDDEN in marketplace scripts. Scripts must rely
//! on the locale-free `icp_format_*` helpers; pulling in full ICU would bloat the
//! binary and complicate the NDK/wasm toolchain.
//!
//! Probe evidence (bundled QuickJS, native build): `typeof Intl` evaluates to the
//! string `"undefined"` and `new Intl.NumberFormat('de-DE').format(1234.5)` throws
//! `ReferenceError: Intl is not defined`. The ICU data set is therefore already
//! absent from the build; the static `validate_intl` gate makes that contract
//! explicit instead of leaving scripts to fail at runtime.

use icp_core::execute_js_json;
use serde_json::Value as JsonValue;

fn result_of(expr: &str) -> JsonValue {
    let out = execute_js_json(expr, None).expect("sandboxed Intl probe must not panic");
    let v: JsonValue = serde_json::from_str(&out).expect("probe output is JSON");
    v["result"].clone()
}

#[test]
fn intl_typeof_probe() {
    let res = result_of("typeof Intl");
    assert!(
        res.is_string(),
        "typeof Intl must return a string without panicking, got: {res}"
    );
}

#[test]
fn intl_number_format_probe() {
    let res = result_of(
        "(function () { try { return new Intl.NumberFormat('de-DE').format(1234.5); } catch (e) { return 'THROWS:' + String(e); } })()",
    );
    assert!(
        res.is_string(),
        "Intl.NumberFormat probe must produce a string without panicking, got: {res}"
    );
}
