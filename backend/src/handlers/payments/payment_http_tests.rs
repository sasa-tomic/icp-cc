use super::{build_download_payload, download_script, icpay_webhook, payment_config};
use crate::db;
use crate::handlers::get_script;
use crate::models::{self, AppState};
use crate::repositories::PurchaseRepository;
use crate::services::{
    AccountService, PasskeyService, PaymentService, ReviewService, ScriptService,
};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use hmac::{Hmac, Mac};
use poem::http::StatusCode;
use poem::test::TestClient;
use poem::{get, middleware::Cors, post, EndpointExt, Route};
use sha2::Sha256;
use sqlx::sqlite::SqlitePool;
use std::sync::Arc;

type HmacSha256 = Hmac<Sha256>;

/// A real Ed25519 keypair + the public key row inserted into the DB so the
/// download handler can resolve `account_id` from the public key.
struct TestIdentity {
    signing_key: SigningKey,
    public_key_b64: String,
    account_id: String,
}

impl TestIdentity {
    fn new(seed: [u8; 32], account_id: &str) -> Self {
        let signing_key = SigningKey::from_bytes(&seed);
        let public_key_b64 = B64.encode(signing_key.verifying_key().as_bytes());
        Self {
            signing_key,
            public_key_b64,
            account_id: account_id.to_string(),
        }
    }

    /// Signs the canonical `download:{script_id}:{timestamp}:{nonce}` payload
    /// and returns the base64 signature.
    fn sign_download(&self, script_id: &str, timestamp: &str, nonce: &str) -> String {
        let payload = build_download_payload(script_id, timestamp, nonce);
        let sig = self.signing_key.sign(&payload);
        B64.encode(sig.to_bytes())
    }
}

async fn insert_identity(pool: &SqlitePool, identity: &TestIdentity) {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        r#"INSERT INTO accounts (id, username, display_name, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)"#,
    )
    .bind(&identity.account_id)
    .bind(identity.account_id.to_lowercase())
    .bind(format!("Display {}", identity.account_id))
    .bind(&now)
    .bind(&now)
    .execute(pool)
    .await
    .unwrap();

    sqlx::query(
        r#"INSERT INTO account_public_keys
           (id, account_id, public_key, ic_principal, is_active, added_at)
           VALUES (?, ?, ?, ?, 1, ?)"#,
    )
    .bind(uuid::Uuid::new_v4().to_string())
    .bind(&identity.account_id)
    .bind(&identity.public_key_b64)
    .bind("principal-placeholder")
    .bind(&now)
    .execute(pool)
    .await
    .unwrap();
}

/// Inserts a script with an explicit price; returns its id.
async fn insert_script(pool: &SqlitePool, id: &str, price: f64, bundle: &str) {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        r#"INSERT INTO scripts (
            id, slug, owner_account_id, title, description, category, tags,
            bundle, author_principal, author_public_key, upload_signature,
            canister_ids, icon_url, screenshots, version, compatibility,
            price, is_public, downloads, rating, review_count,
            created_at, updated_at, deleted_at
        ) VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 1, 0, 0.0, 0, ?, ?, NULL)"#,
    )
    .bind(id)
    .bind(format!("slug-{id}"))
    .bind(format!("Title {id}"))
    .bind("description")
    .bind("utility")
    .bind(bundle)
    .bind("1.0.0")
    .bind(price)
    .bind(&now)
    .bind(&now)
    .execute(pool)
    .await
    .unwrap();
}

/// Builds a test `AppState` over an in-memory SQLite DB. Optionally seeds
/// a known ICPay config so webhook/config tests can drive the happy path.
async fn build_state(publishable_key: Option<&str>, webhook_secret: Option<&str>) -> Arc<AppState> {
    let pool = sqlx::sqlite::SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .unwrap();
    db::initialize_database(&pool).await;

    let passkey_service = PasskeyService::new(pool.clone(), "localhost", "http://localhost:58000")
        .expect("Failed to create PasskeyService");

    Arc::new(AppState {
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        passkey_service,
        purchase_repo: PurchaseRepository::new(pool.clone()),
        payment_service: PaymentService::with_config(
            publishable_key.map(str::to_string),
            None,
            webhook_secret.map(str::to_string),
            pool.clone(),
        ),
        pool,
    })
}

/// Builds a `Route` wired with just the payment-related endpoints, sharing
/// `state` via `.data(...)`.
fn build_app(state: Arc<AppState>) -> impl poem::Endpoint {
    Route::new()
        .at("/api/v1/scripts/:id", get(get_script))
        .at("/api/v1/scripts/:id/download", post(download_script))
        .at("/api/v1/payments/icpay/config", get(payment_config))
        .at("/api/v1/payments/icpay/webhook", post(icpay_webhook))
        .with(Cors::new())
        .data(state)
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

fn sign_webhook(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(body);
    hex_encode(&mac.finalize().into_bytes())
}

/// Extracts the response body as a `serde_json::Value` for assertion.
/// (`TestJson`'s inner field is private; `deserialize` is the public seam.)
async fn json_value(resp: poem::test::TestResponse) -> serde_json::Value {
    resp.json().await.value().deserialize::<serde_json::Value>()
}

// ========================================================================
// get_script entitlement gate
// ========================================================================

#[tokio::test]
async fn get_script_free_returns_bundle_and_purchased_true() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "free-1", 0.0, "print('free source')").await;
    let app = build_app(state);
    let client = TestClient::new(app);

    let resp = client.get("/api/v1/scripts/free-1").send().await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert_eq!(json["data"]["bundle"], "print('free source')");
    assert_eq!(json["data"]["purchased"], true);
    assert_eq!(json["data"]["price"], 0.0);
}

#[tokio::test]
async fn get_script_paid_no_account_hides_bundle() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "print('paid source')").await;
    let client = TestClient::new(build_app(state));

    let resp = client.get("/api/v1/scripts/paid-1").send().await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert!(
        json["data"]["bundle"].is_null(),
        "paid bundle MUST be null when no account_id is provided"
    );
    assert_eq!(json["data"]["purchased"], false);
    assert_eq!(json["data"]["price"], 9.99);
    assert!(
        !json["data"]["description"].is_null(),
        "metadata (description, price) must still be present for the Buy CTA"
    );
}

#[tokio::test]
async fn get_script_paid_account_without_purchase_hides_bundle() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "print('paid source')").await;
    let client = TestClient::new(build_app(state.clone()));

    let resp = client
        .get("/api/v1/scripts/paid-1?account_id=someone-else")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert!(
        json["data"]["bundle"].is_null(),
        "paid bundle MUST be null without a purchase record"
    );
    assert_eq!(json["data"]["purchased"], false);
}

#[tokio::test]
async fn get_script_paid_account_with_purchase_returns_bundle() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "print('paid source')").await;
    // Seed a purchase record.
    let now = chrono::Utc::now().to_rfc3339();
    state
        .purchase_repo
        .create_or_ignore(&models::NewPurchase {
            id: uuid::Uuid::new_v4().to_string(),
            account_id: "buyer-1".to_string(),
            script_id: "paid-1".to_string(),
            icpay_intent_id: Some("intent-1".to_string()),
            icpay_transaction_id: Some("tx-1".to_string()),
            usd_amount: 9.99,
            currency: "USD".to_string(),
            status: "completed".to_string(),
            paid_at: now.clone(),
            created_at: now,
        })
        .await
        .unwrap();

    let client = TestClient::new(build_app(state));
    let resp = client
        .get("/api/v1/scripts/paid-1?account_id=buyer-1")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(
        json["data"]["bundle"], "print('paid source')",
        "paid bundle MUST be present once a purchase record exists"
    );
    assert_eq!(json["data"]["purchased"], true);
}

#[tokio::test]
async fn get_script_paid_owner_is_entitled_without_purchase() {
    let state = build_state(None, None).await;
    // Seed an account + a script it owns.
    let identity = TestIdentity::new([42u8; 32], "owner-acct");
    insert_identity(&state.pool, &identity).await;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        r#"INSERT INTO scripts (
            id, slug, owner_account_id, title, description, category, tags,
            bundle, author_principal, author_public_key, upload_signature,
            canister_ids, icon_url, screenshots, version, compatibility,
            price, is_public, downloads, rating, review_count,
            created_at, updated_at, deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 1, 0, 0.0, 0, ?, ?, NULL)"#,
    )
    .bind("paid-owned")
    .bind("slug-paid-owned")
    .bind("owner-acct") // owner_account_id
    .bind("Title")
    .bind("desc")
    .bind("utility")
    .bind("owner source")
    .bind("1.0.0")
    .bind(19.99)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .unwrap();

    let client = TestClient::new(build_app(state));
    let resp = client
        .get("/api/v1/scripts/paid-owned?account_id=owner-acct")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(
        json["data"]["bundle"], "owner source",
        "script owner is always entitled, even without a purchase row"
    );
    assert_eq!(json["data"]["purchased"], true);
}

#[tokio::test]
async fn get_script_unknown_id_returns_404() {
    let state = build_state(None, None).await;
    let client = TestClient::new(build_app(state));
    let resp = client.get("/api/v1/scripts/does-not-exist").send().await;
    resp.assert_status(StatusCode::NOT_FOUND);
}

// ========================================================================
// POST /scripts/:id/download
// ========================================================================

#[tokio::test]
async fn download_free_script_returns_bundle() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "free-1", 0.0, "free source").await;
    let identity = TestIdentity::new([1u8; 32], "acct-1");
    insert_identity(&state.pool, &identity).await;

    let timestamp = chrono::Utc::now().to_rfc3339();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_download("free-1", &timestamp, &nonce);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/free-1/download")
        .body_json(&serde_json::json!({
            "public_key": identity.public_key_b64,
            "signature": sig,
            "timestamp": timestamp,
            "nonce": nonce,
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert_eq!(json["data"]["bundle"], "free source");
    assert_eq!(json["data"]["purchased"], true);
}

#[tokio::test]
async fn download_paid_with_purchase_returns_bundle() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let identity = TestIdentity::new([2u8; 32], "buyer-1");
    insert_identity(&state.pool, &identity).await;
    // Seed the entitlement.
    let now = chrono::Utc::now().to_rfc3339();
    state
        .purchase_repo
        .create_or_ignore(&models::NewPurchase {
            id: uuid::Uuid::new_v4().to_string(),
            account_id: "buyer-1".to_string(),
            script_id: "paid-1".to_string(),
            icpay_intent_id: None,
            icpay_transaction_id: None,
            usd_amount: 9.99,
            currency: "USD".to_string(),
            status: "completed".to_string(),
            paid_at: now.clone(),
            created_at: now,
        })
        .await
        .unwrap();

    let timestamp = chrono::Utc::now().to_rfc3339();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_download("paid-1", &timestamp, &nonce);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/paid-1/download")
        .body_json(&serde_json::json!({
            "public_key": identity.public_key_b64,
            "signature": sig,
            "timestamp": timestamp,
            "nonce": nonce,
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["data"]["bundle"], "paid source");
    assert_eq!(json["data"]["purchased"], true);
}

#[tokio::test]
async fn download_paid_without_purchase_returns_402() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let identity = TestIdentity::new([3u8; 32], "freeloader");
    insert_identity(&state.pool, &identity).await;

    let timestamp = chrono::Utc::now().to_rfc3339();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_download("paid-1", &timestamp, &nonce);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/paid-1/download")
        .body_json(&serde_json::json!({
            "public_key": identity.public_key_b64,
            "signature": sig,
            "timestamp": timestamp,
            "nonce": nonce,
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::PAYMENT_REQUIRED);
    let json = json_value(resp).await;
    assert_eq!(json["success"], false);
    assert_eq!(json["error"], "Purchase required");
    assert_eq!(json["data"]["price"], 9.99);
}

#[tokio::test]
async fn download_with_bad_signature_returns_401() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "free-1", 0.0, "free").await;
    let identity = TestIdentity::new([4u8; 32], "acct-4");
    insert_identity(&state.pool, &identity).await;

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/free-1/download")
        .body_json(&serde_json::json!({
            "public_key": identity.public_key_b64,
            "signature": "0000000000000000000000000000000000000000000000000000000000000000",
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "nonce": uuid::Uuid::new_v4().to_string(),
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
    let json = json_value(resp).await;
    assert_eq!(json["error"], "Invalid signature");
}

#[tokio::test]
async fn download_with_unknown_public_key_returns_401() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "free-1", 0.0, "free").await;
    // No account_public_keys row for this key.
    let identity = TestIdentity::new([5u8; 32], "ghost");

    let timestamp = chrono::Utc::now().to_rfc3339();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_download("free-1", &timestamp, &nonce);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/free-1/download")
        .body_json(&serde_json::json!({
            "public_key": identity.public_key_b64,
            "signature": sig,
            "timestamp": timestamp,
            "nonce": nonce,
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
    let json = json_value(resp).await;
    assert_eq!(json["error"], "Unknown public key");
}

#[tokio::test]
async fn download_unknown_script_returns_404() {
    let state = build_state(None, None).await;
    let identity = TestIdentity::new([6u8; 32], "acct-6");
    insert_identity(&state.pool, &identity).await;

    let timestamp = chrono::Utc::now().to_rfc3339();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_download("ghost-script", &timestamp, &nonce);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/ghost-script/download")
        .body_json(&serde_json::json!({
            "public_key": identity.public_key_b64,
            "signature": sig,
            "timestamp": timestamp,
            "nonce": nonce,
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::NOT_FOUND);
}

// ========================================================================
// GET /payments/icpay/config
// ========================================================================

#[tokio::test]
async fn config_with_publishable_key_returns_200() {
    let state = build_state(Some("pk_test_abc"), Some("whsec_xyz")).await;
    let client = TestClient::new(build_app(state));
    let resp = client.get("/api/v1/payments/icpay/config").send().await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert_eq!(json["data"]["publishableKey"], "pk_test_abc");
    assert_eq!(json["data"]["shortcode"], "ic_icp");
    assert_eq!(json["data"]["apiUrl"], "https://api.icpay.org");
}

#[tokio::test]
async fn config_without_publishable_key_returns_503() {
    let state = build_state(None, Some("whsec_xyz")).await;
    let client = TestClient::new(build_app(state));
    let resp = client.get("/api/v1/payments/icpay/config").send().await;
    resp.assert_status(StatusCode::SERVICE_UNAVAILABLE);
    let json = json_value(resp).await;
    assert_eq!(json["success"], false);
    assert_eq!(json["error"], "ICPAY_PUBLISHABLE_KEY not configured");
}

// ========================================================================
// POST /payments/icpay/webhook
// ========================================================================

fn completed_webhook_body(account: &str, script: &str) -> Vec<u8> {
    serde_json::json!({
        "id": "icpay-tx-1",
        "status": "completed",
        "usdAmount": 9.99,
        "metadata": {
            "accountId": account,
            "scriptId": script,
            "intentId": "intent-1"
        }
    })
    .to_string()
    .into_bytes()
}

#[tokio::test]
async fn webhook_with_valid_hmac_records_purchase_and_returns_200() {
    let state = build_state(Some("pk"), Some("whsec_demo")).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let body = completed_webhook_body("buyer-1", "paid-1");
    let sig = sign_webhook("whsec_demo", &body);

    let client = TestClient::new(build_app(state.clone()));
    let resp = client
        .post("/api/v1/payments/icpay/webhook")
        .header("X-Icpay-Signature", &sig)
        .body(body)
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert_eq!(json["data"]["recorded"], true);

    // Entitlement now exists.
    assert!(
        state
            .purchase_repo
            .exists_for_account_and_script("buyer-1", "paid-1")
            .await
            .unwrap(),
        "purchase must be persisted after a valid webhook"
    );
}

#[tokio::test]
async fn webhook_redelivery_is_idempotent() {
    let state = build_state(Some("pk"), Some("whsec_demo")).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let body = completed_webhook_body("buyer-1", "paid-1");
    let sig = sign_webhook("whsec_demo", &body);

    let client = TestClient::new(build_app(state.clone()));
    let resp1 = client
        .post("/api/v1/payments/icpay/webhook")
        .header("X-Icpay-Signature", &sig)
        .body(body.clone())
        .send()
        .await;
    let json1 = json_value(resp1).await;
    assert_eq!(json1["data"]["recorded"], true, "first delivery inserts");

    let resp2 = client
        .post("/api/v1/payments/icpay/webhook")
        .header("X-Icpay-Signature", &sig)
        .body(body)
        .send()
        .await;
    resp2.assert_status(StatusCode::OK);
    let json2 = json_value(resp2).await;
    assert_eq!(
        json2["data"]["recorded"], false,
        "redelivery must be a no-op (recorded=false, no duplicate row)"
    );
}

#[tokio::test]
async fn webhook_with_bad_hmac_returns_401() {
    let state = build_state(Some("pk"), Some("whsec_demo")).await;
    let body = completed_webhook_body("buyer-1", "paid-1");

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/payments/icpay/webhook")
        .header("X-Icpay-Signature", "deadbeef".repeat(8))
        .body(body)
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
    let json = json_value(resp).await;
    assert!(
        json["error"].as_str().unwrap().contains("signature"),
        "got: {json}"
    );
}

#[tokio::test]
async fn webhook_without_secret_returns_500() {
    // No webhook secret configured.
    let state = build_state(Some("pk"), None).await;
    let body = completed_webhook_body("buyer-1", "paid-1");
    let sig = sign_webhook("whsec_demo", &body);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/payments/icpay/webhook")
        .header("X-Icpay-Signature", &sig)
        .body(body)
        .send()
        .await;
    resp.assert_status(StatusCode::INTERNAL_SERVER_ERROR);
    let json = json_value(resp).await;
    assert_eq!(json["error"], "ICPAY_WEBHOOK_SECRET not configured");
}

#[tokio::test]
async fn webhook_missing_signature_header_returns_401() {
    let state = build_state(Some("pk"), Some("whsec_demo")).await;
    let body = completed_webhook_body("buyer-1", "paid-1");

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/payments/icpay/webhook")
        .body(body)
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn webhook_accepts_icmpay_signature_header_spelling() {
    // Resilience: accept both X-Icpay-Signature and Icmpay-Signature.
    let state = build_state(Some("pk"), Some("whsec_demo")).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let body = completed_webhook_body("buyer-2", "paid-1");
    let sig = sign_webhook("whsec_demo", &body);

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/payments/icpay/webhook")
        .header("Icmpay-Signature", &sig)
        .body(body)
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["data"]["recorded"], true);
}
