#[cfg(feature = "ffi")]
pub mod ffi;
pub mod identity;
pub mod principal;

pub use identity::{generate_ed25519_identity, generate_secp256k1_identity, IdentityData};
pub use principal::{principal_from_der, principal_from_public_key};
