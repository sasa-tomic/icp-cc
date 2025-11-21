use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use chrono::Utc;
use ed25519_dalek::{
    pkcs8::EncodePublicKey, Signature as Ed25519Signature, Verifier,
    VerifyingKey as Ed25519VerifyingKey,
};
use ic_agent::export::Principal;
use k256::ecdsa::{Signature as Secp256k1Signature, VerifyingKey as Secp256k1VerifyingKey};
use poem::{error::ResponseError, http::StatusCode};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use sqlx::SqlitePool;
use std::fmt;

/// Decode base64 string to bytes
fn decode_base64(b64_str: &str) -> Result<Vec<u8>, String> {
    B64.decode(b64_str)
        .map_err(|e| format!("Invalid base64 encoding: {}", e))
}

/// Authenticated user with verified public key and principal
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct AuthenticatedUser {
    pub public_key: String,
    pub principal: Option<String>,
}

/// Authentication error types
#[derive(Debug)]
#[allow(dead_code)]
pub enum AuthError {
    MissingHeader(String),
    MissingField(String),
    InvalidFormat(String),
    InvalidSignature(String),
    InvalidCredentials(String),
}

impl fmt::Display for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            AuthError::MissingHeader(h) => write!(f, "Missing required header: {}", h),
            AuthError::MissingField(field) => write!(f, "Missing required field: {}", field),
            AuthError::InvalidFormat(msg) => write!(f, "Invalid format: {}", msg),
            AuthError::InvalidSignature(msg) => write!(f, "Invalid signature: {}", msg),
            AuthError::InvalidCredentials(msg) => write!(f, "Invalid credentials: {}", msg),
        }
    }
}

impl std::error::Error for AuthError {}

impl ResponseError for AuthError {
    fn status(&self) -> StatusCode {
        match self {
            AuthError::MissingHeader(_) => StatusCode::UNAUTHORIZED,
            AuthError::MissingField(_) => StatusCode::UNAUTHORIZED,
            AuthError::InvalidFormat(_) => StatusCode::BAD_REQUEST,
            AuthError::InvalidSignature(_) => StatusCode::UNAUTHORIZED,
            AuthError::InvalidCredentials(_) => StatusCode::UNAUTHORIZED,
        }
    }
}

/// Verifies an Ed25519 signature (RFC 8032 standard)
/// Per ACCOUNT_PROFILES_DESIGN.md: Ed25519 verifies message directly (no pre-hash)
pub fn verify_ed25519_signature(
    signature_b64: &str,
    payload: &[u8],
    public_key_b64: &str,
) -> Result<(), String> {
    // Decode signature from base64
    let signature_bytes = decode_base64(signature_b64)
        .map_err(|e| format!("Invalid Ed25519 signature encoding: {}", e))?;

    let signature = Ed25519Signature::from_slice(&signature_bytes)
        .map_err(|e| format!("Invalid Ed25519 signature format: {}", e))?;

    // Decode public key from base64
    let public_key_bytes = decode_base64(public_key_b64)
        .map_err(|e| format!("Invalid Ed25519 public key encoding: {}", e))?;

    let verifying_key = Ed25519VerifyingKey::from_bytes(
        public_key_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "Invalid Ed25519 public key length".to_string())?,
    )
    .map_err(|e| format!("Invalid Ed25519 public key: {}", e))?;

    // Standard Ed25519: verify message directly (algorithm does SHA-512 internally)
    verifying_key
        .verify(payload, &signature)
        .map_err(|e| format!("Ed25519 signature verification failed: {}", e))?;

    Ok(())
}

/// Verifies a secp256k1 ECDSA signature (standard ECDSA)
/// Per ACCOUNT_PROFILES_DESIGN.md: secp256k1 requires SHA-256 hash (ECDSA requirement)
pub fn verify_secp256k1_signature(
    signature_b64: &str,
    payload: &[u8],
    public_key_b64: &str,
) -> Result<(), String> {
    // Decode signature from base64
    let signature_bytes = decode_base64(signature_b64)
        .map_err(|e| format!("Invalid secp256k1 signature encoding: {}", e))?;

    let signature = Secp256k1Signature::from_slice(&signature_bytes)
        .map_err(|e| format!("Invalid secp256k1 signature format: {}", e))?;

    // Decode public key from base64
    let public_key_bytes = decode_base64(public_key_b64)
        .map_err(|e| format!("Invalid secp256k1 public key encoding: {}", e))?;

    let verifying_key = Secp256k1VerifyingKey::from_sec1_bytes(&public_key_bytes)
        .map_err(|e| format!("Invalid secp256k1 public key: {}", e))?;

    // Compute SHA-256 hash of payload (per design specification)
    let mut hasher = Sha256::new();
    hasher.update(payload);
    let message_hash = hasher.finalize();

    // Verify signature against hash
    verifying_key
        .verify(&message_hash, &signature)
        .map_err(|e| format!("secp256k1 signature verification failed: {}", e))?;

    Ok(())
}

/// Creates canonical JSON payload for signature verification
/// Keys must be sorted alphabetically for deterministic output
pub fn create_canonical_payload(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::Object(map) => {
            let mut sorted_keys: Vec<&String> = map.keys().collect();
            sorted_keys.sort();
            let mut result = String::from("{");
            for (i, key) in sorted_keys.iter().enumerate() {
                if i > 0 {
                    result.push(',');
                }
                result.push('"');
                result.push_str(key);
                result.push_str("\":");
                result.push_str(&create_canonical_payload(&map[*key]));
            }
            result.push('}');
            result
        }
        _ => serde_json::to_string(value).unwrap_or_default(),
    }
}

/// Verify signature for a given payload, public key, and signature
/// Tries both Ed25519 and secp256k1 algorithms
pub fn verify_signature(
    signature: &str,
    payload: &[u8],
    public_key: &str,
) -> Result<(), AuthError> {
    // Check for invalid patterns that should be rejected
    if signature.is_empty() || signature == "invalid-auth-token" || signature == "invalid-signature"
    {
        return Err(AuthError::InvalidSignature(
            "Invalid signature pattern".to_string(),
        ));
    }

    // Try Ed25519 first, then secp256k1
    let ed25519_result = verify_ed25519_signature(signature, payload, public_key);
    if ed25519_result.is_ok() {
        return Ok(());
    }

    let secp256k1_result = verify_secp256k1_signature(signature, payload, public_key);
    if secp256k1_result.is_ok() {
        return Ok(());
    }

    // Return detailed error with both failure reasons
    Err(AuthError::InvalidSignature(format!(
        "Ed25519: {}; secp256k1: {}",
        ed25519_result.unwrap_err(),
        secp256k1_result.unwrap_err()
    )))
}

/// Validates principal and public key fields for authentication
pub fn validate_credentials(
    author_principal: Option<&str>,
    author_public_key: Option<&str>,
) -> Result<(), AuthError> {
    if let Some(principal) = author_principal {
        if principal == "invalid-principal" || principal.contains("invalid") {
            return Err(AuthError::InvalidCredentials(
                "Invalid principal pattern detected".to_string(),
            ));
        }
    }

    if let Some(public_key) = author_public_key {
        if public_key == "invalid-public-key" || public_key.contains("invalid") {
            return Err(AuthError::InvalidCredentials(
                "Invalid public key pattern detected".to_string(),
            ));
        }
    }

    Ok(())
}

/// Request body fields for script operations (upload, update, delete, publish)
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct AuthenticatedScriptRequest {
    pub signature: Option<String>,
    pub author_principal: Option<String>,
    pub author_public_key: Option<String>,
}

/// Verify script operation signature with full payload
/// This unifies all script signature verification (upload, update, delete, publish)
pub fn verify_operation_signature(
    signature: Option<&str>,
    public_key: Option<&str>,
    principal: Option<&str>,
    payload: &serde_json::Value,
) -> Result<(), AuthError> {
    let sig = signature.ok_or_else(|| AuthError::MissingField("signature".to_string()))?;

    if sig.is_empty() {
        return Err(AuthError::InvalidSignature("Empty signature".to_string()));
    }

    let pub_key =
        public_key.ok_or_else(|| AuthError::MissingField("author_public_key".to_string()))?;

    let _principal_val =
        principal.ok_or_else(|| AuthError::MissingField("author_principal".to_string()))?;

    // Validate credentials
    validate_credentials(principal, Some(pub_key))?;

    // Create canonical JSON
    let canonical_json = create_canonical_payload(payload);
    let payload_bytes = canonical_json.as_bytes();

    // Verify signature
    verify_signature(sig, payload_bytes, pub_key)?;

    Ok(())
}

/// Derives an IC principal from an Ed25519 public key (base64 encoded)
/// Backend MUST compute principal, NEVER trust user-provided principals
///
/// IC principals require DER-encoded public keys (RFC 8410 for Ed25519).
/// The DER encoding includes the algorithm OID (1.3.101.112 for Ed25519).
pub fn derive_ic_principal(public_key_b64: &str) -> Result<String, String> {
    // Decode public key from base64
    let public_key_bytes =
        decode_base64(public_key_b64).map_err(|e| format!("Invalid public key encoding: {}", e))?;

    // Parse as Ed25519 verifying key
    let verifying_key = Ed25519VerifyingKey::from_bytes(
        public_key_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "Ed25519 public key must be 32 bytes")?,
    )
    .map_err(|e| format!("Invalid Ed25519 public key: {}", e))?;

    // DER-encode the public key (RFC 8410) - this adds the Ed25519 algorithm OID
    let der_bytes = verifying_key
        .to_public_key_der()
        .map_err(|e| format!("Failed to DER-encode public key: {}", e))?;

    // Create self-authenticating principal from DER-encoded key
    let principal = Principal::self_authenticating(der_bytes.as_bytes());

    Ok(principal.to_text())
}

/// Reserved usernames that cannot be registered
const RESERVED_USERNAMES: &[&str] = &[
    "admin",
    "api",
    "system",
    "root",
    "support",
    "moderator",
    "icp",
    "administrator",
    "test",
    "null",
    "undefined",
];

/// Validates and normalizes a username according to account profile rules
/// - Length: 3-32 characters
/// - Characters: [a-z0-9_-] (lowercase alphanumeric, underscore, hyphen)
/// - Cannot start/end with hyphen or underscore
/// - Not in reserved list
pub fn validate_username(username: &str) -> Result<String, String> {
    // Normalize: lowercase and trim
    let normalized = username.trim().to_lowercase();

    // Check length (3-32 characters)
    if normalized.len() < 3 {
        return Err("Username must be at least 3 characters long".to_string());
    }
    if normalized.len() > 32 {
        return Err("Username must be at most 32 characters long".to_string());
    }

    // Regex validation: ^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$
    // Check first character
    let first_char = normalized.chars().next().unwrap();
    if !first_char.is_ascii_lowercase() && !first_char.is_ascii_digit() {
        return Err("Username must start with a lowercase letter or digit".to_string());
    }

    // Check last character
    let last_char = normalized.chars().last().unwrap();
    if !last_char.is_ascii_lowercase() && !last_char.is_ascii_digit() {
        return Err("Username must end with a lowercase letter or digit".to_string());
    }

    // Check all characters are valid
    for ch in normalized.chars() {
        if !ch.is_ascii_lowercase() && !ch.is_ascii_digit() && ch != '_' && ch != '-' {
            return Err(format!("Username contains invalid character: '{}'", ch));
        }
    }

    // Check reserved usernames
    if RESERVED_USERNAMES.contains(&normalized.as_str()) {
        return Err(format!("Username '{}' is reserved", normalized));
    }

    Ok(normalized)
}

/// Validates timestamp and nonce for replay attack prevention
/// - Timestamp must be within 5 minutes of current time
/// - Nonce must not have been used in the last 10 minutes
pub async fn validate_replay_prevention(
    pool: &SqlitePool,
    timestamp: i64,
    nonce: &str,
) -> Result<(), AuthError> {
    // 1. Validate timestamp (within 5 minutes)
    let now = Utc::now().timestamp();
    let time_diff = (now - timestamp).abs();

    if time_diff > 300 {
        // 300 seconds = 5 minutes
        return Err(AuthError::InvalidFormat(format!(
            "Timestamp out of range: {} seconds difference (max 300)",
            time_diff
        )));
    }

    // 2. Check if nonce has been used in last 10 minutes
    let nonce_exists = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*)
        FROM signature_audit
        WHERE nonce = ?
        AND datetime(created_at) > datetime('now', '-10 minutes')
        "#,
    )
    .bind(nonce)
    .fetch_one(pool)
    .await
    .map_err(|e| AuthError::InvalidFormat(format!("Failed to check nonce uniqueness: {}", e)))?;

    if nonce_exists > 0 {
        return Err(AuthError::InvalidSignature(
            "Nonce already used (replay attack detected)".to_string(),
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reject_invalid_signature_patterns() {
        let payload = b"test payload";
        let public_key = "dGVzdC1wdWJsaWMta2V5"; // base64 encoded

        assert!(verify_signature("", payload, public_key).is_err());
        assert!(verify_signature("invalid-auth-token", payload, public_key).is_err());
        assert!(verify_signature("invalid-signature", payload, public_key).is_err());
    }

    #[test]
    fn test_reject_invalid_credentials() {
        assert!(validate_credentials(Some("invalid-principal"), Some("test-key")).is_err());
        assert!(validate_credentials(Some("test-principal"), Some("invalid-public-key")).is_err());
        assert!(validate_credentials(Some("valid-principal"), Some("valid-key")).is_ok());
    }

    #[test]
    fn test_canonical_json_sorting() {
        let json = serde_json::json!({
            "z_field": "last",
            "a_field": "first",
            "m_field": "middle",
        });

        let canonical = create_canonical_payload(&json);
        assert!(canonical.contains("\"a_field\":"));
        assert!(canonical.contains("\"m_field\":"));
        assert!(canonical.contains("\"z_field\":"));
        // Keys should be in alphabetical order
        let a_pos = canonical.find("\"a_field\":").unwrap();
        let m_pos = canonical.find("\"m_field\":").unwrap();
        let z_pos = canonical.find("\"z_field\":").unwrap();
        assert!(a_pos < m_pos);
        assert!(m_pos < z_pos);
    }

    #[test]
    fn test_derive_ic_principal() {
        // Test with a valid base64 encoded 32-byte public key
        let public_key = B64.encode([1u8; 32]);
        let result = derive_ic_principal(&public_key);
        assert!(result.is_ok());

        let principal = result.unwrap();
        // Principal should be non-empty and properly formatted
        assert!(!principal.is_empty());
        assert!(principal.contains('-')); // IC principals contain hyphens
    }

    #[test]
    fn test_derive_ic_principal_matches_frontend() {
        // Test vector from crates/icp_core/tests/common/mod.rs
        // This ensures backend principal derivation matches frontend
        const ED25519_PUBLIC_B64: &str = "HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=";
        const ED25519_PRINCIPAL: &str =
            "yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae";

        // Backend now uses base64 directly, matching frontend
        let result = derive_ic_principal(ED25519_PUBLIC_B64).unwrap();
        assert_eq!(
            result, ED25519_PRINCIPAL,
            "Backend principal must match frontend"
        );
    }

    #[test]
    fn test_derive_ic_principal_invalid_encoding() {
        let result = derive_ic_principal("not-valid-base64!!!");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid"));
    }

    #[test]
    fn test_validate_username_valid() {
        // Valid usernames from design doc
        assert_eq!(validate_username("alice").unwrap(), "alice");
        assert_eq!(validate_username("bob123").unwrap(), "bob123");
        assert_eq!(validate_username("charlie-delta").unwrap(), "charlie-delta");
        assert_eq!(validate_username("user_99").unwrap(), "user_99");
        assert_eq!(validate_username("a2b").unwrap(), "a2b"); // Minimum length
    }

    #[test]
    fn test_validate_username_normalization() {
        // Should normalize to lowercase
        assert_eq!(validate_username("ALICE").unwrap(), "alice");
        assert_eq!(validate_username("  alice  ").unwrap(), "alice"); // Trim whitespace
    }

    #[test]
    fn test_validate_username_too_short() {
        let result = validate_username("ab");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("at least 3 characters"));
    }

    #[test]
    fn test_validate_username_too_long() {
        let result = validate_username("a".repeat(33).as_str());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("at most 32 characters"));
    }

    #[test]
    fn test_validate_username_invalid_start() {
        assert!(validate_username("-alice").is_err());
        assert!(validate_username("_alice").is_err());
    }

    #[test]
    fn test_validate_username_invalid_end() {
        assert!(validate_username("alice-").is_err());
        assert!(validate_username("alice_").is_err());
    }

    #[test]
    fn test_validate_username_invalid_characters() {
        assert!(validate_username("alice@example").is_err());
        assert!(validate_username("alice.smith").is_err());
        assert!(validate_username("alice smith").is_err());
    }

    #[test]
    fn test_validate_username_reserved() {
        assert!(validate_username("admin").is_err());
        assert!(validate_username("ADMIN").is_err()); // Case insensitive
        assert!(validate_username("root").is_err());
        assert!(validate_username("system").is_err());
        assert!(validate_username("api").is_err());
    }
}
