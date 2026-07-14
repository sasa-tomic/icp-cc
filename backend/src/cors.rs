//! CORS middleware — single source of the origin allow-list + method set.
//!
//! Poem's [`Cors::new()`] default reflects ANY `Origin` back to the caller and
//! advertises every HTTP method (including `TRACE` / `CONNECT`) on preflight.
//! That is an open CORS relay: any site on the internet can issue cross-origin
//! requests and observe responses, and the preflight exposes verbs the API
//! never serves.
//!
//! [`build_cors`] constructs the production middleware:
//! - **Origins** — explicit allow-list:
//!   - loopback dev hosts, any port: `http://127.0.0.1:*`, `http://localhost:*`
//!     (covers the Flutter Web dev server on `127.0.0.1:8099` / `:8100`, the
//!     API itself, etc.);
//!   - the production origin, read from the `CORS_ALLOWED_ORIGIN` env var
//!     (default [`DEFAULT_PROD_ORIGIN`] — matches the frontend's
//!     `app_config.dart` `PUBLIC_API_ENDPOINT` / `MARKETPLACE_WEB_URL` default
//!     `https://icp-mp.kalaj.org`).
//! - **Methods** — exactly `GET` / `POST` / `PUT` / `DELETE` / `OPTIONS`.
//!   `TRACE` and `CONNECT` (advertised by the empty default) are dropped.
//! - **Headers** — left at the Poem default (any), which already does the
//!   right thing (echoes `Access-Control-Request-Headers` on preflight).
//!
//! The helper is the single construction site — `main.rs` and the tests both
//! go through it so the allow-list can never drift between them.

use poem::{http::Method, middleware::Cors};
use std::env;

/// Default production origin on the CORS allow-list.
///
/// Matches the frontend's `app_config.dart` `PUBLIC_API_ENDPOINT` /
/// `MARKETPLACE_WEB_URL` default (`https://icp-mp.kalaj.org`) — single source
/// on the backend. Operators override with the `CORS_ALLOWED_ORIGIN` env var
/// when deploying to a different host without touching code.
pub const DEFAULT_PROD_ORIGIN: &str = "https://icp-mp.kalaj.org";

/// Env var used to override the production origin on the CORS allow-list.
pub const CORS_ALLOWED_ORIGIN_ENV: &str = "CORS_ALLOWED_ORIGIN";

/// Constructs the marketplace CORS middleware. See the module docs for the
/// policy. Reads `CORS_ALLOWED_ORIGIN` at call time (once, from `main`).
#[must_use]
pub fn build_cors() -> Cors {
    let prod_origin = env::var(CORS_ALLOWED_ORIGIN_ENV)
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| DEFAULT_PROD_ORIGIN.to_string());

    Cors::new()
        // Local dev — wildcard per origin so any port works (the frontend
        // dev server runs on 127.0.0.1:8099 / :8100; the API binds to a
        // random loopback port in tests, etc.).
        .allow_origin_regex("http://127.0.0.1:*")
        .allow_origin_regex("http://localhost:*")
        // Configured production origin. Listed explicitly (not a regex) so
        // it is byte-exact — a spoofed `https://icp-mp.kalaj.org.evil.tld`
        // can never match.
        .allow_origin(prod_origin)
        // Explicit method set — drop TRACE / CONNECT / PATCH / HEAD that the
        // Poem default advertises but the API never serves.
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::DELETE,
            Method::OPTIONS,
        ])
}
