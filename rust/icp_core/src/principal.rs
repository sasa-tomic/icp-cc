use candid::Principal;

pub fn principal_from_der(der: &[u8]) -> String {
    // candid::Principal::self_authenticating expects the DER-encoded public key
    // and internally computes SHA-224 and the self-authenticating tag.
    Principal::self_authenticating(der).to_text()
}

pub fn principal_from_public_key(alg: &str, public_key: &[u8]) -> String {
    let der = match alg {
        "ed25519" => {
            // 302a300506032b6570032100 || 32-byte raw public key
            let mut out = Vec::with_capacity(12 + 32);
            out.extend_from_slice(&hex_literal::hex!("302a300506032b6570032100"));
            out.extend_from_slice(public_key);
            out
        }
        "secp256k1" => {
            // SPKI with uncompressed key (0x04 || X || Y)
            // Prefix through the bit string header (before the 0x04)
            let mut key = Vec::from(public_key);
            if key.len() == 64 {
                key.insert(0, 0x04);
            }
            assert!(
                key.len() == 65 && key[0] == 0x04,
                "secp256k1 uncompressed key required"
            );
            let mut out = Vec::with_capacity(27 + 65);
            out.extend_from_slice(&hex_literal::hex!(
                "3056301006072a8648ce3d020106052b8104000a034200"
            ));
            out.extend_from_slice(&key);
            out
        }
        _ => panic!("unsupported alg"),
    };
    principal_from_der(&der)
}
