//! IC byte-relay CORS proxy — R-3b WU-1.
//!
//! A protocol-blind byte relay so the browser-side agent-js (R-3b WU-0+) can
//! reach IC boundary nodes through our backend. The browser cannot call
//! `ic0.app` directly: `ic0.app` sends no `Access-Control-Allow-Origin` for
//! `/api/v2/*` / `/api/v3/*` (empirically confirmed — see plan §7.2). This
//! proxy is the keystone that makes browser-side canister calls possible.
//!
//! ## Design (plan §7.3.1 + §7.4)
//! - Route: catch-all under `/api/v1/ic/*<rest>` (GET + POST). agent-js, with
//!   host overridden via a custom `fetch`, POSTs its CBOR request bodies here;
//!   `<rest>` = `api/v3/canister/<id>/query` etc.
//! - Behaviour: read the raw request body, forward the path + query + body
//!   verbatim to `${IC_GATEWAY_HOST}` (default `https://ic0.app`), return the
//!   upstream status + body verbatim. The global `Cors::new()` middleware
//!   (`main.rs`) adds CORS headers on the way out.
//! - The proxy is provably protocol-blind: agent-js keeps ALL CBOR encode/
//!   decode, request-id, signing, nonce, retry/backoff, and certificate/bls
//!   verification (`verifyQuerySignatures: true`). The proxy carries bytes
//!   opaquely and never sees a private key (zero-knowledge, end-to-end).
//!
//! ## Abuse surface (plan §7.8.5)
//! - Single upstream: ONLY `${IC_GATEWAY_HOST}` (never user-controlled).
//! - Size cap: 2 MiB request body (rejected loudly as 413).
//! - Timeout: every hop bounded by `ICPCC_CANISTER_TIMEOUT_SECS` (default 30s,
//!   reusing the native name so tests can shrink it — mirrors
//!   `call_anonymous_timeout_fires_against_blackhole`, `canister_client.rs:900`).

use std::time::Duration;

use poem::{handler, http::StatusCode, web::Path, IntoResponse, Request, Response};

use crate::responses::error_response;

/// Maximum accepted request body size. The IC agent's CBOR payloads are tiny
/// (query/update calls are a few hundred bytes; `read_state` a few KB). 2 MiB
/// is a generous ceiling that rejects abuse without rejecting any legitimate
/// call. Mirrors the "size cap" rule in AGENTS.md.
const MAX_BODY_BYTES: usize = 2 * 1024 * 1024;

/// Shared reqwest client (connection-pooled). Per-request timeouts are applied
/// via `RequestBuilder::timeout` so the env var is honoured on every call
/// (cached client ↔ fresh timeout, no stale bound).
static CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();

fn shared_client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            // No client-level timeout — per-request timeout (env-driven) below.
            .build()
            .expect("failed to build reqwest client for IC proxy")
    })
}

/// The single upstream IC gateway host. Defaults to the shared native const
/// `icp_core::DEFAULT_IC_GATEWAY` (single source of truth across core + backend
/// — see `canister_client.rs`). Overridable via `IC_GATEWAY_HOST` for testing
/// against a local mock or a different network. When the default is in use (var
/// unset) the marketplace still boots and browses — the proxy simply relays to
/// mainnet.
fn gateway_host() -> String {
    std::env::var("IC_GATEWAY_HOST").unwrap_or_else(|_| icp_core::DEFAULT_IC_GATEWAY.to_string())
}

/// Per-request network budget. Reuses the native `ICPCC_CANISTER_TIMEOUT_SECS`
/// name (default 30s) so tests can shrink it identically to the native
/// `call_anonymous_timeout_fires_against_blackhole` test. AGENTS.md: every I/O
/// must have a `.timeout()`.
fn proxy_timeout() -> Duration {
    const DEFAULT: Duration = Duration::from_secs(30);
    std::env::var("ICPCC_CANISTER_TIMEOUT_SECS")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .map(Duration::from_secs)
        .unwrap_or(DEFAULT)
}

/// Headers forwarded to the upstream. The IC agent sets `Content-Type`
/// (`application/cbor`) and sometimes `Accept`; both are forwarded verbatim.
/// Browser-specific headers (Origin, Cookie, …) are NOT forwarded — the proxy
/// is the IC agent's transport, not a generic browser-proxy.
fn forward_header(req: &Request, name: &'static str) -> Option<(&'static str, String)> {
    req.header(name).map(|v| (name, v.to_string()))
}

/// `GET|POST /api/v1/ic/*<rest>` — protocol-blind byte relay to IC boundary
/// nodes. See module docs.
#[handler]
pub async fn ic_proxy(req: &Request, Path(rest): Path<String>, body: Vec<u8>) -> Response {
    // 1. Size cap (plan §7.8.5). Reject loudly — never silently truncate.
    if body.len() > MAX_BODY_BYTES {
        tracing::warn!(
            "IC proxy rejected oversized request: {} bytes > {} cap (path={})",
            body.len(),
            MAX_BODY_BYTES,
            rest
        );
        return error_response(
            StatusCode::PAYLOAD_TOO_LARGE,
            "IC proxy request body too large",
        );
    }

    // 2. Build the upstream URL: ${IC_GATEWAY_HOST}/${rest}${?query}.
    let host = gateway_host();
    let host = host.trim_end_matches('/');
    let query = req
        .uri()
        .query()
        .map(|q| format!("?{q}"))
        .unwrap_or_default();
    let upstream_url = format!("{host}/{rest}{query}");

    // 3. Forward the request with the same method + relevant headers + body,
    //    bounded by the per-request timeout.
    let method = req.method().clone();
    let timeout = proxy_timeout();

    let mut builder = shared_client()
        .request(method.clone(), &upstream_url)
        .timeout(timeout);
    for name in ["content-type", "accept"] {
        if let Some((k, v)) = forward_header(req, name) {
            builder = builder.header(k, v);
        }
    }
    let builder = builder.body(body);

    let upstream = match builder.send().await {
        Ok(r) => r,
        Err(e) => {
            if e.is_timeout() {
                tracing::warn!(
                    "IC proxy upstream timeout ({}s): {} {}",
                    timeout.as_secs(),
                    method,
                    upstream_url
                );
                return error_response(
                    StatusCode::GATEWAY_TIMEOUT,
                    &format!("IC gateway timeout ({}s)", timeout.as_secs()),
                );
            }
            tracing::error!(
                "IC proxy upstream error: {} {} -> {}",
                method,
                upstream_url,
                e
            );
            return error_response(
                StatusCode::BAD_GATEWAY,
                &format!("IC gateway unreachable: {e}"),
            );
        }
    };

    // 4. Return upstream status + body + content-type verbatim. The global
    //    Cors middleware (applied to the whole Route in main.rs) adds the CORS
    //    headers on the way out — no explicit CORS handling needed here.
    let status =
        StatusCode::from_u16(upstream.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
    let content_type = upstream
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let bytes = upstream.bytes().await.unwrap_or_default();

    tracing::debug!(
        "IC proxy relayed: {} {} -> {} ({} bytes)",
        method,
        upstream_url,
        status.as_u16(),
        bytes.len()
    );

    let mut response = Response::builder().status(status);
    if let Some(ct) = content_type {
        response = response.content_type(ct);
    }
    response.body(bytes).into_response()
}

// ============================================================================
// Handler-level integration tests
// ============================================================================
//
// Prove the proxy is a faithful byte relay: forwards method+path+query+body+
// headers, returns upstream status+body verbatim, rejects oversized bodies
// (413), and applies the timeout against a blackhole upstream (mirrors the
// native `call_anonymous_timeout_fires_against_blackhole` test at
// `canister_client.rs:900-944`).
//
// The mock upstream is a tiny HTTP/1.1 responder on a tokio TCP listener — no
// extra test deps. It either echoes the received request (status/body/path
// assertions) or accepts-and-holds (blackhole timeout).

#[cfg(test)]
mod tests;
