//! Wasm-compatible exports for use in Cloudflare Workers and other JavaScript environments
#![cfg(target_arch = "wasm32")]

use crate::{validate_lua_comprehensive, ValidationContext, ValidationResult};
use serde_json::{json, Value};
use wasm_bindgen::prelude::*;

/// Wasm-compatible validation function that returns JSON string
/// This can be called from JavaScript in Cloudflare Workers
#[wasm_bindgen]
pub fn validate_lua_script_wasm(
    script: &str,
    is_example: bool,
    is_test: bool,
    is_production: bool,
) -> String {
    let context = ValidationContext {
        is_example,
        is_test,
        is_production,
    };

    let result = validate_lua_comprehensive(script, Some(context));

    // Convert to JSON string that can be parsed in JavaScript
    let json_result = json!({
        "is_valid": result.is_valid,
        "syntax_errors": result.syntax_errors,
        "warnings": result.warnings,
        "line_count": result.line_count,
        "character_count": result.character_count
    });

    json_result.to_string()
}

/// Simple Wasm-compatible syntax check function
#[wasm_bindgen]
pub fn check_lua_syntax_wasm(script: &str) -> String {
    let result = crate::lint_lua(script);

    // Parse the existing JSON result and return it
    // The lint_lua function already returns JSON string
    result
}

/// Initialize the Wasm module (called once when loading)
#[wasm_bindgen(start)]
pub fn main() {
    // This function is called when the Wasm module is loaded
    // Can be used for any initialization if needed
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
