//! Vault encryption utilities (Argon2id KDF + AES-GCM)
//!
//! Per PASSKEY_IMPLEMENTATION_PLAN.md:
//! - Argon2id: time=3, memory=64MB, parallelism=4, output=32 bytes
//! - AES-GCM: key=256 bits, nonce=96 bits

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use argon2::{Argon2, Params, Version};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use rand::RngCore;

/// Argon2id parameters (Bitwarden-level security)
const ARGON2_TIME_COST: u32 = 3;
const ARGON2_MEMORY_COST: u32 = 65536; // 64 MB
const ARGON2_PARALLELISM: u32 = 4;
const ARGON2_OUTPUT_LEN: usize = 32;
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 12;

/// Encrypted vault data with all components needed for decryption
#[derive(Debug, Clone)]
pub struct EncryptedVault {
    pub encrypted_data: Vec<u8>,
    pub salt: Vec<u8>,
    pub nonce: Vec<u8>,
}

/// Derives a 256-bit key from password using Argon2id
pub fn derive_key(password: &str, salt: &[u8]) -> Result<[u8; 32], String> {
    let params = Params::new(ARGON2_MEMORY_COST, ARGON2_TIME_COST, ARGON2_PARALLELISM, Some(ARGON2_OUTPUT_LEN))
        .map_err(|e| format!("Invalid Argon2 params: {}", e))?;

    let argon2 = Argon2::new(argon2::Algorithm::Argon2id, Version::V0x13, params);

    let mut key = [0u8; 32];
    argon2.hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|e| format!("Key derivation failed: {}", e))?;

    Ok(key)
}

/// Generates cryptographically secure random bytes
pub fn generate_salt() -> [u8; SALT_LEN] {
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    salt
}

/// Generates cryptographically secure random nonce for AES-GCM
pub fn generate_nonce() -> [u8; NONCE_LEN] {
    let mut nonce = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut nonce);
    nonce
}

/// Encrypts data with AES-256-GCM using a password-derived key
pub fn encrypt_vault(password: &str, plaintext: &[u8]) -> Result<EncryptedVault, String> {
    let salt = generate_salt();
    let nonce_bytes = generate_nonce();

    let key = derive_key(password, &salt)?;
    let cipher = Aes256Gcm::new_from_slice(&key)
        .map_err(|e| format!("Cipher init failed: {}", e))?;

    let nonce = Nonce::from_slice(&nonce_bytes);
    let encrypted_data = cipher.encrypt(nonce, plaintext)
        .map_err(|e| format!("Encryption failed: {}", e))?;

    Ok(EncryptedVault {
        encrypted_data,
        salt: salt.to_vec(),
        nonce: nonce_bytes.to_vec(),
    })
}

/// Decrypts AES-256-GCM encrypted data using a password-derived key
pub fn decrypt_vault(password: &str, vault: &EncryptedVault) -> Result<Vec<u8>, String> {
    let key = derive_key(password, &vault.salt)?;
    let cipher = Aes256Gcm::new_from_slice(&key)
        .map_err(|e| format!("Cipher init failed: {}", e))?;

    let nonce = Nonce::from_slice(&vault.nonce);
    cipher.decrypt(nonce, vault.encrypted_data.as_ref())
        .map_err(|_| "Decryption failed: invalid password or corrupted data".to_string())
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
    let key = derive_key(&normalized, &salt)?;
    Ok(format!("{}${}", B64.encode(salt), B64.encode(key)))
}

/// Verifies a recovery code against a stored hash
pub fn verify_recovery_code(code: &str, hash: &str) -> Result<bool, String> {
    let normalized = code.to_uppercase().replace(['-', ' '], "");
    let parts: Vec<&str> = hash.split('$').collect();
    if parts.len() != 2 {
        return Err("Invalid hash format".to_string());
    }

    let salt = B64.decode(parts[0]).map_err(|e| format!("Invalid salt: {}", e))?;
    let stored_key = B64.decode(parts[1]).map_err(|e| format!("Invalid key: {}", e))?;
    let derived_key = derive_key(&normalized, &salt)?;

    Ok(derived_key[..] == stored_key[..])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let password = "test-password-123";
        let plaintext = b"secret vault data";

        let vault = encrypt_vault(password, plaintext).expect("encryption should succeed");
        let decrypted = decrypt_vault(password, &vault).expect("decryption should succeed");

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_wrong_password_fails() {
        let password = "correct-password";
        let wrong_password = "wrong-password";
        let plaintext = b"secret data";

        let vault = encrypt_vault(password, plaintext).expect("encryption should succeed");
        let result = decrypt_vault(wrong_password, &vault);

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("invalid password"));
    }

    #[test]
    fn test_corrupted_data_fails() {
        let password = "test-password";
        let plaintext = b"secret data";

        let mut vault = encrypt_vault(password, plaintext).expect("encryption should succeed");
        vault.encrypted_data[0] ^= 0xFF; // Corrupt first byte

        let result = decrypt_vault(password, &vault);
        assert!(result.is_err());
    }

    #[test]
    fn test_unique_salt_per_encryption() {
        let password = "same-password";
        let plaintext = b"same data";

        let vault1 = encrypt_vault(password, plaintext).unwrap();
        let vault2 = encrypt_vault(password, plaintext).unwrap();

        assert_ne!(vault1.salt, vault2.salt, "salts should be unique");
        assert_ne!(vault1.nonce, vault2.nonce, "nonces should be unique");
        assert_ne!(vault1.encrypted_data, vault2.encrypted_data, "ciphertexts should differ");
    }

    #[test]
    fn test_derive_key_deterministic() {
        let password = "test-password";
        let salt = [1u8; 16];

        let key1 = derive_key(password, &salt).unwrap();
        let key2 = derive_key(password, &salt).unwrap();

        assert_eq!(key1, key2, "same password+salt should produce same key");
    }

    #[test]
    fn test_derive_key_different_salt() {
        let password = "test-password";
        let salt1 = [1u8; 16];
        let salt2 = [2u8; 16];

        let key1 = derive_key(password, &salt1).unwrap();
        let key2 = derive_key(password, &salt2).unwrap();

        assert_ne!(key1, key2, "different salts should produce different keys");
    }

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
            assert!(code.chars().all(|c| RECOVERY_CODE_ALPHABET.contains(&(c as u8))));
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
}
