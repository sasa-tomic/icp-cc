use crate::{
    canister_client::{self, MethodKind},
    generate_ed25519_keypair, generate_secp256k1_keypair, lua_engine, principal_from_public_key,
    sign_ed25519, sign_secp256k1, ValidationContext,
};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use serde_json::json;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// # Safety
/// `mnemonic` must be either null or a valid, null-terminated C string pointer.
#[no_mangle]
pub unsafe extern "C" fn icp_generate_keypair(alg: i32, mnemonic: *const c_char) -> *mut c_char {
    let alg_str = match alg {
        0 => "ed25519",
        1 => "secp256k1",
        _ => return null_c_string(),
    };
    let mnemonic_opt = if mnemonic.is_null() {
        None
    } else {
        CStr::from_ptr(mnemonic)
            .to_str()
            .ok()
            .map(|s| s.to_string())
    };

    let result = match alg_str {
        "ed25519" => generate_ed25519_keypair(mnemonic_opt),
        _ => generate_secp256k1_keypair(mnemonic_opt),
    };

    let json = format!(
        "{{\"public_key_b64\":\"{}\",\"private_key_b64\":\"{}\",\"principal_text\":\"{}\"}}",
        result.public_key_b64, result.private_key_b64, result.principal_text
    );
    CString::new(json).unwrap().into_raw()
}

/// Derive principal from algorithm and base64-encoded public key.
///
/// # Safety
/// - `pk_b64` must be a valid, null-terminated C string containing base64-encoded public key.
/// - `alg`: 0 = ed25519 (32-byte key), 1 = secp256k1 (65-byte uncompressed key)
/// - The returned pointer must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_principal_from_public_key(
    alg: i32,
    pk_b64: *const c_char,
) -> *mut c_char {
    if pk_b64.is_null() {
        return null_c_string();
    }
    let pk_str = match CStr::from_ptr(pk_b64).to_str() {
        Ok(s) => s,
        Err(_) => return null_c_string(),
    };
    let pk_bytes = match B64.decode(pk_str) {
        Ok(b) => b,
        Err(_) => return null_c_string(),
    };
    let alg_str = match alg {
        0 => "ed25519",
        1 => "secp256k1",
        _ => return null_c_string(),
    };
    let principal = match principal_from_public_key(alg_str, &pk_bytes) {
        Some(p) => p,
        None => return null_c_string(),
    };
    CString::new(principal).unwrap().into_raw()
}

/// Sign a message with a private key.
///
/// # Safety
/// - `message_b64` must be a valid, null-terminated C string containing base64-encoded message.
/// - `private_key_b64` must be a valid, null-terminated C string containing base64-encoded private key.
/// - `alg`: 0 = Ed25519, 1 = secp256k1
/// - Returns JSON: {"ok": true, "signature": "<hex>"} or {"ok": false, "error": "..."}
/// - The returned pointer must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_sign_message(
    alg: i32,
    message_b64: *const c_char,
    private_key_b64: *const c_char,
) -> *mut c_char {
    if message_b64.is_null() || private_key_b64.is_null() {
        let err_json = json!({"ok": false, "error": "Null parameters"}).to_string();
        return CString::new(err_json).unwrap().into_raw();
    }

    let msg_b64 = match CStr::from_ptr(message_b64).to_str() {
        Ok(s) => s,
        Err(_) => {
            let err_json = json!({"ok": false, "error": "Invalid message encoding"}).to_string();
            return CString::new(err_json).unwrap().into_raw();
        }
    };

    let pk_b64 = match CStr::from_ptr(private_key_b64).to_str() {
        Ok(s) => s,
        Err(_) => {
            let err_json =
                json!({"ok": false, "error": "Invalid private key encoding"}).to_string();
            return CString::new(err_json).unwrap().into_raw();
        }
    };

    // Decode the message from base64
    let message = match B64.decode(msg_b64) {
        Ok(b) => b,
        Err(e) => {
            let err_json =
                json!({"ok": false, "error": format!("Failed to decode message: {}", e)})
                    .to_string();
            return CString::new(err_json).unwrap().into_raw();
        }
    };

    let result = match alg {
        0 => sign_ed25519(&message, pk_b64),
        1 => sign_secp256k1(&message, pk_b64),
        _ => Err("Invalid algorithm: use 0 for Ed25519 or 1 for secp256k1".to_string()),
    };

    let json = match result {
        Ok(signature) => json!({"ok": true, "signature": signature}).to_string(),
        Err(e) => json!({"ok": false, "error": e}).to_string(),
    };

    CString::new(json).unwrap().into_raw()
}

/// # Safety
/// `ptr` must be a pointer returned by `icp_generate_keypair` and not freed yet.
#[no_mangle]
pub unsafe extern "C" fn icp_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

fn null_c_string() -> *mut c_char {
    CString::new("").unwrap().into_raw()
}

// ---- Canister client FFI (JSON strings in/out) ----

/// # Safety
/// - `canister_id` and `host` must be either null or valid, null-terminated C strings.
/// - The returned pointer, when non-null, points to a heap-allocated C string owned by Rust
///   and must be freed by calling `icp_free_string` exactly once.
/// - This function performs FFI boundary conversions and must not be called concurrently with
///   a free of the returned pointer.
#[no_mangle]
pub unsafe extern "C" fn icp_fetch_candid(
    canister_id: *const c_char,
    host: *const c_char,
) -> *mut c_char {
    let cid = if canister_id.is_null() {
        ""
    } else {
        CStr::from_ptr(canister_id).to_str().unwrap_or("")
    };
    let host_opt = if host.is_null() {
        None
    } else {
        Some(CStr::from_ptr(host).to_str().unwrap_or(""))
    };
    match canister_client::fetch_candid(cid, host_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(_) => null_c_string(),
    }
}

/// # Safety
/// - `candid_text` must be either null or a valid, null-terminated C string.
/// - The returned pointer, when non-null, points to a heap-allocated C string owned by Rust
///   and must be freed by calling `icp_free_string` exactly once.
#[no_mangle]
pub unsafe extern "C" fn icp_parse_candid(candid_text: *const c_char) -> *mut c_char {
    if candid_text.is_null() {
        return null_c_string();
    }
    let s = CStr::from_ptr(candid_text).to_str().unwrap_or("");
    match canister_client::parse_candid_interface(s) {
        Ok(parsed) => {
            let json = serde_json::to_string(&parsed).unwrap_or_else(|_| "{}".to_string());
            CString::new(json).unwrap().into_raw()
        }
        Err(_) => null_c_string(),
    }
}

/// # Safety
/// - `canister_id`, `method`, `arg_candid`, and `host` must be either null or valid,
///   null-terminated C strings.
/// - `kind` must be one of 0 (query), 1 (update), or 2 (composite query).
/// - The returned pointer, when non-null, points to a heap-allocated C string owned by Rust
///   and must be freed by calling `icp_free_string` exactly once.
#[no_mangle]
pub unsafe extern "C" fn icp_call_anonymous(
    canister_id: *const c_char,
    method: *const c_char,
    kind: i32, // 0=query,1=update,2=comp
    arg_candid: *const c_char,
    host: *const c_char,
) -> *mut c_char {
    let cid = if canister_id.is_null() {
        ""
    } else {
        CStr::from_ptr(canister_id).to_str().unwrap_or("")
    };
    let m = if method.is_null() {
        ""
    } else {
        CStr::from_ptr(method).to_str().unwrap_or("")
    };
    let a = if arg_candid.is_null() {
        ""
    } else {
        CStr::from_ptr(arg_candid).to_str().unwrap_or("")
    };
    let host_opt = if host.is_null() {
        None
    } else {
        Some(CStr::from_ptr(host).to_str().unwrap_or(""))
    };
    let mk = match kind {
        2 => MethodKind::CompositeQuery,
        1 => MethodKind::Update,
        _ => MethodKind::Query,
    };
    match canister_client::call_anonymous(cid, m, mk, a, host_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(e) => {
            let err_json = json!({"ok": false, "error": e.to_string()}).to_string();
            CString::new(err_json).unwrap().into_raw()
        }
    }
}

/// # Safety
/// - `canister_id`, `method`, `arg_candid`, `ed25519_private_key_b64`, and `host` must be
///   either null or valid, null-terminated C strings.
/// - `ed25519_private_key_b64` must contain a base64-encoded 32-byte Ed25519 private key when
///   non-null/non-empty.
/// - `kind` must be one of 0 (query), 1 (update), or 2 (composite query).
/// - The returned pointer, when non-null, points to a heap-allocated C string owned by Rust
///   and must be freed by calling `icp_free_string` exactly once.
#[no_mangle]
pub unsafe extern "C" fn icp_call_authenticated(
    canister_id: *const c_char,
    method: *const c_char,
    kind: i32,
    arg_candid: *const c_char,
    ed25519_private_key_b64: *const c_char,
    host: *const c_char,
) -> *mut c_char {
    let cid = if canister_id.is_null() {
        ""
    } else {
        CStr::from_ptr(canister_id).to_str().unwrap_or("")
    };
    let m = if method.is_null() {
        ""
    } else {
        CStr::from_ptr(method).to_str().unwrap_or("")
    };
    let a = if arg_candid.is_null() {
        ""
    } else {
        CStr::from_ptr(arg_candid).to_str().unwrap_or("")
    };
    let k = if ed25519_private_key_b64.is_null() {
        ""
    } else {
        CStr::from_ptr(ed25519_private_key_b64)
            .to_str()
            .unwrap_or("")
    };
    let host_opt = if host.is_null() {
        None
    } else {
        Some(CStr::from_ptr(host).to_str().unwrap_or(""))
    };
    let mk = match kind {
        2 => MethodKind::CompositeQuery,
        1 => MethodKind::Update,
        _ => MethodKind::Query,
    };
    match canister_client::call_authenticated(cid, m, mk, a, k, host_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(e) => {
            let err_json = json!({"ok": false, "error": e.to_string()}).to_string();
            CString::new(err_json).unwrap().into_raw()
        }
    }
}

// Bookmarks
/// # Safety
/// - The returned pointer, when non-null, points to a heap-allocated C string owned by Rust
///   and must be freed by calling `icp_free_string` exactly once.
// ---- Lua scripting FFI ----
/// # Safety
/// - `script` and `json_arg` must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_lua_exec(
    script: *const c_char,
    json_arg: *const c_char,
) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let script_s = CStr::from_ptr(script).to_str().unwrap_or("");
    let arg_opt = if json_arg.is_null() {
        None
    } else {
        Some(CStr::from_ptr(json_arg).to_str().unwrap_or(""))
    };
    match lua_engine::execute_lua_json(script_s, arg_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(e) => {
            let err_json = json!({"ok": false, "error": e.to_string()}).to_string();
            CString::new(err_json).unwrap().into_raw()
        }
    }
}

/// # Safety
/// - `script` must be null or a valid, null-terminated C string.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_lua_lint(script: *const c_char) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let script_s = CStr::from_ptr(script).to_str().unwrap_or("");
    let json = lua_engine::lint_lua(script_s);
    CString::new(json).unwrap().into_raw()
}

/// # Safety
/// - `script` must be null or a valid, null-terminated C string.
/// - `is_example`, `is_test`, and `is_production` must be 0 (false) or 1 (true).
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_lua_validate_comprehensive(
    script: *const c_char,
    is_example: i32,
    is_test: i32,
    is_production: i32,
) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let script_s = CStr::from_ptr(script).to_str().unwrap_or("");

    let context = ValidationContext {
        is_example: is_example != 0,
        is_test: is_test != 0,
        is_production: is_production != 0,
    };

    let result = lua_engine::validate_lua_comprehensive(script_s, Some(context));
    let json = json!({
        "is_valid": result.is_valid,
        "syntax_errors": result.syntax_errors,
        "warnings": result.warnings,
        "line_count": result.line_count,
        "character_count": result.character_count
    })
    .to_string();

    CString::new(json).unwrap().into_raw()
}

// ---- TEA-style Lua app FFI ----
/// # Safety
/// - All pointers must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_lua_app_init(
    script: *const c_char,
    json_arg: *const c_char,
    budget_ms: u64,
) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let s = CStr::from_ptr(script).to_str().unwrap_or("");
    let arg_opt = if json_arg.is_null() {
        None
    } else {
        Some(CStr::from_ptr(json_arg).to_str().unwrap_or(""))
    };
    let out = lua_engine::app_init(s, arg_opt, budget_ms);
    CString::new(out).unwrap().into_raw()
}

/// # Safety
/// - All pointers must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_lua_app_view(
    script: *const c_char,
    state_json: *const c_char,
    budget_ms: u64,
) -> *mut c_char {
    if script.is_null() || state_json.is_null() {
        return null_c_string();
    }
    let s = CStr::from_ptr(script).to_str().unwrap_or("");
    let st = CStr::from_ptr(state_json).to_str().unwrap_or("");
    let out = lua_engine::app_view(s, st, budget_ms);
    CString::new(out).unwrap().into_raw()
}

/// # Safety
/// - All pointers must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_lua_app_update(
    script: *const c_char,
    msg_json: *const c_char,
    state_json: *const c_char,
    budget_ms: u64,
) -> *mut c_char {
    if script.is_null() || msg_json.is_null() || state_json.is_null() {
        return null_c_string();
    }
    let s = CStr::from_ptr(script).to_str().unwrap_or("");
    let m = CStr::from_ptr(msg_json).to_str().unwrap_or("");
    let st = CStr::from_ptr(state_json).to_str().unwrap_or("");
    let out = lua_engine::app_update(s, m, st, budget_ms);
    CString::new(out).unwrap().into_raw()
}
