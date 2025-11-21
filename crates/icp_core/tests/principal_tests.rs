use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use icp_core::{generate_ed25519_keypair, generate_secp256k1_keypair, principal_from_public_key};
mod common;

#[test]
fn ed25519_principal_text_matches_dart() {
    let id = generate_ed25519_keypair(Some(common::MNEMONIC.to_string()));
    assert_eq!(id.principal_text, common::ED25519_PRINCIPAL);

    let public = B64.decode(id.public_key_b64.as_bytes()).unwrap();
    let p2 = principal_from_public_key("ed25519", &public).unwrap();
    assert_eq!(p2, id.principal_text);
}

#[test]
fn secp256k1_principal_text_matches_dart() {
    let id = generate_secp256k1_keypair(Some(common::MNEMONIC.to_string()));
    assert_eq!(id.principal_text, common::SECP256K1_PRINCIPAL);

    let public = B64.decode(id.public_key_b64.as_bytes()).unwrap();
    let p2 = principal_from_public_key("secp256k1", &public).unwrap();
    assert_eq!(p2, id.principal_text);
}
