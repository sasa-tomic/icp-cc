use super::{build_download_payload, download_script, icpay_webhook, payment_config};
use crate::auth::create_canonical_payload;
use crate::db;
use crate::handlers::{entitlement_check, get_script};
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

/// The single canonical action name for the signed-entitlement payload.
/// Mirrors `handlers::scripts::ENTITLEMENT_ACTION` — the wire contract both
/// sides must agree on. Kept literal here (not imported) because the backend
/// const is private to its module; if it drifts the entitlement tests will
/// fail loudly at the signature step.
const ENTITLEMENT_ACTION: &str = "entitlement";

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
        let sig = self.signing_key.sign(payload.as_bytes());
        B64.encode(sig.to_bytes())
    }

    /// Signs the canonical-JSON entitlement payload
    /// `{action:"entitlement", id:<script_id>, nonce:<nonce>, ts:<timestamp>}`
    /// and returns the base64 signature. The payload is canonicalised with the
    /// SAME helper the backend uses (`auth::create_canonical_payload`) so the
    /// bytes are identical on both sides.
    fn sign_entitlement(&self, script_id: &str, timestamp: i64, nonce: &str) -> String {
        let payload = serde_json::json!({
            "action": ENTITLEMENT_ACTION,
            "id": script_id,
            "nonce": nonce,
            "ts": timestamp,
        });
        let canonical = create_canonical_payload(&payload);
        let sig = self.signing_key.sign(canonical.as_bytes());
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
        recovery_rate_limiter: std::sync::Arc::new(
            crate::rate_limit::SlidingWindowRateLimiter::new(5, 15 * 60),
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
        .at("/api/v1/scripts/:id/entitlement", post(entitlement_check))
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

/// W7-2 (security, RED-first): the public `GET /scripts/:id` endpoint MUST NOT
/// return the paid bundle even when the caller spoofs the owner's `account_id`
/// (a public identifier leaked by `GET /accounts/:username` and
/// `ScriptDetailResponse.owner_account_id`). The `?account_id=` query branch
/// was an entitlement bypass — it returned the full paid source to anyone. The
/// fix strips `bundle` for every paid-script GET; entitlement is now provable
/// only via the signed `POST /scripts/:id/entitlement` endpoint.
#[tokio::test]
async fn get_script_paid_spoofed_owner_account_id_does_not_leak_bundle() {
    let state = build_state(None, None).await;
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
    .bind("paid-spoof")
    .bind("slug-paid-spoof")
    .bind("owner-acct")
    .bind("Title")
    .bind("desc")
    .bind("utility")
    .bind("PAID SOURCE — must never leak via GET")
    .bind("1.0.0")
    .bind(19.99)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    .unwrap();

    let client = TestClient::new(build_app(state));

    // Spoof the owner's public account_id — the exact exploit from
    // §1 of the Wave-7 plan.
    let resp = client
        .get("/api/v1/scripts/paid-spoof?account_id=owner-acct")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert!(
        json["data"]["bundle"].is_null(),
        "paid bundle MUST be null even when ?account_id=<owner> is spoofed \
         (account_id is a public identifier; entitlement requires a signature)"
    );
    // `purchased` is metadata-safe but now always false for paid scripts via
    // GET — the signed entitlement endpoint is the sole source of truth.
    assert_eq!(json["data"]["purchased"], false);
}

/// W7-2: `GET /scripts/:id` no longer carries entitlement. Even when a
/// purchase record exists, the paid bundle is `null` + `purchased: false`
/// here. The signed `POST /scripts/:id/entitlement` endpoint is the sole
/// source of truth — the entitlement-purchased-owner / entitlement-purchaser
/// tests below prove the purchase row still grants access via that path.
#[tokio::test]
async fn get_script_paid_with_purchase_no_longer_leaks_bundle_via_get() {
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
    // The `?account_id=` query param is now ignored — it was the leak vector.
    let resp = client
        .get("/api/v1/scripts/paid-1?account_id=buyer-1")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert!(
        json["data"]["bundle"].is_null(),
        "GET must never return the paid bundle, even for a known purchaser"
    );
    assert_eq!(
        json["data"]["purchased"], false,
        "GET is no longer an entitlement source; paid scripts are always purchased:false here"
    );
    // Metadata is still present for the Buy CTA.
    assert!(!json["data"]["description"].is_null());
}

#[tokio::test]
async fn get_script_paid_owner_bundle_is_locked_via_get() {
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
    assert!(
        json["data"]["bundle"].is_null(),
        "GET must never return the paid bundle — even to the owner. \
         Use POST /scripts/:id/entitlement (metadata) or /download (bundle)."
    );
    assert_eq!(json["data"]["purchased"], false);
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

/// W7-5 (security): a captured signed download request MUST NOT be replayable.
/// The handler builds the signed payload from `timestamp`+`nonce` and verifies
/// the signature, but pre-fix never called `auth::validate_replay_prevention`
/// — so the same signed request could be submitted repeatedly. This test sends
/// the identical signed request twice and asserts the second is rejected with
/// 401 (replay). Pre-fix both requests returned 200.
#[tokio::test]
async fn download_replay_with_same_nonce_is_rejected() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "free-1", 0.0, "free source").await;
    let identity = TestIdentity::new([7u8; 32], "acct-replay");
    insert_identity(&state.pool, &identity).await;

    let timestamp = chrono::Utc::now().to_rfc3339();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_download("free-1", &timestamp, &nonce);
    let body = serde_json::json!({
        "public_key": identity.public_key_b64,
        "signature": sig,
        "timestamp": timestamp,
        "nonce": nonce,
    });

    let client = TestClient::new(build_app(state));

    // First download succeeds.
    let resp1 = client
        .post("/api/v1/scripts/free-1/download")
        .body_json(&body)
        .send()
        .await;
    resp1.assert_status(StatusCode::OK);

    // Replay the identical signed request — must be rejected (replay).
    let resp2 = client
        .post("/api/v1/scripts/free-1/download")
        .body_json(&body)
        .send()
        .await;
    resp2.assert_status(StatusCode::UNAUTHORIZED);
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
    // W7-6 follow-up: the config endpoint is called by the FRONTEND (public,
    // unauthenticated) to learn whether ICPay is configured. When it is not,
    // the 503 body MUST NOT echo the internal config variable name
    // (`ICPAY_PUBLISHABLE_KEY`) — same leak class W7-6 just closed for the
    // webhook (which is called by an untrusted external ICPay). The detail
    // stays in the server log only.
    let state = build_state(None, Some("whsec_xyz")).await;
    let client = TestClient::new(build_app(state));
    let resp = client.get("/api/v1/payments/icpay/config").send().await;
    resp.assert_status(StatusCode::SERVICE_UNAVAILABLE);
    let json = json_value(resp).await;
    assert_eq!(json["success"], false);
    let err = json["error"].as_str().expect("error must be a string");
    assert!(
        !err.contains("ICPAY_PUBLISHABLE_KEY"),
        "config error must not leak the config var name, got: {err}"
    );
    assert!(
        !err.is_empty(),
        "config error must carry a generic external message"
    );
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
async fn webhook_without_secret_returns_503_and_does_not_leak_config_var() {
    // W7-6: when ICPAY_WEBHOOK_SECRET is unset the webhook is called by an
    // UNTRUSTED external caller (ICPay). It must return 503 (service
    // unavailable — "not configured"), NOT 500, and MUST NOT echo the
    // internal config variable name back to that caller. The detailed reason
    // stays in the server log (tracing::error!) only.
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
    resp.assert_status(StatusCode::SERVICE_UNAVAILABLE);
    let json = json_value(resp).await;
    let err = json["error"].as_str().expect("error must be a string");
    // MUST NOT leak the internal config variable name to an untrusted caller.
    assert!(
        !err.contains("ICPAY_WEBHOOK_SECRET"),
        "webhook error must not leak the config var name, got: {err}"
    );
    assert!(
        !err.is_empty(),
        "webhook error must carry a generic external message"
    );
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

// ========================================================================
// POST /scripts/:id/entitlement (W7-2 — signed entitlement check)
// ========================================================================
//
// Replaces the entitlement bypass closed in `get_script`. The endpoint returns
// ONLY `{purchased, owns}` — metadata that drives the Buy/Download CTA — and
// never the bundle. The caller proves identity with an Ed25519 signature over
// the canonical payload; the server resolves account_id from the verified
// public key (never trusts client input). Mirrors the download endpoint's
// account-resolution + replay-prevention + signature-audit pattern.

/// Builds a valid signed entitlement request body for [identity].
fn entitlement_body(identity: &TestIdentity, script_id: &str) -> serde_json::Value {
    let timestamp = chrono::Utc::now().timestamp();
    let nonce = uuid::Uuid::new_v4().to_string();
    let sig = identity.sign_entitlement(script_id, timestamp, &nonce);
    serde_json::json!({
        "signature": sig,
        "author_public_key": identity.public_key_b64,
        "author_principal": "principal-placeholder",
        "timestamp": timestamp,
        "nonce": nonce,
    })
}

#[tokio::test]
async fn entitlement_unsigned_returns_401() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let identity = TestIdentity::new([1u8; 32], "acct-1");
    insert_identity(&state.pool, &identity).await;

    let client = TestClient::new(build_app(state));
    // No signature, garbage key — must be rejected before any entitlement work.
    let resp = client
        .post("/api/v1/scripts/paid-1/entitlement")
        .body_json(&serde_json::json!({
            "signature": "deadbeef".repeat(16),
            "author_public_key": identity.public_key_b64,
            "author_principal": "principal-placeholder",
            "timestamp": chrono::Utc::now().timestamp(),
            "nonce": uuid::Uuid::new_v4().to_string(),
        }))
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn entitlement_signed_by_owner_returns_purchased_true_owns_true() {
    let state = build_state(None, None).await;
    let owner = TestIdentity::new([42u8; 32], "owner-acct");
    insert_identity(&state.pool, &owner).await;
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
    .bind("owner-acct") // owner_account_id — matches the identity's account
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
        .post("/api/v1/scripts/paid-owned/entitlement")
        .body_json(&entitlement_body(&owner, "paid-owned"))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert_eq!(
        json["data"]["purchased"], true,
        "owner is always entitled — purchased:true, owns:true"
    );
    assert_eq!(json["data"]["owns"], true);
}

#[tokio::test]
async fn entitlement_signed_by_purchaser_returns_purchased_true_owns_false() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let buyer = TestIdentity::new([2u8; 32], "buyer-1");
    insert_identity(&state.pool, &buyer).await;
    // Seed the purchase record that grants entitlement.
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

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/paid-1/entitlement")
        .body_json(&entitlement_body(&buyer, "paid-1"))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["data"]["purchased"], true, "purchaser is entitled");
    assert_eq!(json["data"]["owns"], false, "but is NOT the owner");
}

#[tokio::test]
async fn entitlement_signed_by_random_account_returns_all_false() {
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let rando = TestIdentity::new([3u8; 32], "rando-acct");
    insert_identity(&state.pool, &rando).await;

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/paid-1/entitlement")
        .body_json(&entitlement_body(&rando, "paid-1"))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(
        json["data"]["purchased"], false,
        "no purchase + not owner → not entitled"
    );
    assert_eq!(json["data"]["owns"], false);
}

#[tokio::test]
async fn entitlement_free_script_returns_purchased_true() {
    // A free script is entitled to everyone — purchased:true regardless of
    // caller. (The frontend uses this to render Download for free scripts.)
    let state = build_state(None, None).await;
    insert_script(&state.pool, "free-1", 0.0, "free source").await;
    let caller = TestIdentity::new([4u8; 32], "caller-acct");
    insert_identity(&state.pool, &caller).await;

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/free-1/entitlement")
        .body_json(&entitlement_body(&caller, "free-1"))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["data"]["purchased"], true);
}

#[tokio::test]
async fn entitlement_unknown_public_key_returns_401() {
    // Unregistered key → no account → 401 (cannot establish identity).
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let ghost = TestIdentity::new([5u8; 32], "ghost-acct");
    // Deliberately NOT inserted into account_public_keys.

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/paid-1/entitlement")
        .body_json(&entitlement_body(&ghost, "paid-1"))
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn entitlement_replay_with_same_nonce_is_rejected() {
    // The signed (timestamp, nonce) pair MUST be single-use — a captured
    // entitlement request cannot be replayed. Mirrors the download replay test.
    let state = build_state(None, None).await;
    insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
    let caller = TestIdentity::new([6u8; 32], "replay-acct");
    insert_identity(&state.pool, &caller).await;

    let body = entitlement_body(&caller, "paid-1");
    let client = TestClient::new(build_app(state));

    let resp1 = client
        .post("/api/v1/scripts/paid-1/entitlement")
        .body_json(&body)
        .send()
        .await;
    resp1.assert_status(StatusCode::OK);

    // Replay the identical signed body.
    let resp2 = client
        .post("/api/v1/scripts/paid-1/entitlement")
        .body_json(&body)
        .send()
        .await;
    resp2.assert_status(StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn entitlement_unknown_script_returns_404() {
    let state = build_state(None, None).await;
    let caller = TestIdentity::new([7u8; 32], "acct-7");
    insert_identity(&state.pool, &caller).await;

    let client = TestClient::new(build_app(state));
    let resp = client
        .post("/api/v1/scripts/ghost-script/entitlement")
        .body_json(&entitlement_body(&caller, "ghost-script"))
        .send()
        .await;
    resp.assert_status(StatusCode::NOT_FOUND);
}
