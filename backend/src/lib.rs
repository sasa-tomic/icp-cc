pub mod auth;
pub mod cleanup;
pub mod cors;
pub mod crypto_util;
pub mod db;
pub mod handlers;
pub mod middleware;
pub mod models;
pub mod rate_limit;
pub mod repositories;
pub mod responses;
pub mod script_language;
pub mod services;
pub mod signature_gate;
pub mod startup_checks;
pub mod vault;

/// Test-only helpers for constructing an [`models::AppState`] over a given
/// pool. Used by the integration tests under `backend/tests/` (which are
/// separate crates and so cannot access `pub(crate)` items). Unmarked by
/// `#[cfg(test)]` because that gate only applies to the LIBRARY crate, not
/// external test crates — instead the helpers are clearly named `*_for_test`
/// so their intent is unambiguous (Rust's idiom for test-only constructors
/// that must be visible to integration tests).
pub mod test_support {
    use std::sync::Arc;

    use crate::{models::AppState, rate_limit::SlidingWindowRateLimiter, services};

    /// Builds an `AppState` for integration tests.
    pub fn app_state_stub(
        pool: sqlx::SqlitePool,
        passkey_service: services::PasskeyService,
        recovery_rate_limiter: Arc<SlidingWindowRateLimiter>,
    ) -> AppState {
        AppState {
            account_service: services::AccountService::new(pool.clone()),
            script_service: services::ScriptService::new(pool.clone()),
            review_service: services::ReviewService::new(pool.clone()),
            passkey_service,
            recovery_rate_limiter,
            pool,
        }
    }
}
