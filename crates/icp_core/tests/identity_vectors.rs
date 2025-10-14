use icp_core::{generate_ed25519_identity, generate_secp256k1_identity};

#[test]
fn ed25519_known_vector_matches_dart() {
    let mnemonic = Some("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art".to_string());
    let id = generate_ed25519_identity(mnemonic);
    assert_eq!(
        id.private_key_b64,
        "QIsoXBI4NgBPS4hCyJMkwfATgkUMDUOa80W6f8Saz3A="
    );
    assert_eq!(
        id.public_key_b64,
        "HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE="
    );
}

#[test]
fn secp256k1_known_vector_matches_dart() {
    let mnemonic = Some("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art".to_string());
    let id = generate_secp256k1_identity(mnemonic);
    assert_eq!(
        id.private_key_b64,
        "Yb+9dY8vXeoLiLMSqhpHbE4MhT2HkGRk0Ai8NkBcD/I="
    );
    assert_eq!(
        id.public_key_b64,
        "BBz+IZWfHzq8STHpP6u3hU/DOJS6Fy5m3ewbQautk0Vd3u79WEhh0/0gvh886bxxFK9et89Fi2sBc4LDysmVe4g="
    );
}
