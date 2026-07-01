use crate::{
    canister_client::{self, MethodKind},
    generate_ed25519_keypair, generate_secp256k1_keypair, js_engine, principal_from_public_key,
    sign_ed25519, sign_secp256k1,
    vault::{self, EncryptedVault},
    JsValidationContext,
};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use serde_json::json;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

unsafe fn cstr_or_empty<'a>(p: *const c_char) -> &'a str {
    if p.is_null() {
        ""
    } else {
        CStr::from_ptr(p).to_str().unwrap_or("")
    }
}

unsafe fn cstr_opt<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        None
    } else {
        CStr::from_ptr(p).to_str().ok()
    }
}

unsafe fn cstr_opt_or_empty<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        None
    } else {
        Some(cstr_or_empty(p))
    }
}

fn err_ptr<E: std::fmt::Display>(e: E) -> *mut c_char {
    CString::new(json!({"ok": false, "error": e.to_string()}).to_string())
        .unwrap()
        .into_raw()
}

fn method_kind(kind: i32) -> MethodKind {
    match kind {
        2 => MethodKind::CompositeQuery,
        1 => MethodKind::Update,
        _ => MethodKind::Query,
    }
}

fn null_c_string() -> *mut c_char {
    CString::new("").unwrap().into_raw()
}

/// # Safety
/// `mnemonic` must be either null or a valid, null-terminated C string pointer.
#[no_mangle]
pub unsafe extern "C" fn icp_generate_keypair(alg: i32, mnemonic: *const c_char) -> *mut c_char {
    let alg_str = match alg {
        0 => "ed25519",
        1 => "secp256k1",
        _ => return null_c_string(),
    };
    let mnemonic_opt = cstr_opt(mnemonic).map(str::to_string);

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
    let pk_str = match cstr_opt(pk_b64) {
        Some(s) => s,
        None => return null_c_string(),
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
/// - Returns JSON: {"ok": true, "signature": "<base64>"} or {"ok": false, "error": "..."}
/// - The returned pointer must be freed by `icp_free_string`.
#[no_mangle]
pub unsafe extern "C" fn icp_sign_message(
    alg: i32,
    message_b64: *const c_char,
    private_key_b64: *const c_char,
) -> *mut c_char {
    if message_b64.is_null() || private_key_b64.is_null() {
        return err_ptr("Null parameters");
    }
    let msg_b64 = match cstr_opt(message_b64) {
        Some(s) => s,
        None => return err_ptr("Invalid message encoding"),
    };
    let pk_b64 = match cstr_opt(private_key_b64) {
        Some(s) => s,
        None => return err_ptr("Invalid private key encoding"),
    };

    // Decode the message from base64
    let message = match B64.decode(msg_b64) {
        Ok(b) => b,
        Err(e) => return err_ptr(format!("Failed to decode message: {}", e)),
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
    let cid = cstr_or_empty(canister_id);
    let host_opt = cstr_opt_or_empty(host);
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
    let s = cstr_or_empty(candid_text);
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
    let cid = cstr_or_empty(canister_id);
    let m = cstr_or_empty(method);
    let a = cstr_or_empty(arg_candid);
    let host_opt = cstr_opt_or_empty(host);
    match canister_client::call_anonymous(cid, m, method_kind(kind), a, host_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(e) => err_ptr(e),
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
    let cid = cstr_or_empty(canister_id);
    let m = cstr_or_empty(method);
    let a = cstr_or_empty(arg_candid);
    let k = cstr_or_empty(ed25519_private_key_b64);
    let host_opt = cstr_opt_or_empty(host);
    match canister_client::call_authenticated(cid, m, method_kind(kind), a, k, host_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(e) => err_ptr(e),
    }
}

// ---- JavaScript scripting FFI (QuickJS-backed; native only) ----
// rquickjs builds QuickJS from vendored C source, which cannot be compiled to
// wasm32-unknown-unknown. The wasm path uses pure-Rust static analysis
// (see wasm_exports.rs).

/// # Safety
/// - `script` and `json_arg` must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[cfg(not(target_arch = "wasm32"))]
#[no_mangle]
pub unsafe extern "C" fn icp_js_exec(
    script: *const c_char,
    json_arg: *const c_char,
) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let script_s = cstr_or_empty(script);
    let arg_opt = cstr_opt_or_empty(json_arg);
    match js_engine::execute_js_json(script_s, arg_opt) {
        Ok(s) => CString::new(s).unwrap().into_raw(),
        Err(e) => err_ptr(e),
    }
}

/// # Safety
/// - `script` must be null or a valid, null-terminated C string.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[cfg(not(target_arch = "wasm32"))]
#[no_mangle]
pub unsafe extern "C" fn icp_js_lint(script: *const c_char) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let script_s = cstr_or_empty(script);
    let json = js_engine::lint_js(script_s);
    CString::new(json).unwrap().into_raw()
}

/// # Safety
/// - `script` must be null or a valid, null-terminated C string.
/// - `is_example`, `is_test`, and `is_production` must be 0 (false) or 1 (true).
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[cfg(not(target_arch = "wasm32"))]
#[no_mangle]
pub unsafe extern "C" fn icp_js_validate_comprehensive(
    script: *const c_char,
    is_example: i32,
    is_test: i32,
    is_production: i32,
) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let script_s = cstr_or_empty(script);

    let context = JsValidationContext {
        is_example: is_example != 0,
        is_test: is_test != 0,
        is_production: is_production != 0,
    };

    let result = js_engine::validate_js_comprehensive(script_s, Some(context));
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

/// # Safety
/// - All pointers must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[cfg(not(target_arch = "wasm32"))]
#[no_mangle]
pub unsafe extern "C" fn icp_js_app_init(
    script: *const c_char,
    json_arg: *const c_char,
    budget_ms: u64,
) -> *mut c_char {
    if script.is_null() {
        return null_c_string();
    }
    let s = cstr_or_empty(script);
    let arg_opt = cstr_opt_or_empty(json_arg);
    let out = js_engine::js_app_init(s, arg_opt, budget_ms);
    CString::new(out).unwrap().into_raw()
}

/// # Safety
/// - All pointers must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[cfg(not(target_arch = "wasm32"))]
#[no_mangle]
pub unsafe extern "C" fn icp_js_app_view(
    script: *const c_char,
    state_json: *const c_char,
    budget_ms: u64,
) -> *mut c_char {
    if script.is_null() || state_json.is_null() {
        return null_c_string();
    }
    let s = cstr_or_empty(script);
    let st = cstr_or_empty(state_json);
    let out = js_engine::js_app_view(s, st, budget_ms);
    CString::new(out).unwrap().into_raw()
}

/// # Safety
/// - All pointers must be null or valid, null-terminated C strings.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
#[cfg(not(target_arch = "wasm32"))]
#[no_mangle]
pub unsafe extern "C" fn icp_js_app_update(
    script: *const c_char,
    msg_json: *const c_char,
    state_json: *const c_char,
    budget_ms: u64,
) -> *mut c_char {
    if script.is_null() || msg_json.is_null() || state_json.is_null() {
        return null_c_string();
    }
    let s = cstr_or_empty(script);
    let m = cstr_or_empty(msg_json);
    let st = cstr_or_empty(state_json);
    let out = js_engine::js_app_update(s, m, st, budget_ms);
    CString::new(out).unwrap().into_raw()
}

// ---- Vault encryption FFI ----

/// Encrypts data with AES-256-GCM using a password-derived key (Argon2id).
///
/// # Safety
/// - `password` and `plaintext_b64` must be null or valid, null-terminated C strings.
/// - `plaintext_b64` must contain base64-encoded plaintext data.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
/// - JSON format on success: {"ok":true,"encrypted_data":"...","salt":"...","nonce":"..."}
/// - JSON format on error: {"ok":false,"error":"..."}
#[no_mangle]
pub unsafe extern "C" fn icp_encrypt_vault(
    password: *const c_char,
    plaintext_b64: *const c_char,
) -> *mut c_char {
    if password.is_null() || plaintext_b64.is_null() {
        return err_ptr("Null parameters");
    }

    let password_str = match cstr_opt(password) {
        Some(s) => s,
        None => return err_ptr("Invalid password encoding"),
    };

    let plaintext_b64_str = match cstr_opt(plaintext_b64) {
        Some(s) => s,
        None => return err_ptr("Invalid plaintext encoding"),
    };

    let plaintext = match B64.decode(plaintext_b64_str) {
        Ok(b) => b,
        Err(e) => return err_ptr(format!("Failed to decode plaintext: {}", e)),
    };

    match vault::encrypt_vault(password_str, &plaintext) {
        Ok(encrypted) => {
            let json = json!({
                "ok": true,
                "encrypted_data": B64.encode(&encrypted.encrypted_data),
                "salt": B64.encode(&encrypted.salt),
                "nonce": B64.encode(&encrypted.nonce)
            })
            .to_string();
            CString::new(json).unwrap().into_raw()
        }
        Err(e) => err_ptr(e),
    }
}

/// Decrypts AES-256-GCM encrypted data using a password-derived key (Argon2id).
///
/// # Safety
/// - `password`, `encrypted_data_b64`, `salt_b64`, and `nonce_b64` must be null or valid,
///   null-terminated C strings containing base64-encoded data.
/// - Returns heap-allocated C string (JSON). Must be freed by `icp_free_string`.
/// - JSON format on success: {"ok":true,"plaintext":"<base64>"}
/// - JSON format on error: {"ok":false,"error":"..."}
#[no_mangle]
pub unsafe extern "C" fn icp_decrypt_vault(
    password: *const c_char,
    encrypted_data_b64: *const c_char,
    salt_b64: *const c_char,
    nonce_b64: *const c_char,
) -> *mut c_char {
    if password.is_null()
        || encrypted_data_b64.is_null()
        || salt_b64.is_null()
        || nonce_b64.is_null()
    {
        return err_ptr("Null parameters");
    }

    let password_str = match cstr_opt(password) {
        Some(s) => s,
        None => return err_ptr("Invalid password encoding"),
    };

    let encrypted_data = match B64.decode(cstr_or_empty(encrypted_data_b64)) {
        Ok(b) => b,
        Err(e) => return err_ptr(format!("Failed to decode encrypted_data: {}", e)),
    };

    let salt = match B64.decode(cstr_or_empty(salt_b64)) {
        Ok(b) => b,
        Err(e) => return err_ptr(format!("Failed to decode salt: {}", e)),
    };

    let nonce = match B64.decode(cstr_or_empty(nonce_b64)) {
        Ok(b) => b,
        Err(e) => return err_ptr(format!("Failed to decode nonce: {}", e)),
    };

    let vault = match EncryptedVault::new(encrypted_data, salt, nonce) {
        Ok(v) => v,
        Err(e) => return err_ptr(e),
    };

    match vault::decrypt_vault(password_str, &vault) {
        Ok(plaintext) => {
            let json = json!({
                "ok": true,
                "plaintext": B64.encode(&plaintext)
            })
            .to_string();
            CString::new(json).unwrap().into_raw()
        }
        Err(e) => err_ptr(e),
    }
}
