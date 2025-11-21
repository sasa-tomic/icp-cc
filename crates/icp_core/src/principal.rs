use candid::Principal;
use ed25519_dalek::pkcs8::EncodePublicKey as _;
// k256's EncodePublicKey is re-exported and auto-imported via the pkcs8 feature

/// Compute principal from DER-encoded public key (per IC spec).
pub fn principal_from_der(der: &[u8]) -> String {
    Principal::self_authenticating(der).to_text()
}

/// DER-encode a raw public key per RFC 8410 (Ed25519) or RFC 5480 (secp256k1).
pub fn der_encode_public_key(alg: &str, public_key: &[u8]) -> Result<Vec<u8>, String> {
    match alg {
        "ed25519" => {
            let pk = ed25519_dalek::VerifyingKey::from_bytes(
                public_key
                    .try_into()
                    .map_err(|_| "Ed25519 key must be 32 bytes")?,
            )
            .map_err(|e| e.to_string())?;
            Ok(pk
                .to_public_key_der()
                .map_err(|e| e.to_string())?
                .as_bytes()
                .to_vec())
        }
        "secp256k1" => {
            // Accept 64-byte (raw X||Y) or 65-byte (0x04||X||Y) uncompressed key
            let key_bytes: Vec<u8> = if public_key.len() == 64 {
                std::iter::once(0x04).chain(public_key.iter().copied()).collect()
            } else {
                public_key.to_vec()
            };
            let pk = k256::PublicKey::from_sec1_bytes(&key_bytes).map_err(|e| e.to_string())?;
            Ok(pk
                .to_public_key_der()
                .map_err(|e| e.to_string())?
                .as_bytes()
                .to_vec())
        }
        _ => Err(format!("unsupported algorithm: {alg}")),
    }
}

/// Compute principal from raw public key bytes.
pub fn principal_from_public_key(alg: &str, public_key: &[u8]) -> String {
    let der = der_encode_public_key(alg, public_key).expect("DER encoding failed");
    principal_from_der(&der)
}
