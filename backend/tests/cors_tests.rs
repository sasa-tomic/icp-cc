//! W7-4 (security, RED-first): CORS hardening.
//!
//! `Cors::new()` (Poem default) reflects ANY `Origin` back to the caller and
//! advertises ALL methods (incl. `TRACE` / `CONNECT`) on preflight. That is an
//! open relay: any site on the internet can issue cross-origin requests to the
//! marketplace API and observe the responses, and the preflight advertises
//! verbs the API never serves. The fix is an EXPLICIT origin allow-list
//! (loopback dev hosts + the production origin) + an explicit method set
//! (GET/POST/PUT/DELETE/OPTIONS only).
//!
//! These tests pin both invariants by exercising the real `Cors` middleware
//! end-to-end via Poem's `TestClient`:
//! 1. An arbitrary external `Origin` (`https://evil.example.com`) is NOT
//!    reflected — the response carries no `Access-Control-Allow-Origin: <evil>`
//!    header (the middleware short-circuits with a 403 before the inner
//!    handler runs).
//! 2. A legitimate local-dev `Origin` (`http://localhost:8099`) IS allowed —
//!    the response echoes `Access-Control-Allow-Origin: http://localhost:8099`.
//! 3. Preflight (`OPTIONS`) for an allowed origin + allowed method returns
//!    the explicit method list (and does NOT advertise `TRACE`).
//!
//! The allow-list is built centrally in `src/cors.rs` (`build_cors`) so the
//! route table and tests can never drift. The production origin is read from
//! `CORS_ALLOWED_ORIGIN` (default: `DEFAULT_PROD_ORIGIN`).

use icp_marketplace_api::cors::{build_cors, DEFAULT_PROD_ORIGIN};
use icp_marketplace_api::handlers::health_check;
use poem::http::{Method, StatusCode};
use poem::test::TestClient;
use poem::{get, EndpointExt, Route};

/// Builds a one-route app wired with the production CORS middleware + a trivial
/// handler so we can observe the middleware's own headers.
fn build_app() -> impl poem::Endpoint {
    Route::new()
        .at("/api/v1/health", get(health_check))
        .with(build_cors())
}

/// Asserts `resp` does NOT reflect the evil origin back to the caller.
fn assert_no_allow_origin(resp: &poem::test::TestResponse, evil: &str) {
    let header = resp
        .0
        .headers()
        .get("access-control-allow-origin")
        .map(|v| v.to_str().unwrap_or("").to_string());
    assert!(
        header.as_deref().is_none_or(|h| h != evil),
        "evil origin {evil:?} MUST NOT be reflected in \
         Access-Control-Allow-Origin (got {header:?}) — open CORS relay"
    );
}

#[tokio::test]
async fn evil_origin_is_not_reflected() {
    // W7-4: the previous `Cors::new()` config (empty allow-list + empty
    // method set) reflected ANY origin. The hardened allow-list must reject
    // arbitrary external origins — they never appear in
    // `Access-Control-Allow-Origin`.
    let client = TestClient::new(build_app());
    let resp = client
        .get("/api/v1/health")
        .header("Origin", "https://evil.example.com")
        .send()
        .await;
    // The middleware short-circuits with 403 before the handler runs.
    resp.assert_status(StatusCode::FORBIDDEN);
    assert_no_allow_origin(&resp, "https://evil.example.com");
}

#[tokio::test]
async fn localhost_dev_origin_is_allowed() {
    // W7-4: legitimate local dev origins (frontend dev server :8099, :8100,
    // the API itself on its bound port, …) MUST keep working. The hardened
    // allow-list includes `http://localhost:*` and `http://127.0.0.1:*` so
    // any loopback port is accepted.
    let client = TestClient::new(build_app());
    let resp = client
        .get("/api/v1/health")
        .header("Origin", "http://localhost:8099")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let header = resp
        .0
        .headers()
        .get("access-control-allow-origin")
        .expect("allowed origin MUST be reflected back");
    assert_eq!(
        header.to_str().unwrap(),
        "http://localhost:8099",
        "dev localhost origin must be echoed verbatim"
    );
}

#[tokio::test]
async fn loopback_ipv4_dev_origin_is_allowed() {
    // The other dev form: `http://127.0.0.1:<port>`.
    let client = TestClient::new(build_app());
    let resp = client
        .get("/api/v1/health")
        .header("Origin", "http://127.0.0.1:8100")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let header = resp
        .0
        .headers()
        .get("access-control-allow-origin")
        .expect("allowed origin MUST be reflected back");
    assert_eq!(header.to_str().unwrap(), "http://127.0.0.1:8100");
}

#[tokio::test]
async fn production_origin_is_allowed() {
    // The configured production origin (default `DEFAULT_PROD_ORIGIN` in
    // tests) MUST be on the allow-list.
    let client = TestClient::new(build_app());
    let resp = client
        .get("/api/v1/health")
        .header("Origin", DEFAULT_PROD_ORIGIN)
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let header = resp
        .0
        .headers()
        .get("access-control-allow-origin")
        .expect("production origin MUST be reflected back");
    assert_eq!(header.to_str().unwrap(), DEFAULT_PROD_ORIGIN);
}

#[tokio::test]
async fn preflight_does_not_advertise_trace_or_connect() {
    // W7-4: preflight must NOT advertise `TRACE` or `CONNECT` (or any verb
    // the API never serves). The hardened allow-list is exactly
    // GET/POST/PUT/DELETE/OPTIONS.
    let client = TestClient::new(build_app());
    let resp = client
        .request(Method::OPTIONS, "/api/v1/health")
        .header("Origin", "http://localhost:8099")
        .header("Access-Control-Request-Method", "GET")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let methods = resp
        .0
        .headers()
        .get("access-control-allow-methods")
        .map(|v| v.to_str().unwrap_or("").to_string())
        .unwrap_or_default();
    assert!(
        !methods.to_lowercase().contains("trace"),
        "TRACE MUST NOT be advertised (got {methods:?})"
    );
    assert!(
        !methods.to_lowercase().contains("connect"),
        "CONNECT MUST NOT be advertised (got {methods:?})"
    );
    // Sanity: the verbs we DO need are present.
    for need in ["get", "post", "put", "delete", "options"] {
        assert!(
            methods.to_lowercase().contains(need),
            "{need} MUST be advertised (got {methods:?})"
        );
    }
}
