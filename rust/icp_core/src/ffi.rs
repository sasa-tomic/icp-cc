use crate::{generate_ed25519_identity, generate_secp256k1_identity};
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
