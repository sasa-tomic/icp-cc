use crate::{
    canister_client::{self, MethodKind},
    favorites as fav, generate_ed25519_identity, generate_secp256k1_identity, lua_engine,
};
use serde_json::json;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// # Safety
/// `mnemonic` must be either null or a valid, null-terminated C string pointer.
#[no_mangle]
pub unsafe extern "C" fn icp_generate_identity(alg: i32, mnemonic: *const c_char) -> *mut c_char {
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
        "ed25519" => generate_ed25519_identity(mnemonic_opt),
        _ => generate_secp256k1_identity(mnemonic_opt),
    };

    let json = format!(
        "{{\"public_key_b64\":\"{}\",\"private_key_b64\":\"{}\",\"principal_text\":\"{}\"}}",
        result.public_key_b64, result.private_key_b64, result.principal_text
    );
    CString::new(json).unwrap().into_raw()
}

/// # Safety
/// `ptr` must be a pointer returned by `icp_generate_identity` and not freed yet.
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

// Favorites
/// # Safety
/// - The returned pointer, when non-null, points to a heap-allocated C string owned by Rust
///   and must be freed by calling `icp_free_string` exactly once.
#[no_mangle]
pub unsafe extern "C" fn icp_favorites_list() -> *mut c_char {
    let entries = fav::list().unwrap_or_default();
    let json = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string());
    CString::new(json).unwrap().into_raw()
}

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
/// - `canister_id`, `method`, and `label` must be either null or valid, null-terminated
///   C strings.
#[no_mangle]
pub unsafe extern "C" fn icp_favorites_add(
    canister_id: *const c_char,
    method: *const c_char,
    label: *const c_char,
) -> i32 {
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
    let l = if label.is_null() {
        None
    } else {
        Some(CStr::from_ptr(label).to_str().unwrap_or("").to_string())
    };
    let entry = fav::FavoriteEntry {
        canister_id: cid.to_string(),
        method: m.to_string(),
        label: l,
    };
    match fav::add(entry) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// # Safety
/// - `canister_id` and `method` must be either null or valid, null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn icp_favorites_remove(
    canister_id: *const c_char,
    method: *const c_char,
) -> i32 {
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
    match fav::remove(cid, m) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}
