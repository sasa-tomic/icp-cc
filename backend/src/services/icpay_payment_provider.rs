//! [`ICPayPaymentProvider`] — production payment provider behind the generic
//! [`PaymentProvider`](super::PaymentProvider) trait.
//!
//! Wraps the existing ICPay webhook verification + client-config logic
//! (previously in `payment_service.rs`). The webhook side stays
//! ICPay-specific (the generic trait does not expose it); the trait methods
//! (`initiate_purchase`, `verify_purchase`, `refund_purchase`,
//! `client_config`) provide the provider-agnostic dispatch surface.
//!
//! ## Phase K behaviour
//!
//! `initiate_purchase` returns `Pending` without an upstream ICPay API call:
//! the frontend continues to drive ICPay's hosted checkout via its client
//! SDK (the historical flow). The backend records the entitlement when the
//! ICPay webhook lands. A future enhancement may create the intent
//! server-side here when `ICPAY_SECRET_KEY` is set.

use async_trait::async_trait;
use chrono::Utc;
use hmac::{Hmac, Mac};
use sha2::Sha256;

use crate::models::{NewPurchase, PaymentConfig, WebhookEvent};
use crate::repositories::PurchaseRepository;
use crate::services::error::PaymentError;
use crate::services::PaymentProvider;

/// HMAC-SHA256 alias for ICPay webhook verification.
type HmacSha256 = Hmac<Sha256>;

/// The ICPay token shortcode this app pays with (ICP + ICRC tokens; Plug /
/// Internet Identity / NFID wallets). Single source of truth for the client
/// config + intent creation.
const ICPAY_TOKEN_SHORTCODE: &str = "ic_icp";

/// The ICPay REST API base URL.
const ICPAY_API_URL: &str = "https://api.icpay.org";

/// The set of status strings (lowercased) that `record_purchase_from_webhook`
/// treats as a successful, entitlement-granting payment.
const COMPLETED_STATUSES: &[&str] = &["completed", "succeeded", "paid"];

/// Production payment provider implementing the generic
/// [`PaymentProvider`] trait over the ICPay hosted-checkout flow.
///
/// Owns:
/// - ICPay configuration read from the environment at construction
///   (`ICPAY_PUBLISHABLE_KEY`, `ICPAY_SECRET_KEY`, `ICPAY_WEBHOOK_SECRET`);
/// - **webhook verification** ([`Self::verify_webhook`]) — HMAC-SHA256 over
///   the RAW request body, constant-time compared, parsed into a typed
///   [`WebhookEvent`];
/// - **purchase recording** ([`Self::record_purchase_from_webhook`]) —
///   idempotent insert when the event signals completion;
/// - the **public client config** ([`Self::get_publishable_config`]) via the
///   trait's `client_config()`.
///
/// Loud-misconfig policy: when `ICPAY_WEBHOOK_SECRET` is unset the verifier
/// refuses (returns `Err`); the webhook handler short-circuits before that
/// with a 503 + generic "Payment provider not configured" body. When
/// `ICPAY_PUBLISHABLE_KEY` is unset `client_config()` returns `None` →
/// `GET /api/v1/payments/config` returns 503.
pub struct ICPayPaymentProvider {
    publishable_key: Option<String>,
    /// Server-only. Currently unused on the backend (intent creation is
    /// client-driven) but read from env so a future server-side intent flow
    /// is a config-only change. NEVER returned to clients.
    #[allow(dead_code)]
    secret_key: Option<String>,
    webhook_secret: Option<String>,
    repo: PurchaseRepository,
}

impl ICPayPaymentProvider {
    /// Reads ICPay configuration from the environment. `Ok` always — unset
    /// vars are stored as `None` and surfaced loudly at the call site
    /// (webhook → 500, config → 503). The app must still boot and browse
    /// the marketplace when ICPay is unconfigured.
    pub fn from_env(pool: sqlx::SqlitePool) -> Self {
        Self {
            publishable_key: env_var("ICPAY_PUBLISHABLE_KEY"),
            secret_key: env_var("ICPAY_SECRET_KEY"),
            webhook_secret: env_var("ICPAY_WEBHOOK_SECRET"),
            repo: PurchaseRepository::new(pool),
        }
    }

    /// Explicit-config constructor (dependency injection). Production code
    /// uses [`Self::from_env`]; this is the testable seam that lets tests
    /// (and a future operator-config flow) supply config without mutating
    /// the process environment. `None` for any field surfaces loudly at the
    /// call site, exactly like `from_env`.
    pub fn with_config(
        publishable_key: Option<String>,
        secret_key: Option<String>,
        webhook_secret: Option<String>,
        pool: sqlx::SqlitePool,
    ) -> Self {
        Self {
            publishable_key,
            secret_key,
            webhook_secret,
            repo: PurchaseRepository::new(pool),
        }
    }

    /// True iff the webhook secret is configured. The handler uses this to
    /// fail LOUDLY (500) before even reading the body when misconfigured.
    pub fn has_webhook_secret(&self) -> bool {
        self.webhook_secret.is_some()
    }

    /// Verifies an ICPay webhook delivery and parses the event.
    ///
    /// `raw_body` MUST be the exact bytes the sender produced (read BEFORE
    /// any JSON re-serialisation); the HMAC is computed over those bytes.
    /// The `signature_header` is the hex-encoded HMAC-SHA256 from the
    /// `X-ICPay-Signature` header.
    pub fn verify_webhook(
        &self,
        raw_body: &[u8],
        signature_header: &str,
    ) -> Result<WebhookEvent, PaymentError> {
        let secret = self.webhook_secret.as_deref().ok_or_else(|| {
            PaymentError::Internal("ICPAY_WEBHOOK_SECRET not configured".to_string())
        })?;

        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).map_err(|e| {
            PaymentError::Internal(format!("Invalid ICPAY_WEBHOOK_SECRET length: {e}"))
        })?;
        mac.update(raw_body);
        let expected_bytes = mac.finalize().into_bytes();
        let expected_hex = hex_encode(&expected_bytes);

        if !crate::crypto_util::constant_time_eq(
            expected_hex.as_bytes(),
            signature_header.trim().as_bytes(),
        ) {
            return Err(PaymentError::Unauthorized(
                "Invalid ICPay webhook signature".to_string(),
            ));
        }

        serde_json::from_slice::<WebhookEvent>(raw_body)
            .map_err(|e| PaymentError::BadRequest(format!("Invalid ICPay webhook body: {e}")))
    }

    /// Records an entitlement from a verified webhook event. Idempotent via
    /// the repo's `ON CONFLICT(account_id, script_id) DO NOTHING`.
    ///
    /// Returns `Ok(true)` when a row was inserted, `Ok(false)` when the
    /// event was ignored (non-completed) OR the entitlement already existed.
    pub async fn record_purchase_from_webhook(&self, event: &WebhookEvent) -> Result<bool, String> {
        let status = match event.status.as_deref() {
            Some(s) => s.to_ascii_lowercase(),
            None => return Ok(false),
        };
        if !COMPLETED_STATUSES.contains(&status.as_str()) {
            return Ok(false);
        }

        let account_id = event.metadata.account_id.as_deref().ok_or_else(|| {
            "ICPay webhook completed event missing metadata.account_id".to_string()
        })?;
        let script_id = event.metadata.script_id.as_deref().ok_or_else(|| {
            "ICPay webhook completed event missing metadata.script_id".to_string()
        })?;

        let now = Utc::now().to_rfc3339();
        let purchase = NewPurchase {
            id: uuid::Uuid::new_v4().to_string(),
            account_id: account_id.to_string(),
            script_id: script_id.to_string(),
            icpay_intent_id: event.metadata.intent_id.clone(),
            icpay_transaction_id: event.resolve_transaction_id().map(str::to_string),
            usd_amount: event.usd_amount.unwrap_or(0.0),
            currency: "USD".to_string(),
            status,
            paid_at: now.clone(),
            created_at: now,
        };

        self.repo
            .create_or_ignore(&purchase)
            .await
            .map_err(|e| format!("Failed to record purchase: {e}"))
    }

    /// Returns the browser-safe ICPay client config. The handler maps
    /// `None` (publishable key unset) to a 503.
    pub fn get_publishable_config(&self) -> Option<PaymentConfig> {
        self.publishable_key.clone().map(|publishable_key| PaymentConfig {
            publishable_key,
            shortcode: ICPAY_TOKEN_SHORTCODE.to_string(),
            api_url: ICPAY_API_URL.to_string(),
        })
    }
}

#[async_trait]
impl PaymentProvider for ICPayPaymentProvider {
    fn name(&self) -> &'static str {
        "icpay"
    }

    async fn initiate_purchase(
        &self,
        _script_id: &str,
        _account_id: &str,
        usd_amount: f64,
    ) -> Result<super::payment_provider::PurchaseIntent, PaymentError> {
        // Phase K: the frontend still drives ICPay's hosted checkout via its
        // client SDK (the historical flow). The backend's generic purchase
        // endpoint exists for the Stub provider + future server-side
        // intent creation. Here we surface a Loud misconfig when the
        // publishable key is missing (the client cannot create an intent
        // without it) and otherwise return a Pending intent — the
        // entitlement is recorded later via the webhook.
        if self.publishable_key.is_none() {
            return Err(PaymentError::Internal(
                "ICPay purchase requires ICPAY_PUBLISHABLE_KEY to be set".to_string(),
            ));
        }
        Ok(super::payment_provider::PurchaseIntent {
            id: format!("icpay-pending-{}", uuid::Uuid::new_v4()),
            status: super::payment_provider::PurchaseStatus::Pending,
            checkout_url: None,
            provider: "icpay",
            usd_amount,
        })
    }

    async fn verify_purchase(
        &self,
        _intent_id: &str,
    ) -> Result<super::payment_provider::PurchaseStatus, PaymentError> {
        // The ICPay webhook is the source of truth; server-side polling of
        // ICPay's API is a future enhancement. Return Pending so callers
        // know to wait for the webhook.
        Ok(super::payment_provider::PurchaseStatus::Pending)
    }

    async fn refund_purchase(&self, _intent_id: &str) -> Result<(), PaymentError> {
        // Not yet implemented — surface loudly rather than silently no-op.
        Err(PaymentError::Internal(
            "ICPay server-side refund not yet implemented".to_string(),
        ))
    }

    fn client_config(&self) -> Option<PaymentConfig> {
        self.get_publishable_config()
    }
}

fn env_var(name: &str) -> Option<String> {
    match std::env::var(name) {
        Ok(v) => {
            let trimmed = v.trim().to_string();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed)
            }
        }
        Err(_) => None,
    }
}

/// Lowercase hex encoding (no `hex` crate dependency).
fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::initialize_database;
    use sqlx::sqlite::SqlitePoolOptions;

    fn sign(secret: &str, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(body);
        hex_encode(&mac.finalize().into_bytes())
    }

    async fn setup() -> ICPayPaymentProvider {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        initialize_database(&pool).await;
        ICPayPaymentProvider {
            publishable_key: Some("pk_test_demo".to_string()),
            secret_key: Some("sk_test_demo".to_string()),
            webhook_secret: Some("whsec_demo".to_string()),
            repo: PurchaseRepository::new(pool),
        }
    }

    fn completed_event(account: &str, script: &str) -> String {
        serde_json::json!({
            "id": "icpay-tx-123",
            "status": "completed",
            "usdAmount": 9.99,
            "metadata": {
                "accountId": account,
                "scriptId": script,
                "intentId": "intent-abc"
            }
        })
        .to_string()
    }

    // ---- verify_webhook ----

    #[tokio::test]
    async fn verify_webhook_accepts_valid_signature() {
        let svc = setup().await;
        let body = completed_event("acct-1", "script-1");
        let sig = sign("whsec_demo", body.as_bytes());
        let event = svc
            .verify_webhook(body.as_bytes(), &sig)
            .expect("valid signature must parse");
        assert_eq!(event.status.as_deref(), Some("completed"));
        assert_eq!(event.metadata.account_id.as_deref(), Some("acct-1"));
        assert_eq!(event.metadata.script_id.as_deref(), Some("script-1"));
        assert_eq!(event.resolve_transaction_id(), Some("icpay-tx-123"));
        assert!((event.usd_amount.unwrap() - 9.99).abs() < f64::EPSILON);
    }

    #[tokio::test]
    async fn verify_webhook_rejects_tampered_body() {
        let svc = setup().await;
        let body = completed_event("acct-1", "script-1");
        let sig = sign("whsec_demo", body.as_bytes());
        let tampered = body.replace("acct-1", "acct-2");
        let err = svc.verify_webhook(tampered.as_bytes(), &sig).unwrap_err();
        assert!(err.message().contains("signature"), "got: {err}");
    }

    #[tokio::test]
    async fn verify_webhook_rejects_wrong_secret() {
        let svc = setup().await;
        let body = completed_event("acct-1", "script-1");
        let sig = sign("whsec_WRONG", body.as_bytes());
        let err = svc.verify_webhook(body.as_bytes(), &sig).unwrap_err();
        assert!(err.message().contains("signature"), "got: {err}");
    }

    #[tokio::test]
    async fn verify_webhook_rejects_malformed_json() {
        let svc = setup().await;
        let body = b"{ this is not json ";
        let sig = sign("whsec_demo", body);
        let err = svc.verify_webhook(body, &sig).unwrap_err();
        assert!(
            err.message().contains("Invalid ICPay webhook body"),
            "got: {err}"
        );
    }

    // ---- record_purchase_from_webhook ----

    #[tokio::test]
    async fn record_purchase_inserts_on_completed() {
        let svc = setup().await;
        let body = completed_event("acct-1", "script-1");
        let event = svc
            .verify_webhook(body.as_bytes(), &sign("whsec_demo", body.as_bytes()))
            .unwrap();
        let inserted = svc.record_purchase_from_webhook(&event).await.unwrap();
        assert!(inserted);
        assert!(
            svc.repo
                .exists_for_account_and_script("acct-1", "script-1")
                .await
                .unwrap()
        );
    }

    #[tokio::test]
    async fn record_purchase_is_idempotent_on_redelivery() {
        let svc = setup().await;
        let body = completed_event("acct-1", "script-1");
        let event = svc
            .verify_webhook(body.as_bytes(), &sign("whsec_demo", body.as_bytes()))
            .unwrap();
        let first = svc.record_purchase_from_webhook(&event).await.unwrap();
        let second = svc.record_purchase_from_webhook(&event).await.unwrap();
        assert!(first);
        assert!(!second, "redelivery must be a no-op");
    }

    #[tokio::test]
    async fn record_purchase_accepts_succeeded_and_paid_statuses() {
        for status in ["succeeded", "paid", "COMPLETED", "Paid"] {
            let svc = setup().await;
            let body = serde_json::json!({
                "id": "tx",
                "status": status,
                "metadata": {"accountId": "a", "scriptId": "s"}
            })
            .to_string();
            let event = svc
                .verify_webhook(body.as_bytes(), &sign("whsec_demo", body.as_bytes()))
                .unwrap();
            let inserted = svc.record_purchase_from_webhook(&event).await.unwrap();
            assert!(inserted, "status '{status}' must be treated as completion");
        }
    }

    // ---- get_publishable_config ----

    #[tokio::test]
    async fn get_publishable_config_returns_config_when_set() {
        let svc = setup().await;
        let cfg = svc.get_publishable_config().expect("publishable key is set");
        assert_eq!(cfg.publishable_key, "pk_test_demo");
        assert_eq!(cfg.shortcode, "ic_icp");
        assert_eq!(cfg.api_url, "https://api.icpay.org");
    }

    #[tokio::test]
    async fn get_publishable_config_returns_none_when_unset() {
        let pool = SqlitePoolOptions::new()
            .connect("sqlite::memory:")
            .await
            .unwrap();
        let svc = ICPayPaymentProvider::with_config(None, None, Some("whsec".into()), pool);
        assert!(svc.get_publishable_config().is_none());
    }

    // ---- PaymentProvider trait impl ----

    #[tokio::test]
    async fn icpay_initiate_purchase_returns_pending_when_configured() {
        let svc = setup().await;
        let intent = svc
            .initiate_purchase("script-1", "acct-1", 9.99)
            .await
            .unwrap();
        assert_eq!(intent.provider, "icpay");
        assert_eq!(
            intent.status,
            super::super::payment_provider::PurchaseStatus::Pending
        );
        assert!(intent.id.starts_with("icpay-pending-"));
        assert!(intent.checkout_url.is_none());
    }

    #[tokio::test]
    async fn icpay_initiate_purchase_errors_when_publishable_key_unset() {
        let pool = SqlitePoolOptions::new()
            .connect("sqlite::memory:")
            .await
            .unwrap();
        let svc = ICPayPaymentProvider::with_config(None, None, None, pool);
        let err = svc
            .initiate_purchase("s", "a", 1.0)
            .await
            .unwrap_err();
        assert!(matches!(err, PaymentError::Internal(_)));
        assert!(
            err.message().contains("ICPAY_PUBLISHABLE_KEY"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn icpay_verify_purchase_always_pending() {
        let svc = setup().await;
        let status = svc.verify_purchase("anything").await.unwrap();
        assert_eq!(
            status,
            super::super::payment_provider::PurchaseStatus::Pending
        );
    }

    #[tokio::test]
    async fn icpay_refund_purchase_is_not_implemented() {
        let svc = setup().await;
        let err = svc.refund_purchase("anything").await.unwrap_err();
        assert!(matches!(err, PaymentError::Internal(_)));
    }

    #[tokio::test]
    async fn icpay_client_config_delegates_to_publishable_config() {
        let svc = setup().await;
        let cfg = svc.client_config().expect("configured");
        assert_eq!(cfg.publishable_key, "pk_test_demo");
    }

    #[test]
    fn hex_encode_is_lowercase() {
        assert_eq!(hex_encode(&[0x01, 0xff, 0xa0]), "01ffa0");
    }
}
