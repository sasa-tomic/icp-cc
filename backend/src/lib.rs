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

    /// Builds an `AppState` with the **Stub** payment provider (dev default).
    /// Used by integration tests that don't exercise payment paths.
    pub fn app_state_stub(
        pool: sqlx::SqlitePool,
        passkey_service: services::PasskeyService,
        recovery_rate_limiter: Arc<SlidingWindowRateLimiter>,
    ) -> AppState {
        let stub = Arc::new(services::StubPaymentProvider::new(
            crate::repositories::PurchaseRepository::new(pool.clone()),
        ));
        let provider: Arc<dyn services::PaymentProvider> = stub;
        AppState {
            account_service: services::AccountService::new(pool.clone()),
            script_service: services::ScriptService::new(pool.clone()),
            review_service: services::ReviewService::new(pool.clone()),
            passkey_service,
            purchase_repo: crate::repositories::PurchaseRepository::new(pool.clone()),
            payment_provider: provider,
            icpay_provider: None,
            recovery_rate_limiter,
            pool,
        }
    }

    /// Builds an `AppState` with the **ICPay** payment provider, explicitly
    /// configured (used by the legacy ICPay webhook / config tests).
    pub fn app_state_icpay(
        pool: sqlx::SqlitePool,
        passkey_service: services::PasskeyService,
        recovery_rate_limiter: Arc<SlidingWindowRateLimiter>,
        publishable_key: Option<String>,
        webhook_secret: Option<String>,
    ) -> AppState {
        let icpay = Arc::new(services::ICPayPaymentProvider::with_config(
            publishable_key,
            None,
            webhook_secret,
            pool.clone(),
        ));
        let provider: Arc<dyn services::PaymentProvider> = icpay.clone();
        AppState {
            account_service: services::AccountService::new(pool.clone()),
            script_service: services::ScriptService::new(pool.clone()),
            review_service: services::ReviewService::new(pool.clone()),
            passkey_service,
            purchase_repo: crate::repositories::PurchaseRepository::new(pool.clone()),
            payment_provider: provider,
            icpay_provider: Some(icpay),
            recovery_rate_limiter,
            pool,
        }
    }
}
