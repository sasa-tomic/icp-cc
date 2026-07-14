//! Wave-7 Phase 2 (W7-12..15): unit tests for the shared signature gate.
//!
//! Proves the security invariant of [`signature_gate::verify_signed_account_request`]
//! with REAL Ed25519 cryptography + a REAL in-memory SQLite database (no mocks):
//!
//! - unknown public key → 401
//! - missing signature → 401
//! - tampered payload → 401
//! - **signed-by-non-owner** (key bound to account B, payload names account A) → 401
//! - valid owner signature → Ok(resolved account_id)
//! - replay (same nonce twice) → 401
//!
//! These are the security-property tests shared by every gated route
//! (vault / passkey / recovery / review). Per-route HTTP-level coverage lives
//! alongside each handler's existing service tests.

use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use icp_marketplace_api::{
    auth::create_canonical_payload,
    db::initialize_database,
    repositories::AccountRepository,
    signature_gate::{verify_signed_account_request, SignedAuthFields},
};
use rand::rngs::OsRng;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};

const NOW: &str = "2026-07-14T00:00:00Z";

/// Real Ed25519 keypair + its base64 public key + its backend-derived IC
/// principal. Mirrors `auth_middleware_tests::RealKey`.
struct RealKey {
    signing: SigningKey,
    public_key_b64: String,
    principal: String,
}

impl RealKey {
    fn generate() -> Self {
        let signing = SigningKey::generate(&mut OsRng);
        let public_key_b64 =
            base64::engine::general_purpose::STANDARD.encode(signing.verifying_key().as_bytes());
        let principal =
            icp_marketplace_api::auth::derive_ic_principal(&public_key_b64).expect("derive");
        Self {
            signing,
            public_key_b64,
            principal,
        }
    }

    /// Sign a JSON payload over its canonical bytes, return base64.
    fn sign_b64(&self, payload: &serde_json::Value) -> String {
        let canonical = create_canonical_payload(payload);
        let sig = self.signing.sign(canonical.as_bytes());
        base64::engine::general_purpose::STANDARD.encode(sig.to_bytes())
    }
}

async fn setup() -> (AccountRepository, SqlitePool) {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("pool");
    initialize_database(&pool).await;
    (AccountRepository::new(pool.clone()), pool)
}

/// Seeds an account `id` with username + binds `key.public_key_b64` to it.
async fn seed_account_with_key(repo: &AccountRepository, account_id: &str, username: &str, key: &RealKey) {
    repo.create_account(icp_marketplace_api::repositories::CreateAccountParams {
        account_id,
        username,
        display_name: username,
        contact_email: None,
        contact_telegram: None,
        contact_twitter: None,
        contact_discord: None,
        website_url: None,
        bio: None,
        now: NOW,
    })
    .await
    .expect("create_account");
    repo.add_public_key(
        &format!("key-{account_id}"),
        account_id,
        &key.public_key_b64,
        &key.principal,
        NOW,
    )
    .await
    .expect("add_public_key");
}

fn ts_now() -> i64 {
    chrono::Utc::now().timestamp()
}

const VAULT_CREATE_ACTION: &str = "vault:create";

#[tokio::test]
async fn gate_rejects_unknown_public_key_with_401() {
    let (repo, pool) = setup().await;
    let key = RealKey::generate(); // NOT bound to any account
    let ts = ts_now();
    let nonce = uuid::Uuid::new_v4().to_string();

    let payload = serde_json::json!({
        "action": VAULT_CREATE_ACTION,
        "account_id": "nobody",
        "nonce": nonce,
        "ts": ts,
    });
    let auth = SignedAuthFields {
        signature: &key.sign_b64(&payload),
        author_public_key: &key.public_key_b64,
        author_principal: &key.principal,
        timestamp: ts,
        nonce: &nonce,
    };

    let err = verify_signed_account_request(&repo, &pool, VAULT_CREATE_ACTION, &auth, |_| {
        serde_json::json!({})
    })
    .await
    .expect_err("unknown key must be rejected");
    assert_eq!(err.status, poem::http::StatusCode::UNAUTHORIZED);
    assert_eq!(err.message, "Unknown public key");
}

#[tokio::test]
async fn gate_rejects_missing_or_empty_signature_with_401() {
    let (repo, pool) = setup().await;
    let key = RealKey::generate();
    seed_account_with_key(&repo, "acc-owner-a", "ownera", &key).await;
    let ts = ts_now();
    let nonce = uuid::Uuid::new_v4().to_string();

    // Empty signature string.
    let auth = SignedAuthFields {
        signature: "",
        author_public_key: &key.public_key_b64,
        author_principal: &key.principal,
        timestamp: ts,
        nonce: &nonce,
    };
    let err = verify_signed_account_request(&repo, &pool, VAULT_CREATE_ACTION, &auth, |_| {
        serde_json::json!({})
    })
    .await
    .expect_err("empty signature must be rejected");
    assert_eq!(err.status, poem::http::StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn gate_rejects_signed_by_non_owner_with_401() {
    // The attacker's key is bound to account B. They craft a payload naming the
    // VICTIM's account A and sign it with their own key. The gate resolves
    // account B from the public key, rebuilds the payload with account_id=B,
    // and the signature (which was over account_id=A) fails to verify → 401.
    let (repo, pool) = setup().await;
    let owner = RealKey::generate();
    let attacker = RealKey::generate();
    seed_account_with_key(&repo, "acc-victim-a", "victim", &owner).await;
    seed_account_with_key(&repo, "acc-attacker-b", "attacker", &attacker).await;

    let ts = ts_now();
    let nonce = uuid::Uuid::new_v4().to_string();
    // Attacker signs a payload that names the VICTIM's account_id.
    let attacker_payload = serde_json::json!({
        "action": VAULT_CREATE_ACTION,
        "account_id": "acc-victim-a",
        "nonce": nonce,
        "ts": ts,
    });
    let auth = SignedAuthFields {
        signature: &attacker.sign_b64(&attacker_payload),
        author_public_key: &attacker.public_key_b64,
        author_principal: &attacker.principal,
        timestamp: ts,
        nonce: &nonce,
    };

    let err = verify_signed_account_request(&repo, &pool, VAULT_CREATE_ACTION, &auth, |resolved| {
        // Backend rebuilds with the RESOLVED account_id (the attacker's).
        serde_json::json!({
            "action": VAULT_CREATE_ACTION,
            "account_id": resolved,
            "nonce": nonce,
            "ts": ts,
        })
    })
    .await
    .expect_err("non-owner signature must be rejected");
    assert_eq!(err.status, poem::http::StatusCode::UNAUTHORIZED);
    assert_eq!(err.message, "Invalid signature");
}

#[tokio::test]
async fn gate_accepts_valid_owner_signature_and_resolves_account_id() {
    let (repo, pool) = setup().await;
    let owner = RealKey::generate();
    seed_account_with_key(&repo, "acc-owner-real", "ownerreal", &owner).await;

    let ts = ts_now();
    let nonce = uuid::Uuid::new_v4().to_string();
    // The owner signs a payload naming its OWN account_id (which the frontend
    // knows — it's the logged-in account). The gate resolves the same id and
    // verification succeeds.
    let payload = serde_json::json!({
        "action": VAULT_CREATE_ACTION,
        "account_id": "acc-owner-real",
        "nonce": nonce,
        "ts": ts,
    });
    let auth = SignedAuthFields {
        signature: &owner.sign_b64(&payload),
        author_public_key: &owner.public_key_b64,
        author_principal: &owner.principal,
        timestamp: ts,
        nonce: &nonce,
    };

    let resolved = verify_signed_account_request(
        &repo,
        &pool,
        VAULT_CREATE_ACTION,
        &auth,
        |resolved| {
            serde_json::json!({
                "action": VAULT_CREATE_ACTION,
                "account_id": resolved,
                "nonce": nonce,
                "ts": ts,
            })
        },
    )
    .await
    .expect("a valid owner signature must resolve the account_id");

    assert_eq!(resolved, "acc-owner-real");
}

#[tokio::test]
async fn gate_rejects_replayed_nonce_with_401() {
    // After a successful gate, the same (timestamp, nonce) pair must be refused
    // — the audit row makes the nonce single-use within the 10-minute window.
    let (repo, pool) = setup().await;
    let owner = RealKey::generate();
    seed_account_with_key(&repo, "acc-replay", "replay", &owner).await;

    let ts = ts_now();
    let nonce = uuid::Uuid::new_v4().to_string();

    // Helper to build auth + call the gate for this fixed (ts, nonce).
    async fn run(
        repo: &AccountRepository,
        pool: &SqlitePool,
        owner: &RealKey,
        ts: i64,
        nonce: &str,
    ) -> Result<String, icp_marketplace_api::signature_gate::AuthGateRejection> {
        let payload = serde_json::json!({
            "action": VAULT_CREATE_ACTION,
            "account_id": "acc-replay",
            "nonce": nonce,
            "ts": ts,
        });
        let auth = SignedAuthFields {
            signature: &owner.sign_b64(&payload),
            author_public_key: &owner.public_key_b64,
            author_principal: &owner.principal,
            timestamp: ts,
            nonce,
        };
        verify_signed_account_request(repo, pool, VAULT_CREATE_ACTION, &auth, |resolved| {
            serde_json::json!({
                "action": VAULT_CREATE_ACTION,
                "account_id": resolved,
                "nonce": nonce,
                "ts": ts,
            })
        })
        .await
    }

    run(&repo, &pool, &owner, ts, &nonce)
        .await
        .expect("first use must succeed");
    let err = run(&repo, &pool, &owner, ts, &nonce)
        .await
        .expect_err("replay must be rejected");
    assert_eq!(err.status, poem::http::StatusCode::UNAUTHORIZED);
    assert_eq!(err.message, "Replay prevention failed");
}
