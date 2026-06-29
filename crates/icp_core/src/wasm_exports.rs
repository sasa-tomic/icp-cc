//! Wasm-compatible exports for use in Cloudflare Workers and other JavaScript environments
#![cfg(target_arch = "wasm32")]

use crate::{js_engine::static_analysis, JsValidationContext};
use serde_json::json;
use wasm_bindgen::prelude::*;

// Lua wasm exports (validate_lua_script_wasm / check_lua_syntax_wasm) were
// removed: the mlua/vendored Lua 5.4 runtime cannot target wasm32-unknown-unknown
// and the Lua engine is being sunset. The pure-Rust JS static analysis below
// is the supported wasm path.

/// Wasm-compatible JavaScript/TypeScript validation using PURE-RUST static
/// analysis only. rquickjs cannot compile to wasm32-unknown-unknown, so the
/// JS engine is not available in the wasm build; this function runs every
/// static validation stage (security, ICP integration, UI nodes, etc.) but
/// cannot perform a runtime parse or runtime export detection.
#[wasm_bindgen]
pub fn validate_js_script_wasm(
    script: &str,
    is_example: bool,
    is_test: bool,
    is_production: bool,
) -> String {
    let context = JsValidationContext {
        is_example,
        is_test,
        is_production,
    };
    let result = static_analysis::run_static_stages(script, Some(context));
    json!({
        "is_valid": result.is_valid,
        "syntax_errors": result.syntax_errors,
        "warnings": result.warnings,
        "line_count": result.line_count,
        "character_count": result.character_count
    })
    .to_string()
}

/// Wasm-compatible JavaScript/TypeScript lint via PURE-RUST static analysis.
/// Returns `{ ok, errors, warnings, line_count, character_count }`.
#[wasm_bindgen]
pub fn check_js_syntax_wasm(script: &str) -> String {
    let result = static_analysis::run_static_stages(script, None);
    json!({
        "ok": result.is_valid,
        "errors": result
            .syntax_errors
            .iter()
            .map(|e| json!({ "message": e }))
            .collect::<Vec<_>>(),
        "warnings": result.warnings,
        "line_count": result.line_count,
        "character_count": result.character_count
    })
    .to_string()
}

/// Initialize the Wasm module (called once when loading)
#[wasm_bindgen(start)]
pub fn main() {
    #[cfg(feature = "console_error_panic_hook")]
    console_error_panic_hook::set_once();
}

// Set up panic hook to get better error messages in browser console
#[cfg(feature = "console_error_panic_hook")]
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn error(s: &str);
}

#[cfg(feature = "console_error_panic_hook")]
mod console_error_panic_hook {
    use super::*;
    use std::panic::{PanicHook, PanicInfo};

    static mut LAST_HOOK: Option<Box<dyn PanicHook>> = None;

    pub fn set_once() {
        unsafe {
            if LAST_HOOK.is_none() {
                LAST_HOOK = Some(Box::new(console_error_panic_hook));
                std::panic::set_hook(Box::new(console_error_panic_hook));
            }
        }
    }

    struct ConsoleErrorPanicHook;
    impl PanicHook for ConsoleErrorPanicHook {
        fn on_panic(&self, info: &PanicInfo) {
            error!("{}", info);
        }
    }
}
