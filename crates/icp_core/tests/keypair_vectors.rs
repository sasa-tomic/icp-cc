use icp_core::{generate_ed25519_keypair, generate_secp256k1_keypair};
mod common;

#[test]
fn ed25519_known_vector_matches_dart() {
    let id = generate_ed25519_keypair(Some(common::MNEMONIC.to_string()));
    assert_eq!(id.private_key_b64, common::ED25519_PRIVATE_B64);
    assert_eq!(id.public_key_b64, common::ED25519_PUBLIC_B64);
}

#[test]
fn secp256k1_known_vector_matches_dart() {
    let id = generate_secp256k1_keypair(Some(common::MNEMONIC.to_string()));
    assert_eq!(id.private_key_b64, common::SECP256K1_PRIVATE_B64);
    assert_eq!(id.public_key_b64, common::SECP256K1_PUBLIC_B64);
}
