pub mod canister_client;

pub mod ffi;
pub mod identity;
pub mod lua_engine;
pub mod principal;

// Include Wasm exports when target is wasm32
#[cfg(target_arch = "wasm32")]
pub mod wasm_exports;

pub use canister_client::{MethodInfo, MethodKind, ParsedInterface};
pub use identity::{generate_ed25519_identity, generate_secp256k1_identity, IdentityData};
pub use lua_engine::{
    execute_lua_json, lint_lua, validate_lua_comprehensive, LuaExecError, ValidationContext,
    ValidationResult,
};
pub use principal::{der_encode_public_key, principal_from_der, principal_from_public_key};
