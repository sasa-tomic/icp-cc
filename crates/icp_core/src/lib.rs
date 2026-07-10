#[cfg(not(target_arch = "wasm32"))]
pub mod canister_client;
pub mod contract;

#[cfg(not(target_arch = "wasm32"))]
pub mod ffi;
pub mod js_engine;
pub mod keypair;
pub mod principal;
pub mod vault;

// Include Wasm exports when target is wasm32
#[cfg(target_arch = "wasm32")]
pub mod wasm_exports;

#[cfg(not(target_arch = "wasm32"))]
pub use canister_client::{DEFAULT_IC_GATEWAY, MethodInfo, MethodKind, ParsedInterface};
pub use contract::SDK_CONTRACT_VERSION;
#[cfg(not(target_arch = "wasm32"))]
pub use js_engine::{
    execute_js_json, js_app_init, js_app_update, js_app_view, lint_js, validate_js_comprehensive,
};
pub use js_engine::{JsExecError, JsValidationContext, JsValidationResult};
pub use keypair::{
    generate_ed25519_keypair, generate_secp256k1_keypair, sign_ed25519, sign_secp256k1, KeypairData,
};
pub use principal::{der_encode_public_key, principal_from_der, principal_from_public_key};
pub use vault::{
    decrypt_vault, derive_key, encrypt_vault, generate_nonce, generate_salt, EncryptedVault,
};
