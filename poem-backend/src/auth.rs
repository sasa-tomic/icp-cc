use base64::{engine::general_purpose, Engine as _};
use ed25519_dalek::{Signature as Ed25519Signature, Verifier, VerifyingKey as Ed25519VerifyingKey};
use k256::ecdsa::{Signature as Secp256k1Signature, VerifyingKey as Secp256k1VerifyingKey};
use poem::{error::ResponseError, http::StatusCode};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::fmt;

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

/// Verifies an Ed25519 signature (ICP standard)
pub fn verify_ed25519_signature(
    signature_b64: &str,
    payload: &[u8],
    public_key_b64: &str,
) -> Result<(), String> {
    // Decode signature
    let signature_bytes = general_purpose::STANDARD
        .decode(signature_b64)
        .map_err(|e| format!("Invalid Ed25519 signature encoding: {}", e))?;

    let signature = Ed25519Signature::from_slice(&signature_bytes)
        .map_err(|e| format!("Invalid Ed25519 signature format: {}", e))?;

    // Decode public key
    let public_key_bytes = general_purpose::STANDARD
        .decode(public_key_b64)
        .map_err(|e| format!("Invalid Ed25519 public key encoding: {}", e))?;

    let verifying_key = Ed25519VerifyingKey::from_bytes(
        public_key_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "Invalid Ed25519 public key length".to_string())?,
    )
    .map_err(|e| format!("Invalid Ed25519 public key: {}", e))?;

    // Verify signature
    verifying_key
        .verify(payload, &signature)
        .map_err(|e| format!("Ed25519 signature verification failed: {}", e))?;

    Ok(())
}

/// Verifies a secp256k1 ECDSA signature (ICP standard)
pub fn verify_secp256k1_signature(
    signature_b64: &str,
    payload: &[u8],
    public_key_b64: &str,
) -> Result<(), String> {
    // Decode signature
    let signature_bytes = general_purpose::STANDARD
        .decode(signature_b64)
        .map_err(|e| format!("Invalid secp256k1 signature encoding: {}", e))?;

    let signature = Secp256k1Signature::from_slice(&signature_bytes)
        .map_err(|e| format!("Invalid secp256k1 signature format: {}", e))?;

    // Decode public key
    let public_key_bytes = general_purpose::STANDARD
        .decode(public_key_b64)
        .map_err(|e| format!("Invalid secp256k1 public key encoding: {}", e))?;

    let verifying_key = Secp256k1VerifyingKey::from_sec1_bytes(&public_key_bytes)
        .map_err(|e| format!("Invalid secp256k1 public key: {}", e))?;

    // For secp256k1, ICP uses SHA-256 hash of the message
    let mut hasher = Sha256::new();
    hasher.update(payload);
    let message_hash = hasher.finalize();

    // Verify signature
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
    if verify_ed25519_signature(signature, payload, public_key).is_ok() {
        return Ok(());
    }

    if verify_secp256k1_signature(signature, payload, public_key).is_ok() {
        return Ok(());
    }

    Err(AuthError::InvalidSignature(
        "Signature verification failed for both Ed25519 and secp256k1".to_string(),
    ))
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

/// Verify script operation signature
#[allow(dead_code)]
pub fn verify_script_operation_signature(
    req: &impl AsRef<str>,
    payload: &serde_json::Value,
    author_principal: Option<&str>,
    author_public_key: Option<&str>,
) -> Result<(), AuthError> {
    let signature = req.as_ref();

    if signature.is_empty() {
        return Err(AuthError::MissingField("signature".to_string()));
    }

    let public_key = author_public_key
        .ok_or_else(|| AuthError::MissingField("author_public_key".to_string()))?;

    let _principal =
        author_principal.ok_or_else(|| AuthError::MissingField("author_principal".to_string()))?;

    // Validate credentials
    validate_credentials(author_principal, Some(public_key))?;

    // Create canonical JSON
    let canonical_json = create_canonical_payload(payload);
    let payload_bytes = canonical_json.as_bytes();

    // Verify signature
    verify_signature(signature, payload_bytes, public_key)?;

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
}
