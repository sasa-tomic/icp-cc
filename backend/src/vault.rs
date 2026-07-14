//! Recovery-code hashing utilities (Argon2id KDF).
//!
//! ## A-4 (zero-knowledge vault) — RESOLVED ON THE BACKEND
//!
//! The backend performs **no** vault cryptography. The Dart client derives the
//! Argon2id key and performs AES-256-GCM encryption locally, then POSTs the
//! resulting opaque blob (ciphertext + salt + nonce) to `/api/v1/vault`. The
//! server stores and returns those bytes verbatim — it never sees the password
//! or the plaintext. See `main.rs::vault_create` / `vault_get` / `vault_update`
//! for the wire contract, and `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md` for
//! the full migration record.
//!
//! The single source of truth for vault crypto params is now
//! `crates/icp_core/src/vault.rs` (the Rust core crate consumed via FFI by the
//! Dart client). This file is **only** the recovery-code Argon2id hashing path.
//!
//! ## What lives here
//!
//! Argon2id-based hashing for one-time recovery codes. Recovery codes are
//! generated, hashed (salted Argon2id), stored, and verified at login time.
//! Parameters (Bitwarden-level):
//! - Argon2id: time=3, memory=64MB, parallelism=4, output=32 bytes

use argon2::{Argon2, Params, Version};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use rand::RngCore;

/// Argon2id parameters (Bitwarden-level security)
const ARGON2_TIME_COST: u32 = 3;
const ARGON2_MEMORY_COST: u32 = 65536; // 64 MB
const ARGON2_PARALLELISM: u32 = 4;
const ARGON2_OUTPUT_LEN: usize = 32;
const SALT_LEN: usize = 16;

/// Derives a 256-bit key from a recovery code + salt using Argon2id.
///
/// This is scoped to the recovery-code path only (renamed from the old generic
/// `derive_key` during A-4 W4 to make its purpose explicit once the vault
/// crypto moved client-side).
fn derive_recovery_key(code: &str, salt: &[u8]) -> Result<[u8; 32], String> {
    let params = Params::new(
        ARGON2_MEMORY_COST,
        ARGON2_TIME_COST,
        ARGON2_PARALLELISM,
        Some(ARGON2_OUTPUT_LEN),
    )
    .map_err(|e| format!("Invalid Argon2 params: {}", e))?;

    let argon2 = Argon2::new(argon2::Algorithm::Argon2id, Version::V0x13, params);

    let mut key = [0u8; 32];
    argon2
        .hash_password_into(code.as_bytes(), salt, &mut key)
        .map_err(|e| format!("Key derivation failed: {}", e))?;

    Ok(key)
}

/// Generates a cryptographically-secure random salt for recovery-code hashing.
fn generate_salt() -> [u8; SALT_LEN] {
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    salt
}

// ============================================================================
// Recovery Codes
// ============================================================================

const RECOVERY_CODE_LEN: usize = 8;
const RECOVERY_CODE_ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No I/O/0/1

/// Generates a single random recovery code (8 uppercase alphanumeric chars)
fn generate_single_code() -> String {
    let mut code = String::with_capacity(RECOVERY_CODE_LEN);
    let mut rng = rand::thread_rng();
    for _ in 0..RECOVERY_CODE_LEN {
        let idx = (rng.next_u32() as usize) % RECOVERY_CODE_ALPHABET.len();
        code.push(RECOVERY_CODE_ALPHABET[idx] as char);
    }
    code
}

/// Generates 12 unique recovery codes
pub fn generate_recovery_codes() -> Vec<String> {
    (0..12).map(|_| generate_single_code()).collect()
}

/// Hashes a recovery code with Argon2id for secure storage
pub fn hash_recovery_code(code: &str) -> Result<String, String> {
    let normalized = code.to_uppercase().replace(['-', ' '], "");
    let salt = generate_salt();
    let key = derive_recovery_key(&normalized, &salt)?;
    Ok(format!("{}${}", B64.encode(salt), B64.encode(key)))
}

/// Verifies a recovery code against a stored hash
pub fn verify_recovery_code(code: &str, hash: &str) -> Result<bool, String> {
    let normalized = code.to_uppercase().replace(['-', ' '], "");
    let parts: Vec<&str> = hash.split('$').collect();
    if parts.len() != 2 {
        return Err("Invalid hash format".to_string());
    }

    let salt = B64
        .decode(parts[0])
        .map_err(|e| format!("Invalid salt: {}", e))?;
    let stored_key = B64
        .decode(parts[1])
        .map_err(|e| format!("Invalid key: {}", e))?;
    let derived_key = derive_recovery_key(&normalized, &salt)?;

    // W7-3 (security): constant-time compare so a timing attacker cannot learn
    // how many leading bytes of a guessed recovery code are correct.
    Ok(crate::crypto_util::constant_time_eq(
        &derived_key[..],
        &stored_key[..],
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Recovery code tests
    #[test]
    fn test_generate_recovery_codes_count() {
        let codes = generate_recovery_codes();
        assert_eq!(codes.len(), 12, "should generate 12 codes");
    }

    #[test]
    fn test_generate_recovery_codes_format() {
        let codes = generate_recovery_codes();
        for code in &codes {
            assert_eq!(code.len(), 8, "each code should be 8 chars");
            assert!(code
                .chars()
                .all(|c| RECOVERY_CODE_ALPHABET.contains(&(c as u8))));
        }
    }

    #[test]
    fn test_generate_recovery_codes_unique() {
        let codes = generate_recovery_codes();
        let unique: std::collections::HashSet<_> = codes.iter().collect();
        assert_eq!(unique.len(), codes.len(), "codes should be unique");
    }

    #[test]
    fn test_hash_verify_recovery_code() {
        let code = "ABCD1234";
        let hash = hash_recovery_code(code).unwrap();

        assert!(verify_recovery_code(code, &hash).unwrap());
        assert!(!verify_recovery_code("WRONG123", &hash).unwrap());
    }

    #[test]
    fn test_recovery_code_case_insensitive() {
        let code = "ABCD1234";
        let hash = hash_recovery_code(code).unwrap();

        assert!(verify_recovery_code("abcd1234", &hash).unwrap());
        assert!(verify_recovery_code("AbCd1234", &hash).unwrap());
    }

    #[test]
    fn test_recovery_code_ignores_separators() {
        let code = "ABCD1234";
        let hash = hash_recovery_code(code).unwrap();

        assert!(verify_recovery_code("ABCD-1234", &hash).unwrap());
        assert!(verify_recovery_code("ABCD 1234", &hash).unwrap());
        assert!(verify_recovery_code("AB-CD 12-34", &hash).unwrap());
    }

    #[test]
    fn test_derive_recovery_key_deterministic() {
        // Same code+salt must produce the same key (regression guard for the
        // rename of derive_key -> derive_recovery_key).
        let code = "test-code";
        let salt = [1u8; 16];

        let key1 = derive_recovery_key(code, &salt).unwrap();
        let key2 = derive_recovery_key(code, &salt).unwrap();

        assert_eq!(key1, key2, "same code+salt should produce same key");
    }

    #[test]
    fn test_derive_recovery_key_different_salt() {
        let code = "test-code";
        let salt1 = [1u8; 16];
        let salt2 = [2u8; 16];

        let key1 = derive_recovery_key(code, &salt1).unwrap();
        let key2 = derive_recovery_key(code, &salt2).unwrap();

        assert_ne!(key1, key2, "different salts should produce different keys");
    }
}
