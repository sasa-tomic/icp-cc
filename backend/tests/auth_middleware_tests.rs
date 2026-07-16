//! W6-13 (TQ-W6-2d): coverage for the auth middleware.
//!
//! Two security-critical surfaces, both previously at 0 tests:
//!
//! 1. `verify_request_auth` — the gate every signed mutation passes through.
//!    Tested with REAL Ed25519 signatures (real keypair via `ed25519-dalek`,
//!    a backend dependency). A request with no signature, no principal, or a
//!    bad signature must be rejected with a 401 whose JSON body carries the
//!    specific reason; a correctly-signed payload passes.
//!
//! 2. `AdminAuth` middleware (the bearer-token guard on admin routes). Driven
//!    through poem's `TestClient` against a real `Route` so the full header
//!    parse + status path is exercised: missing header, bad format, wrong
//!    token, and a valid token that passes through to the handler.

use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use icp_marketplace_api::auth::{create_canonical_payload, derive_ic_principal};
use icp_marketplace_api::middleware::{verify_request_auth, AdminAuth, AuthenticatedRequest};
use poem::{
    get, handler, http::StatusCode, test::TestClient, web::Json, EndpointExt, IntoResponse, Route,
};
use rand::rngs::OsRng;

// ============================================================================
// Test AuthenticatedRequest impl
// ============================================================================

/// A minimal request carrying the three auth fields, so the middleware tests
/// don't depend on the full CreateScriptRequest shape.
#[derive(Default)]
struct TestAuthedRequest {
    signature: Option<String>,
    author_principal: Option<String>,
    author_public_key: Option<String>,
}

impl AuthenticatedRequest for TestAuthedRequest {
    fn signature(&self) -> Option<&str> {
        self.signature.as_deref()
    }
    fn author_principal(&self) -> Option<&str> {
        self.author_principal.as_deref()
    }
    fn author_public_key(&self) -> Option<&str> {
        self.author_public_key.as_deref()
    }
}

/// Real Ed25519 keypair + its base64-encoded public key + its IC principal
/// (derived the same way the backend derives it, so the pairing is realistic).
struct RealKey {
    signing: SigningKey,
    public_key_b64: String,
    principal: String,
}

impl RealKey {
    fn generate() -> Self {
        let signing = SigningKey::generate(&mut OsRng);
        let verifying = signing.verifying_key();
        let public_key_b64 = base64::engine::general_purpose::STANDARD.encode(verifying.to_bytes());
        let principal = derive_ic_principal(&public_key_b64)
            .expect("principal derivation must succeed for a real key");
        Self {
            signing,
            public_key_b64,
            principal,
        }
    }

    /// Sign a payload with the REAL Ed25519 key, return base64.
    fn sign_b64(&self, payload: &serde_json::Value) -> String {
        let canonical = create_canonical_payload(payload);
        let sig = self.signing.sign(canonical.as_bytes());
        base64::engine::general_purpose::STANDARD.encode(sig.to_bytes())
    }

    fn req_with_sig(&self, signature: Option<String>) -> TestAuthedRequest {
        TestAuthedRequest {
            signature,
            author_principal: Some(self.principal.clone()),
            author_public_key: Some(self.public_key_b64.clone()),
        }
    }
}

fn sample_payload() -> serde_json::Value {
    serde_json::json!({
        "action": "upload",
        "title": "t",
        "bundle": "b",
        "author_principal": "p",
    })
}

/// Extract the JSON body of a `Box<Response>` after asserting its status.
async fn body_of(resp: poem::Response) -> serde_json::Value {
    resp.into_body()
        .into_json::<serde_json::Value>()
        .await
        .expect("body must be JSON")
}

// ----------------------------------------------------------------------------
// verify_request_auth: positive + negative (specific status + message)
// ----------------------------------------------------------------------------

#[tokio::test]
async fn verify_auth_rejects_missing_signature_with_401() {
    let key = RealKey::generate();
    let req = TestAuthedRequest {
        signature: None, // missing
        author_principal: Some(key.principal.clone()),
        author_public_key: Some(key.public_key_b64.clone()),
    };

    let err = verify_request_auth(&req, "Test op", || Ok(sample_payload()))
        .expect_err("missing signature must be rejected");
    let resp = *err;
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    let body = body_of(resp).await;
    assert_eq!(body["success"], false, "success flag must be false");
    assert!(
        body["error"].as_str().unwrap().contains("signature"),
        "error must mention signature, got: {}",
        body["error"],
    );
}

#[tokio::test]
async fn verify_auth_rejects_missing_principal_with_401() {
    let req = TestAuthedRequest {
        signature: Some("somesig".into()),
        author_principal: None, // missing
        author_public_key: Some("k".into()),
    };

    let err = verify_request_auth(&req, "Test op", || Ok(sample_payload()))
        .expect_err("missing principal must be rejected");
    let resp = *err;
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    let body = body_of(resp).await;
    assert!(
        body["error"].as_str().unwrap().contains("author_principal"),
        "error must mention author_principal, got: {}",
        body["error"],
    );
}

#[tokio::test]
async fn verify_auth_accepts_real_ed25519_signature() {
    let key = RealKey::generate();
    let payload = sample_payload();
    let sig = key.sign_b64(&payload);
    let req = key.req_with_sig(Some(sig));

    // Real signature over the canonical payload must pass the real verifier.
    verify_request_auth(&req, "Test op", || Ok(payload.clone()))
        .expect("a valid real Ed25519 signature must pass verification");
}

#[tokio::test]
async fn verify_auth_rejects_tampered_payload_with_401() {
    let key = RealKey::generate();
    let payload = sample_payload();
    let sig = key.sign_b64(&payload); // signs the original payload
    let req = key.req_with_sig(Some(sig));

    // Present the signed signature, but build a DIFFERENT payload — the real
    // verifier must detect the mismatch (the signature won't verify).
    let tampered = serde_json::json!({
        "action": "upload",
        "title": "TAMPERED", // changed after signing
        "bundle": "b",
        "author_principal": "p",
    });

    let err = verify_request_auth(&req, "Test op", || Ok(tampered))
        .expect_err("tampered payload must be rejected");
    let resp = *err;
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    let body = body_of(resp).await;
    assert!(
        body["error"].as_str().unwrap().contains("Ed25519"),
        "rejection must come from real Ed25519 verification, got: {}",
        body["error"],
    );
}

#[tokio::test]
async fn verify_auth_rejects_signature_from_a_different_key() {
    // Sign with key A, present key B's public key/principal — real crypto
    // rejects (this is the impersonation guard).
    let signer = RealKey::generate();
    let claimed = RealKey::generate();
    assert_ne!(
        signer.public_key_b64, claimed.public_key_b64,
        "the two keys must be distinct",
    );

    let payload = sample_payload();
    let sig = signer.sign_b64(&payload); // signed by `signer`
    let req = TestAuthedRequest {
        signature: Some(sig),
        author_principal: Some(claimed.principal.clone()), // claiming `claimed`'s identity
        author_public_key: Some(claimed.public_key_b64.clone()),
    };

    let err = verify_request_auth(&req, "Test op", || Ok(payload.clone()))
        .expect_err("signature from the wrong key must be rejected");
    let resp = *err;
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn verify_auth_rejects_empty_signature_with_401() {
    // The structural-invalid guard: an empty signature string is rejected
    // before any crypto (it can never be a real signature).
    let key = RealKey::generate();
    let req = key.req_with_sig(Some(String::new()));

    let err = verify_request_auth(&req, "Test op", || Ok(sample_payload()))
        .expect_err("empty signature must be rejected");
    let resp = *err;
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    let body = body_of(resp).await;
    assert!(
        body["error"]
            .as_str()
            .unwrap()
            .to_lowercase()
            .contains("empty"),
        "must explain the empty-signature rejection, got: {}",
        body["error"],
    );
}

// ============================================================================
// AdminAuth middleware (bearer-token guard)
// ============================================================================

/// A guard that sets `ADMIN_TOKEN` for the duration of a test and restores the
/// prior value (or removes it) on drop, so tests don't bleed env state.
struct AdminTokenGuard {
    prior: Option<String>,
}

impl AdminTokenGuard {
    fn set(token: &str) -> Self {
        let prior = std::env::var("ADMIN_TOKEN").ok();
        // SAFETY: env mutation is process-global; these tests run serially
        // within the file and nextest isolates test binaries. The middleware
        // reads ADMIN_TOKEN at request time only.
        unsafe { std::env::set_var("ADMIN_TOKEN", token) };
        Self { prior }
    }

    fn unset() -> Self {
        let prior = std::env::var("ADMIN_TOKEN").ok();
        unsafe { std::env::remove_var("ADMIN_TOKEN") };
        Self { prior }
    }
}

impl Drop for AdminTokenGuard {
    fn drop(&mut self) {
        match self.prior.take() {
            Some(v) => unsafe { std::env::set_var("ADMIN_TOKEN", v) },
            None => unsafe { std::env::remove_var("ADMIN_TOKEN") },
        }
    }
}

#[handler]
async fn admin_only() -> impl IntoResponse {
    Json(serde_json::json!({ "ok": true }))
}

fn guarded_app() -> Route {
    Route::new().at("/admin/thing", get(admin_only).with(AdminAuth))
}

#[tokio::test]
async fn admin_auth_rejects_missing_authorization_header() {
    let _guard = AdminTokenGuard::set("real-admin-secret");
    let client = TestClient::new(guarded_app());

    let resp = client.get("/admin/thing").send().await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
    let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
    assert_eq!(body["success"], false);
    assert_eq!(
        body["error"], "Admin authentication required",
        "must give the missing-header reason, got: {}",
        body["error"],
    );
}

#[tokio::test]
async fn admin_auth_rejects_invalid_header_format() {
    let _guard = AdminTokenGuard::set("real-admin-secret");
    let client = TestClient::new(guarded_app());

    // Header present but not "Bearer <token>".
    let resp = client
        .get("/admin/thing")
        .header("authorization", "Basic abc")
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
    let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
    assert!(
        body["error"].as_str().unwrap().contains("header format"),
        "must explain the bad format, got: {}",
        body["error"],
    );
}

#[tokio::test]
async fn admin_auth_rejects_wrong_token() {
    let _guard = AdminTokenGuard::set("real-admin-secret");
    let client = TestClient::new(guarded_app());

    let resp = client
        .get("/admin/thing")
        .header("authorization", "Bearer not-the-secret")
        .send()
        .await;
    resp.assert_status(StatusCode::UNAUTHORIZED);
    let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
    assert_eq!(
        body["error"], "Invalid admin credentials",
        "must say invalid credentials, got: {}",
        body["error"],
    );
}

#[tokio::test]
async fn admin_auth_passes_through_with_valid_token() {
    let _guard = AdminTokenGuard::set("real-admin-secret");
    let client = TestClient::new(guarded_app());

    let resp = client
        .get("/admin/thing")
        .header("authorization", "Bearer real-admin-secret")
        .send()
        .await;
    resp.assert_status_is_ok();
    let body: serde_json::Value = resp.0.into_body().into_json().await.unwrap();
    assert_eq!(body["ok"], true, "the guarded handler must have run");
}

#[tokio::test]
async fn admin_auth_uses_insecure_default_when_env_unset() {
    // When ADMIN_TOKEN is unset, the middleware falls back to the documented
    // default ("change-me-in-production"). This locks the dev fallback so a
    // refactor doesn't silently change it; the startup warning
    // (warn_if_insecure_prod_admin_token) covers the production-risk side.
    let _guard = AdminTokenGuard::unset();
    let client = TestClient::new(guarded_app());

    let resp = client
        .get("/admin/thing")
        .header("authorization", "Bearer change-me-in-production")
        .send()
        .await;
    resp.assert_status_is_ok();
}
