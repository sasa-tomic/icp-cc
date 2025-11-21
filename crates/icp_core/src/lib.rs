pub mod canister_client;

pub mod ffi;
pub mod keypair;
pub mod lua_engine;
pub mod principal;

// Include Wasm exports when target is wasm32
#[cfg(target_arch = "wasm32")]
pub mod wasm_exports;

pub use canister_client::{MethodInfo, MethodKind, ParsedInterface};
pub use keypair::{generate_ed25519_keypair, generate_secp256k1_keypair, KeypairData};
pub use lua_engine::{
    execute_lua_json, lint_lua, validate_lua_comprehensive, LuaExecError, ValidationContext,
    ValidationResult,
};
pub use principal::{der_encode_public_key, principal_from_der, principal_from_public_key};
