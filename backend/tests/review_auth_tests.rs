//! W7-15 — signature-gate + DB-integrity tests for `POST /scripts/:id/reviews`.
//!
//! Proves, end-to-end through the REAL handler + TestClient + a REAL in-memory
//! SQLite DB + REAL Ed25519 signatures (no mocked crypto):
//!
//! - unsigned (unknown public key) → 401
//! - valid owner signature → 201
//! - duplicate review (same user, same script) → 409 (the UNIQUE(script_id,
//!   user_id) index + the service's typed conflict mapping)

use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use icp_marketplace_api::{
    auth::create_canonical_payload,
    db::initialize_database,
    handlers::create_review,
    models::AppState,
    rate_limit::SlidingWindowRateLimiter,
    repositories::{AccountRepository, PurchaseRepository},
    services::{AccountService, PasskeyService, PaymentService, ReviewService, ScriptService},
};
use poem::{post, test::TestClient, EndpointExt, Route};
use rand::rngs::OsRng;
use sqlx::sqlite::SqlitePoolOptions;
use std::sync::Arc;

const NOW: &str = "2026-07-14T00:00:00Z";
const REVIEW_CREATE_ACTION: &str = "review:create";

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
        let principal = icp_marketplace_api::auth::derive_ic_principal(&public_key_b64).unwrap();
        Self {
            signing,
            public_key_b64,
            principal,
        }
    }

    fn sign_b64(&self, payload: &serde_json::Value) -> String {
        let canonical = create_canonical_payload(payload);
        let sig = self.signing.sign(canonical.as_bytes());
        base64::engine::general_purpose::STANDARD.encode(sig.to_bytes())
    }
}

async fn setup() -> Arc<AppState> {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("pool");
    initialize_database(&pool).await;

    Arc::new(AppState {
        pool: pool.clone(),
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        passkey_service: PasskeyService::new(pool.clone(), "localhost", "http://localhost:58000")
            .unwrap(),
        purchase_repo: PurchaseRepository::new(pool.clone()),
        payment_service: PaymentService::from_env(pool),
        recovery_rate_limiter: Arc::new(SlidingWindowRateLimiter::new(5, 15 * 60)),
    })
}

/// Seeds an account + binds `key.public_key_b64` to it + inserts a script.
/// Returns the script_id.
async fn seed_account_key_and_script(state: &AppState, key: &RealKey) -> String {
    let repo = AccountRepository::new(state.pool.clone());
    let account_id = "acc-reviewer";
    repo.create_account(icp_marketplace_api::repositories::CreateAccountParams {
        account_id,
        username: "reviewer",
        display_name: "Reviewer",
        contact_email: None,
        contact_telegram: None,
        contact_twitter: None,
        contact_discord: None,
        website_url: None,
        bio: None,
        now: NOW,
    })
    .await
    .unwrap();
    repo.add_public_key(
        "key-reviewer",
        account_id,
        &key.public_key_b64,
        &key.principal,
        NOW,
    )
    .await
    .unwrap();

    let script_id = "script-to-review";
    sqlx::query(
        r#"INSERT INTO scripts (id, slug, title, description, category, bundle, version, price, is_public, downloads, rating, review_count, created_at, updated_at)
           VALUES (?1, 'slug', 'T', 'D', 'c', 'b', '1.0.0', 0.0, 1, 0, 0.0, 0, ?2, ?2)"#,
    )
    .bind(script_id)
    .bind(NOW)
    .execute(&state.pool)
    .await
    .unwrap();
    script_id.to_string()
}

fn ts_now() -> i64 {
    chrono::Utc::now().timestamp()
}

/// Builds a fully-signed review request body for `script_id` / `rating`.
fn signed_review_body(key: &RealKey, script_id: &str, rating: i32, ts: i64, nonce: &str) -> serde_json::Value {
    let account_id = "acc-reviewer";
    let payload = serde_json::json!({
        "action": REVIEW_CREATE_ACTION,
        "script_id": script_id,
        "rating": rating,
        "account_id": account_id,
        "nonce": nonce,
        "ts": ts,
    });
    serde_json::json!({
        "signature": key.sign_b64(&payload),
        "author_public_key": key.public_key_b64,
        "author_principal": key.principal,
        "timestamp": ts,
        "nonce": nonce,
        "rating": rating,
        "comment": "great",
    })
}

#[tokio::test]
async fn review_unsigned_with_unknown_key_is_rejected_401() {
    let state = setup().await;
    let stranger = RealKey::generate(); // NOT bound to any account
    let script_id = seed_account_key_and_script(&state, &stranger).await;

    let app = Route::new()
        .at(
            "/scripts/:id/reviews",
            post(create_review),
        )
        .data(state);
    let client = TestClient::new(app);

    let resp = client
        .post(format!("/scripts/{script_id}/reviews"))
        .body_json(&serde_json::json!({
            "signature": "deadbeef",
            "author_public_key": stranger.public_key_b64,
            "author_principal": stranger.principal,
            "timestamp": ts_now(),
            "nonce": uuid::Uuid::new_v4().to_string(),
            "rating": 5,
            "comment": serde_json::Value::Null,
        }))
        .send()
        .await;
    resp.assert_status(poem::http::StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn review_valid_owner_signature_creates_201_and_duplicate_is_409() {
    let state = setup().await;
    let owner = RealKey::generate();
    let script_id = seed_account_key_and_script(&state, &owner).await;

    let app = Route::new()
        .at("/scripts/:id/reviews", post(create_review))
        .data(state);
    let client = TestClient::new(app);

    // First review → 201.
    let ts = ts_now();
    let resp = client
        .post(format!("/scripts/{script_id}/reviews"))
        .body_json(&signed_review_body(
            &owner,
            &script_id,
            5,
            ts,
            &uuid::Uuid::new_v4().to_string(),
        ))
        .send()
        .await;
    resp.assert_status(poem::http::StatusCode::CREATED);
    let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
    assert_eq!(body["success"], true);

    // Duplicate (same user, same script) → 409.
    let resp = client
        .post(format!("/scripts/{script_id}/reviews"))
        .body_json(&signed_review_body(
            &owner,
            &script_id,
            4,
            ts_now(),
            &uuid::Uuid::new_v4().to_string(),
        ))
        .send()
        .await;
    resp.assert_status(poem::http::StatusCode::CONFLICT);
    let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
    assert_eq!(body["success"], false);
    assert!(
        body["error"].as_str().unwrap().contains("already reviewed"),
        "duplicate error must explain the conflict, got: {}",
        body["error"],
    );
}
