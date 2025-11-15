use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use icp_core::{generate_ed25519_identity, generate_secp256k1_identity, principal_from_public_key};

#[test]
fn ed25519_principal_text_matches_dart() {
    let mnemonic = Some("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art".to_string());
    let id = generate_ed25519_identity(mnemonic);
    assert_eq!(
        id.principal_text,
        "yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae"
    );

    let public = B64.decode(id.public_key_b64.as_bytes()).unwrap();
    let p2 = principal_from_public_key("ed25519", &public);
    assert_eq!(p2, id.principal_text);
}

#[test]
fn secp256k1_principal_text_matches_dart() {
    let mnemonic = Some("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art".to_string());
    let id = generate_secp256k1_identity(mnemonic);
    assert_eq!(
        id.principal_text,
        "m7bn6-s5er4-xouui-ymkqf-azncv-qfche-3qghk-2fvpm-atfyh-ozg2w-iqe"
    );

    let public = B64.decode(id.public_key_b64.as_bytes()).unwrap();
    let p2 = principal_from_public_key("secp256k1", &public);
    assert_eq!(p2, id.principal_text);
}
