//! Tests for `ic_proxy` — see `ic_proxy.rs` module docs.
//!
//! Three behaviours proven:
//! 1. Forwards method + path + query + body + content-type verbatim and
//!    returns the upstream status + body verbatim.
//! 2. Rejects oversized request bodies with 413 (the size cap).
//! 3. Applies the per-request timeout against a blackhole upstream (mirrors
//!    the native `call_anonymous_timeout_fires_against_blackhole` test at
//!    `canister_client.rs:900-944`).
//!
//! `cargo nextest` runs each test in its OWN process, so the process-global
//! `IC_GATEWAY_HOST` / `ICPCC_CANISTER_TIMEOUT_SECS` mutations below cannot
//! leak between tests. (The shared reqwest client caches only the connection
//! pool — the host + timeout are read per-request, never cached on it.)

use std::time::{Duration, Instant};

use poem::http::StatusCode;
use poem::test::TestClient;
use poem::{get, middleware::Cors, EndpointExt, Route};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

use crate::handlers::ic_proxy::ic_proxy;

/// The `/api/v1/ic/*rest` route wired exactly like `main.rs` (with the global
/// `Cors::new()` so CORS behaviour matches production). The proxy handler does
/// not extract `AppState`, so no `.data(state)` is needed — keeping the test
/// focused on the relay (no DB fixture required).
fn build_app() -> impl poem::Endpoint {
    Route::new()
        .at("/api/v1/ic/*rest", get(ic_proxy).post(ic_proxy))
        .with(Cors::new())
}

/// Save `IC_GATEWAY_HOST`, set it to `host`, and return a guard that restores
/// the prior value (or removes it) on drop. RAII so the test body can `?`/panic
/// freely without leaking the override.
struct GatewayHostGuard {
    prior: Option<String>,
}
impl GatewayHostGuard {
    fn set(host: &str) -> Self {
        let prior = std::env::var("IC_GATEWAY_HOST").ok();
        std::env::set_var("IC_GATEWAY_HOST", host);
        Self { prior }
    }
}
impl Drop for GatewayHostGuard {
    fn drop(&mut self) {
        match &self.prior {
            Some(v) => std::env::set_var("IC_GATEWAY_HOST", v),
            None => std::env::remove_var("IC_GATEWAY_HOST"),
        }
    }
}

/// Same as [GatewayHostGuard] for the timeout env var.
struct TimeoutGuard {
    prior: Option<String>,
}
impl TimeoutGuard {
    fn set(secs: u64) -> Self {
        let prior = std::env::var("ICPCC_CANISTER_TIMEOUT_SECS").ok();
        std::env::set_var("ICPCC_CANISTER_TIMEOUT_SECS", secs.to_string());
        Self { prior }
    }
}
impl Drop for TimeoutGuard {
    fn drop(&mut self) {
        match &self.prior {
            Some(v) => std::env::set_var("ICPCC_CANISTER_TIMEOUT_SECS", v),
            None => std::env::remove_var("ICPCC_CANISTER_TIMEOUT_SECS"),
        }
    }
}

fn find_header_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

/// A tiny HTTP/1.1 responder that echoes the received method + path + query +
/// body + content-type back as a JSON body with status 200. This lets the test
/// verify the proxy forwarded everything verbatim. Accepts connections in a
/// loop (so a stray preflight/extra request cannot consume the one-shot
/// accept) until the task is aborted by the test.
async fn echo_upstream(listener: TcpListener) {
    loop {
        let (mut sock, _) = match listener.accept().await {
            Ok(s) => s,
            Err(_) => return,
        };
        // Read the full request: headers until \r\n\r\n, then Content-Length
        // body bytes (or none if no Content-Length).
        let mut buf = Vec::with_capacity(4096);
        let mut tmp = [0u8; 1024];
        let mut clen = 0usize;
        loop {
            let n = match sock.read(&mut tmp).await {
                Ok(0) => break,
                Ok(n) => n,
                Err(_) => break,
            };
            buf.extend_from_slice(&tmp[..n]);
            if let Some(idx) = find_header_end(&buf) {
                let header = std::str::from_utf8(&buf[..idx]).unwrap_or("");
                clen = header
                    .lines()
                    .find_map(|l| {
                        let l = l.to_lowercase();
                        l.strip_prefix("content-length: ")
                            .and_then(|v| v.trim().parse::<usize>().ok())
                    })
                    .unwrap_or(0);
                let have = buf.len() - (idx + 4);
                if have >= clen {
                    break;
                }
            }
        }
        let _ = clen; // read-only; used to gate the loop above

        let text = String::from_utf8_lossy(&buf);
        let mut lines = text.lines();
        let request_line = lines.next().unwrap_or("");
        let (method, path) = {
            let mut parts = request_line.split_whitespace();
            let m = parts.next().unwrap_or("");
            let p = parts.next().unwrap_or("");
            (m.to_string(), p.to_string())
        };
        let content_type = text
            .lines()
            .find_map(|l| {
                let lower = l.to_lowercase();
                lower
                    .strip_prefix("content-type: ")
                    .map(|v| v.trim().to_string())
            })
            .unwrap_or_default();
        let body = find_header_end(&buf)
            .map(|idx| String::from_utf8_lossy(&buf[idx + 4..]).to_string())
            .unwrap_or_default();

        let resp_body = serde_json::json!({
            "method": method,
            "path": path,
            "contentType": content_type,
            "body": body,
        })
        .to_string();
        let http = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            resp_body.len(),
            resp_body
        );
        let _ = sock.write_all(http.as_bytes()).await;
        let _ = sock.flush().await;
        let _ = sock.shutdown().await;
    }
}

/// Read a TestClient JSON response body into a `serde_json::Value`.
async fn json_value(resp: poem::test::TestResponse) -> serde_json::Value {
    resp.json().await.value().deserialize::<serde_json::Value>()
}

#[tokio::test]
async fn forwards_method_path_body_and_returns_upstream_status_body() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let upstream = format!("http://{}", addr);
    let echo = tokio::spawn(echo_upstream(listener));

    let _gw = GatewayHostGuard::set(&upstream);
    let client = TestClient::new(build_app());

    let resp = client
        .post("/api/v1/ic/api/v3/canister/ryjl3-tyaaa-aaaaa-aaaba-cai/query")
        .header("Content-Type", "application/cbor")
        .body(b"raw-cbor-bytes".to_vec())
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["method"], "POST");
    assert_eq!(
        json["path"],
        "/api/v3/canister/ryjl3-tyaaa-aaaaa-aaaba-cai/query"
    );
    assert_eq!(json["contentType"], "application/cbor");
    assert_eq!(json["body"], "raw-cbor-bytes");

    echo.abort();
}

#[tokio::test]
async fn forwards_query_string_verbatim() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let upstream = format!("http://{}", addr);
    let echo = tokio::spawn(echo_upstream(listener));

    let _gw = GatewayHostGuard::set(&upstream);
    let client = TestClient::new(build_app());

    let resp = client
        .get("/api/v1/ic/api/v2/canister/abc/status?canister_id=xyz")
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["method"], "GET");
    assert_eq!(json["path"], "/api/v2/canister/abc/status?canister_id=xyz");

    echo.abort();
}

#[tokio::test]
async fn returns_upstream_non_200_status_verbatim() {
    // The echo here responds 502 — the proxy MUST return 502 verbatim (not
    // re-interpret it). Proves the relay is status-faithful.
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let upstream = format!("http://{}", addr);
    let fixed = tokio::spawn(fixed_status_upstream(listener, 502, "gateway-bad"));

    let _gw = GatewayHostGuard::set(&upstream);
    let client = TestClient::new(build_app());

    let resp = client
        .post("/api/v1/ic/api/v3/canister/x/query")
        .body(b"hi".to_vec())
        .send()
        .await;
    resp.assert_status(StatusCode::BAD_GATEWAY);
    resp.assert_text("gateway-bad").await;

    fixed.abort();
}

/// Respond with a fixed status + body for any request (status-faithfulness
/// test). The body is plain text.
async fn fixed_status_upstream(listener: TcpListener, status: u16, body: &str) {
    let _ = body; // moved below
    let (mut sock, _) = listener.accept().await.unwrap();
    // Drain the request (best-effort) so the client doesn't see a reset.
    let mut tmp = [0u8; 1024];
    let _ = sock.read(&mut tmp).await;
    let http = format!(
        "HTTP/1.1 {} OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        status,
        body.len(),
        body
    );
    let _ = sock.write_all(http.as_bytes()).await;
    let _ = sock.shutdown().await;
}

#[tokio::test]
async fn rejects_oversized_body_with_413() {
    // No upstream listener needed — the size cap fires BEFORE forwarding.
    let _gw = GatewayHostGuard::set("http://127.0.0.1:1");
    let client = TestClient::new(build_app());

    let oversized = vec![0u8; (2 * 1024 * 1024) + 1]; // 2 MiB + 1 byte
    let resp = client
        .post("/api/v1/ic/api/v3/canister/x/query")
        .body(oversized)
        .send()
        .await;
    resp.assert_status(StatusCode::PAYLOAD_TOO_LARGE);
    let json = json_value(resp).await;
    assert_eq!(json["success"], false);
    assert!(
        json["error"].as_str().unwrap().contains("too large"),
        "got: {json}"
    );
}

/// Mirrors the native `call_anonymous_timeout_fires_against_blackhole` test
/// (`canister_client.rs:900-944`): a blackhole TCP listener accepts the
/// connection but never responds, so without our per-request timeout the
/// proxy would hang forever. The 2s bound must hold.
#[tokio::test]
async fn timeout_fires_against_blackhole_upstream() {
    // Blackhole: accept connections but never write a byte.
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let upstream = format!("http://{}", addr);
    let blackhole = tokio::spawn(async move {
        // Accept connections but never write a byte (tokio's TcpListener has no
        // `.incoming()`; loop on accept). One connection is enough for the test.
        loop {
            match listener.accept().await {
                Ok((_stream, _)) => {
                    // Hold the accepted connection open without responding.
                    tokio::time::sleep(Duration::from_secs(60)).await;
                }
                Err(_) => return,
            }
        }
    });

    let _gw = GatewayHostGuard::set(&upstream);
    let _to = TimeoutGuard::set(2);
    let client = TestClient::new(build_app());

    let start = Instant::now();
    let resp = client
        .post("/api/v1/ic/api/v3/canister/x/query")
        .header("Content-Type", "application/cbor")
        .body(b"hi".to_vec())
        .send()
        .await;
    let elapsed = start.elapsed();

    resp.assert_status(StatusCode::GATEWAY_TIMEOUT);
    let json = json_value(resp).await;
    assert!(
        json["error"].as_str().unwrap().contains("timeout"),
        "error must name the timeout cause, got: {json}"
    );
    // The 2s bound must hold; give a generous upper margin for teardown while
    // still catching a regression that drops the timeout.
    assert!(
        elapsed < Duration::from_secs(10),
        "timeout did not fire promptly: {elapsed:?}"
    );

    blackhole.abort();
}

/// Upstream responds 200 + a `Content-Length` larger than the body actually
/// sent, then closes the connection — a truncated body. reqwest's `.bytes()`
/// must surface this as an error; the proxy must turn that into a LOUD 502,
/// NOT a 200 with an empty/partial body (which would feed corrupt CBOR to
/// agent-js and surface as a confusing certificate error downstream).
async fn truncated_body_upstream(listener: TcpListener) {
    let (mut sock, _) = listener.accept().await.unwrap();
    // Drain the request (best-effort) so the client doesn't see a reset.
    let mut tmp = [0u8; 1024];
    let _ = sock.read(&mut tmp).await;
    // Headers say 100 bytes are coming; only "abc" (3) arrive before close.
    let http = "HTTP/1.1 200 OK\r\nContent-Type: application/cbor\r\nContent-Length: 100\r\nConnection: close\r\n\r\nabc";
    let _ = sock.write_all(http.as_bytes()).await;
    let _ = sock.flush().await;
    let _ = sock.shutdown().await;
}

#[tokio::test]
async fn truncated_upstream_body_returns_bad_gateway_not_200_empty() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let upstream = format!("http://{}", addr);
    let truncated = tokio::spawn(truncated_body_upstream(listener));

    let _gw = GatewayHostGuard::set(&upstream);
    let client = TestClient::new(build_app());

    let resp = client
        .post("/api/v1/ic/api/v3/canister/x/query")
        .header("Content-Type", "application/cbor")
        .body(b"hi".to_vec())
        .send()
        .await;

    // LOUD: must surface as 502, NOT a 200 with an empty/truncated body. On
    // the old `unwrap_or_default()` code this returned 200 + b"" — a silent
    // swallow of a mid-body connection drop.
    resp.assert_status(StatusCode::BAD_GATEWAY);
    let json = json_value(resp).await;
    assert_eq!(json["success"], false);
    assert!(
        json["error"].as_str().unwrap().contains("truncated"),
        "error must name the truncation cause, got: {json}"
    );

    truncated.abort();
}
