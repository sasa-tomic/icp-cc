//! Deprecated alias kept for transition; the implementation now lives in
//! [`ICPayPaymentProvider`](super::ICPayPaymentProvider) (Phase K).
//!
//! New code MUST depend on the generic [`PaymentProvider`] trait (or the
//! concrete [`ICPayPaymentProvider`] when ICPay-specific methods like
//! `verify_webhook` are needed). This module exists so the few remaining
//! references in `handlers/payments/mod.rs`, `main.rs`, and the http tests
//! compile while those call sites are migrated; it will be removed in a
//! follow-up commit once all uses move.
//!
//! Kept as a re-export (rather than `pub type`) so doc-links + `from_env` /
//! `with_config` resolve transparently to the new location.

pub use super::icpay_payment_provider::ICPayPaymentProvider as PaymentService;
