//! A software WebAuthn authenticator for the passkey service tests.
//!
//! Produces GENUINE WebAuthn responses that the real `webauthn-rs` verifier
//! accepts (registration attestation + authentication assertion), so the
//! passkey tests exercise the real verification path — no mocking.
//!
//! The COSE key is a real P-256 (EC2 / ES256) keypair; the attestation object
//! is CBOR-encoded (`fmt = "none"`); the assertion signature is a real ES256
//! signature over `SHA-256(authenticatorData || SHA-256(clientDataJSON))`. The
//! assembled responses are built as JSON and deserialised into the
//! `webauthn-rs-proto` types — identical to how a browser client transmits
//! them — which keeps the test free of the proto crate's optional/extension
//! field boilerplate.
//!
//! Note: this is deliberately separate from the Dart-side
//! `FakePasskeyAuthenticator` (a mock-the-mock fixture checked against its own
//! CBOR re-implementation). Here the verifier under test is the REAL
//! `webauthn-rs`, so a bug in either the service wiring or the verifier
//! surfaces.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD as B64URL, Engine as _};
use ciborium::value::Value;
use p256::ecdsa::{signature::Signer, DerSignature, SigningKey, VerifyingKey};
use rand::RngCore;
use sha2::{Digest, Sha256};
use webauthn_rs_proto::{
    CreationChallengeResponse, PublicKeyCredential, RegisterPublicKeyCredential,
    RequestChallengeResponse,
};

const FLAG_USER_PRESENT: u8 = 0x01;
const FLAG_USER_VERIFIED: u8 = 0x04;
const FLAG_ATTESTED: u8 = 0x40;

/// A minimal virtual authenticator holding one P-256 credential.
pub struct SoftAuthenticator {
    signing_key: SigningKey,
    credential_id: Vec<u8>,
}

impl Default for SoftAuthenticator {
    fn default() -> Self {
        Self::new()
    }
}

impl SoftAuthenticator {
    /// Generate a fresh, unique credential (random P-256 key + random id).
    /// The signing-key seed is retried until it is a valid P-256 scalar — a
    /// random 32-byte value is almost always valid, but we never want a
    /// one-in-2^128 flake.
    pub fn new() -> Self {
        let mut rng = rand::thread_rng();
        let signing_key = loop {
            let mut seed = [0u8; 32];
            rng.fill_bytes(&mut seed);
            if let Ok(k) = SigningKey::from_bytes(&seed.into()) {
                break k;
            }
        };
        let mut cred_id = [0u8; 16];
        rng.fill_bytes(&mut cred_id);
        Self {
            signing_key,
            credential_id: cred_id.to_vec(),
        }
    }

    /// The credential id this authenticator chose. After a successful
    /// registration this is the credential id the server stores.
    pub fn credential_id(&self) -> Vec<u8> {
        self.credential_id.clone()
    }

    fn verifying_key(&self) -> VerifyingKey {
        VerifyingKey::from(&self.signing_key)
    }

    /// CBOR-encoded COSE P-256 public key (kty=EC2, alg=ES256, crv=P-256).
    fn cose_public_key(&self) -> Vec<u8> {
        let encoded = self.verifying_key().to_encoded_point(false);
        let x = encoded.x().expect("uncompressed point has x").to_vec();
        let y = encoded.y().expect("uncompressed point has y").to_vec();

        let cose = Value::Map(vec![
            (1u64.into(), 2u64.into()), // kty = EC2
            (3u64.into(), (-7i64).into()), // alg = ES256
            ((-1i64).into(), 1u64.into()), // crv = P-256
            ((-2i64).into(), Value::Bytes(x)), // x
            ((-3i64).into(), Value::Bytes(y)), // y
        ]);
        let mut out = Vec::new();
        ciborium::into_writer(&cose, &mut out).expect("encode cose key");
        out
    }

    /// Build a registration response the real verifier will accept for the
    /// given challenge + RP.
    pub fn register_response(
        &self,
        options: &CreationChallengeResponse,
        rp_id: &str,
        origin: &str,
    ) -> Result<RegisterPublicKeyCredential, String> {
        let challenge = options.public_key.challenge.as_slice();
        let client_data = build_client_data("webauthn.create", challenge, origin);
        let auth_data =
            build_registration_auth_data(rp_id, &self.credential_id, self.cose_public_key());

        // Attestation object: fmt "none" with an empty attStmt.
        let att_obj = Value::Map(vec![
            ("fmt".into(), "none".into()),
            ("attStmt".into(), Value::Map(vec![])),
            ("authData".into(), Value::Bytes(auth_data)),
        ]);
        let mut att_bytes = Vec::new();
        ciborium::into_writer(&att_obj, &mut att_bytes).map_err(|e| format!("cbor: {e}"))?;

        let cred_id_b64 = B64URL.encode(&self.credential_id);
        let json = serde_json::json!({
            "id": cred_id_b64,
            "rawId": cred_id_b64,
            "response": {
                "attestationObject": B64URL.encode(&att_bytes),
                "clientDataJSON": B64URL.encode(&client_data),
            },
            "type": "public-key"
        });
        serde_json::from_value(json).map_err(|e| format!("deserialize: {e}"))
    }

    /// A throwaway registration response — used by negative tests where the
    /// service fails BEFORE verification (e.g. unknown challenge id), so the
    /// credential contents are irrelevant; it only needs to be a parseable
    /// `RegisterPublicKeyCredential`.
    pub fn dummy_register_response(&self) -> RegisterPublicKeyCredential {
        let cred_id_b64 = B64URL.encode(&self.credential_id);
        let json = serde_json::json!({
            "id": cred_id_b64,
            "rawId": cred_id_b64,
            "response": {
                "attestationObject": B64URL.encode([0u8; 1]),
                "clientDataJSON": B64URL.encode(b"{}"),
            },
            "type": "public-key"
        });
        serde_json::from_value(json).expect("dummy register json must deserialize")
    }

    /// Build an authentication assertion for the given challenge, origin and
    /// counter. `counter` must be strictly greater than the credential's
    /// counter (as the server recorded it) for the monotonicity check to pass.
    pub fn authenticate_response(
        &self,
        options: &RequestChallengeResponse,
        origin: &str,
        counter: u32,
    ) -> Result<PublicKeyCredential, String> {
        let challenge = options.public_key.challenge.as_slice();
        let rp_id = options.public_key.rp_id.clone();
        let client_data = build_client_data("webauthn.get", challenge, origin);
        let auth_data = build_assertion_auth_data(&rp_id, counter);

        // ES256 signature over SHA-256(authenticatorData || SHA-256(clientData)).
        // p256's `Signer<DerSignature>` impl SHA-256 hashes the message internally
        // (NistP256: DigestPrimitive = Sha256), matching the WebAuthn spec.
        //
        // We emit the DER-encoded form: webauthn-rs 0.5 verifies via OpenSSL,
        // whose ECDSA `EVP_DigestVerifyFinal` requires an ASN.1 DER signature
        // (a raw r‖s byte string is rejected with an OpenSSL parse error).
        let client_data_hash = Sha256::digest(&client_data);
        let signed_message: Vec<u8> =
            [auth_data.as_slice(), client_data_hash.as_slice()].concat();
        let signature: DerSignature = self.signing_key.sign(&signed_message);

        let cred_id_b64 = B64URL.encode(&self.credential_id);
        let json = serde_json::json!({
            "id": cred_id_b64,
            "rawId": cred_id_b64,
            "response": {
                "authenticatorData": B64URL.encode(&auth_data),
                "clientDataJSON": B64URL.encode(&client_data),
                "signature": B64URL.encode(signature.to_bytes()),
            },
            "type": "public-key"
        });
        serde_json::from_value(json).map_err(|e| format!("deserialize: {e}"))
    }
}

fn build_client_data(type_: &str, challenge: &[u8], origin: &str) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "type": type_,
        "challenge": B64URL.encode(challenge),
        "origin": origin,
        "crossOrigin": false,
    }))
    .expect("client data json must serialize")
}

fn rp_id_hash(rp_id: &str) -> Vec<u8> {
    Sha256::digest(rp_id.as_bytes()).to_vec()
}

/// Registration authData: rpIdHash || flags(UP|UV|AT) || signCount(0) ||
/// attestedCredentialData (AAGUID=0, credIdLen, credId, COSE pubkey).
fn build_registration_auth_data(rp_id: &str, cred_id: &[u8], cose_pubkey: Vec<u8>) -> Vec<u8> {
    let mut out = Vec::with_capacity(37 + 18 + cred_id.len() + cose_pubkey.len());
    out.extend_from_slice(&rp_id_hash(rp_id));
    out.push(FLAG_USER_PRESENT | FLAG_USER_VERIFIED | FLAG_ATTESTED);
    out.extend_from_slice(&0u32.to_be_bytes());
    out.extend_from_slice(&[0u8; 16]); // AAGUID
    out.extend_from_slice(&(cred_id.len() as u16).to_be_bytes());
    out.extend_from_slice(cred_id);
    out.extend_from_slice(&cose_pubkey);
    out
}

/// Assertion authData: rpIdHash || flags(UP|UV) || signCount(counter).
fn build_assertion_auth_data(rp_id: &str, counter: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity(37);
    out.extend_from_slice(&rp_id_hash(rp_id));
    out.push(FLAG_USER_PRESENT | FLAG_USER_VERIFIED);
    out.extend_from_slice(&counter.to_be_bytes());
    out
}
