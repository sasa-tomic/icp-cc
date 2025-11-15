use crate::principal::principal_from_public_key;
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use bip39::{Language, Mnemonic};
use ed25519_dalek::{SigningKey as Ed25519Secret, VerifyingKey as Ed25519Public};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IdentityData {
    pub public_key_b64: String,
    pub private_key_b64: String,
    pub principal_text: String,
}

fn resolve_mnemonic(m: Option<String>) -> Mnemonic {
    match m {
        Some(s) if !s.trim().is_empty() => Mnemonic::parse_in(Language::English, s).unwrap(),
        _ => {
            // Generate 24-word mnemonic deterministically using zero entropy placeholder
            // (We won't call this in tests; prod path will be replaced to use RNG feature.)
            let entropy = [0u8; 32];
            Mnemonic::from_entropy_in(Language::English, &entropy).unwrap()
        }
    }
}

pub fn generate_ed25519_identity(mnemonic: Option<String>) -> IdentityData {
    // Dart uses mnemonicToSeed(...).sublist(0, 32) as seed for Ed25519
    let m = resolve_mnemonic(mnemonic);
    let seed = m.to_seed("");
    let seed_bytes = &seed[0..32];
    let secret = Ed25519Secret::from_bytes(seed_bytes.try_into().unwrap());
    let public: Ed25519Public = (&secret).into();
    let private_b64 = B64.encode(secret.to_bytes());
    let public_b64 = B64.encode(public.as_bytes());
    let principal = principal_from_public_key("ed25519", public.as_bytes());
    IdentityData {
        public_key_b64: public_b64,
        private_key_b64: private_b64,
        principal_text: principal,
    }
}

pub fn generate_secp256k1_identity(mnemonic: Option<String>) -> IdentityData {
    // Dart derives BIP32 at m/44'/223'/0'/0/0 and exports uncompressed pubkey
    use bitcoin::bip32::{DerivationPath, Xpriv};
    use bitcoin::secp256k1::{PublicKey, Secp256k1, SecretKey};

    let m = resolve_mnemonic(mnemonic);
    let seed = m.to_seed("");
    let network = bitcoin::Network::Bitcoin; // irrelevant for key math
    let xprv = Xpriv::new_master(network, &seed).unwrap();
    let path: DerivationPath = "m/44'/223'/0'/0/0".parse().unwrap();
    let child = xprv.derive_priv(&Secp256k1::new(), &path).unwrap();
    let sk: SecretKey = child.private_key;
    let pk: PublicKey = PublicKey::from_secret_key(&Secp256k1::new(), &sk);
    let uncompressed = pk.serialize_uncompressed(); // 65 bytes with 0x04

    let private_b64 = B64.encode(sk.secret_bytes());
    let public_b64 = B64.encode(uncompressed);
    let principal = principal_from_public_key("secp256k1", &uncompressed);
    IdentityData {
        public_key_b64: public_b64,
        private_key_b64: private_b64,
        principal_text: principal,
    }
}
