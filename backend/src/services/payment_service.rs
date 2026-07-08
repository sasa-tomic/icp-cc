//! ICPay payment integration service.
//!
//! This service owns:
//! - ICPay configuration read from the environment at construction
//!   (`ICPAY_PUBLISHABLE_KEY`, `ICPAY_SECRET_KEY`, `ICPAY_WEBHOOK_SECRET`);
//! - **webhook verification** ([`PaymentService::verify_webhook`]) — an
//!   HMAC-SHA256 over the RAW request body with the shared webhook secret,
//!   constant-time compared, parsed into a typed [`WebhookEvent`];
//! - **purchase recording** ([`PaymentService::record_purchase_from_webhook`])
//!   — idempotently inserts an entitlement row when the event signals
//!   completion (`completed` / `succeeded` / `paid`, case-insensitive);
//! - the **public client config** ([`PaymentService::get_publishable_config`])
//!   returned to browsers.
//!
//! ## Assumption: webhook scheme
//! The live ICPay docs (`docs.icpay.org/webhooks`, network-blocked from the dev
//! sandbox) and the ICPay "Skills" reference describe verifying the
//! `X-ICPay-Signature` header as `HMAC-SHA256(raw_body, ICPAY_WEBHOOK_SECRET)`
//! rendered as lowercase hex. This service implements exactly that. The handler
//! also accepts the `X-Icpay-Signature` / `Icmpay-Signature` spelling variants
//! for resilience. **The human must confirm the encoding (hex vs base64) and
//! the exact header name against live ICPay docs before going to prod.**
//!
//! Loud-misconfig policy (AGENTS.md): when `ICPAY_WEBHOOK_SECRET` is unset the
//! service refuses to verify (returns `Err`); the webhook handler turns that
//! into a 500. When `ICPAY_PUBLISHABLE_KEY` is unset the config endpoint
//! returns 503. The app still boots and browses the marketplace — only the
//! payment endpoints 5xx/503 when invoked without config.

use crate::models::{NewPurchase, PaymentConfig, WebhookEvent};
use crate::repositories::PurchaseRepository;
use chrono::Utc;
use hmac::{Hmac, Mac};
use sha2::Sha256;
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

pub struct PaymentService {
    publishable_key: Option<String>,
    /// Server-only. Currently unused on the backend (intent creation is
    /// client-driven) but read from env so a future server-side intent flow is
    /// a config-only change. NEVER returned to clients.
    #[allow(dead_code)]
    secret_key: Option<String>,
    webhook_secret: Option<String>,
    purchase_repo: PurchaseRepository,
}

impl PaymentService {
    /// Reads ICPay configuration from the environment. `Ok` always — unset vars
    /// are stored as `None` and surfaced loudly at the call site (webhook →
    /// 500, config → 503). The app must still boot and browse the marketplace
    /// when ICPay is unconfigured.
    pub fn from_env(pool: sqlx::SqlitePool) -> Self {
        Self {
            publishable_key: env_var("ICPAY_PUBLISHABLE_KEY"),
            secret_key: env_var("ICPAY_SECRET_KEY"),
            webhook_secret: env_var("ICPAY_WEBHOOK_SECRET"),
            purchase_repo: PurchaseRepository::new(pool),
        }
    }

    /// Explicit-config constructor (dependency injection). Production code uses
    /// [`PaymentService::from_env`]; this is the testable seam that lets tests
    /// (and a future operator-config flow) supply config without mutating the
    /// process environment. `None` for any field surfaces loudly at the call
    /// site, exactly like `from_env`.
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
            purchase_repo: PurchaseRepository::new(pool),
        }
    }

    /// True iff the webhook secret is configured. The handler uses this to fail
    /// LOUDLY (500) before even reading the body when misconfigured.
    pub fn has_webhook_secret(&self) -> bool {
        self.webhook_secret.is_some()
    }

    /// Verifies an ICPay webhook delivery and parses the event.
    ///
    /// `raw_body` MUST be the exact bytes the sender produced (read BEFORE any
    /// JSON re-serialisation); the HMAC is computed over those bytes. The
    /// `signature_header` is the hex-encoded HMAC-SHA256 from the
    /// `X-ICPay-Signature` header.
    ///
    /// Returns:
    /// - `Ok(WebhookEvent)` on a valid signature + parseable JSON body;
    /// - `Err(String)` when the secret is unset (misconfig), the signature
    ///   mismatches, or the body is not valid JSON. The handler maps each to
    ///   the appropriate HTTP status (500 / 401 / 400).
    pub fn verify_webhook(
        &self,
        raw_body: &[u8],
        signature_header: &str,
    ) -> Result<WebhookEvent, String> {
        let secret = self
            .webhook_secret
            .as_deref()
            .ok_or("ICPAY_WEBHOOK_SECRET not configured")?;

        // Recompute HMAC-SHA256(raw_body, secret) and constant-time compare.
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
            .map_err(|e| format!("Invalid ICPAY_WEBHOOK_SECRET length: {e}"))?;
        mac.update(raw_body);
        let expected_bytes = mac.finalize().into_bytes();
        let expected_hex = hex_encode(&expected_bytes);

        if !constant_time_eq(expected_hex.as_bytes(), signature_header.trim().as_bytes()) {
            return Err("Invalid ICPay webhook signature".to_string());
        }

        serde_json::from_slice::<WebhookEvent>(raw_body)
            .map_err(|e| format!("Invalid ICPay webhook body: {e}"))
    }

    /// Records an entitlement from a verified webhook event.
    ///
    /// Only completes the insert when `event.status` indicates success
    /// (case-insensitive `completed` / `succeeded` / `paid`); non-completed
    /// events are ignored (no row, returns `Ok(false)`). The insert is
    /// idempotent via the repo's `ON CONFLICT(account_id, script_id) DO
    /// NOTHING`, so redelivery is a no-op.
    ///
    /// Returns `Ok(true)` when a row was inserted, `Ok(false)` when the event
    /// was ignored (non-completed) OR the entitlement already existed.
    /// Returns `Err` when the event is missing the required metadata
    /// (`account_id` / `script_id`) or the DB write fails — both are surfaced
    /// loudly.
    pub async fn record_purchase_from_webhook(&self, event: &WebhookEvent) -> Result<bool, String> {
        let status = match event.status.as_deref() {
            Some(s) => s.to_ascii_lowercase(),
            None => return Ok(false), // no status → not a completion, ignore
        };
        if !COMPLETED_STATUSES.contains(&status.as_str()) {
            // Pending / cancelled / failed events are not entitlements. Ignore.
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

        self.purchase_repo
            .create_or_ignore(&purchase)
            .await
            .map_err(|e| format!("Failed to record purchase: {e}"))
    }

    /// Returns the browser-safe ICPay client config. The handler maps
    /// `None` (publishable key unset) to a 503.
    pub fn get_publishable_config(&self) -> Option<PaymentConfig> {
        self.publishable_key
            .clone()
            .map(|publishable_key| PaymentConfig {
                publishable_key,
                shortcode: ICPAY_TOKEN_SHORTCODE.to_string(),
                api_url: ICPAY_API_URL.to_string(),
            })
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

/// Constant-time byte comparison that ALWAYS processes the full length of both
/// slices (no early-return on first mismatch). This blunts timing attacks
/// against the webhook signature check. Length differences are also factored
/// into the accumulator so as not to leak length via timing.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    let mut acc: u8 = 0;
    let n = a.len().max(b.len());
    for i in 0..n {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        acc |= x ^ y;
    }
    acc == 0 && a.len() == b.len()
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

    async fn setup() -> PaymentService {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        initialize_database(&pool).await;
        // Construct directly so tests can inject a known webhook secret without
        // touching the real process environment.
        PaymentService {
            publishable_key: Some("pk_test_demo".to_string()),
            secret_key: Some("sk_test_demo".to_string()),
            webhook_secret: Some("whsec_demo".to_string()),
            purchase_repo: PurchaseRepository::new(pool),
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
        // Flip the account id in the body AFTER signing.
        let tampered = body.replace("acct-1", "acct-2");
        let err = svc.verify_webhook(tampered.as_bytes(), &sig).unwrap_err();
        assert!(err.contains("signature"), "got: {err}");
    }

    #[tokio::test]
    async fn verify_webhook_rejects_wrong_secret() {
        let svc = setup().await;
        let body = completed_event("acct-1", "script-1");
        // Sign with a DIFFERENT secret than the service holds.
        let sig = sign("whsec_WRONG", body.as_bytes());
        let err = svc.verify_webhook(body.as_bytes(), &sig).unwrap_err();
        assert!(err.contains("signature"), "got: {err}");
    }

    #[tokio::test]
    async fn verify_webhook_rejects_missing_secret() {
        let svc = PaymentService {
            publishable_key: Some("pk".to_string()),
            secret_key: None,
            webhook_secret: None,
            purchase_repo: PurchaseRepository::new(
                SqlitePoolOptions::new()
                    .connect("sqlite::memory:")
                    .await
                    .unwrap(),
            ),
        };
        let body = completed_event("acct-1", "script-1");
        let sig = sign("whsec_demo", body.as_bytes());
        let err = svc.verify_webhook(body.as_bytes(), &sig).unwrap_err();
        assert!(
            err.contains("ICPAY_WEBHOOK_SECRET not configured"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn verify_webhook_rejects_malformed_json() {
        let svc = setup().await;
        let body = b"{ this is not json ";
        let sig = sign("whsec_demo", body);
        let err = svc.verify_webhook(body, &sig).unwrap_err();
        assert!(err.contains("Invalid ICPay webhook body"), "got: {err}");
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
        assert!(inserted, "first delivery must insert a row");
        // Entitlement is queryable.
        assert!(svc
            .purchase_repo
            .exists_for_account_and_script("acct-1", "script-1")
            .await
            .unwrap());
    }

    #[tokio::test]
    async fn record_purchase_ignores_pending_status() {
        let svc = setup().await;
        let body = serde_json::json!({
            "id": "tx",
            "status": "pending",
            "metadata": {"accountId": "acct-1", "scriptId": "script-1"}
        })
        .to_string();
        let event = svc
            .verify_webhook(body.as_bytes(), &sign("whsec_demo", body.as_bytes()))
            .unwrap();
        let inserted = svc.record_purchase_from_webhook(&event).await.unwrap();
        assert!(!inserted, "pending status must NOT grant entitlement");
        assert!(!svc
            .purchase_repo
            .exists_for_account_and_script("acct-1", "script-1")
            .await
            .unwrap());
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
        assert!(first, "first delivery inserts");
        assert!(
            !second,
            "redelivery must be a no-op (no error, no duplicate row)"
        );
        // Still exactly one row.
        let row = svc
            .purchase_repo
            .find_by_account_and_script("acct-1", "script-1")
            .await
            .unwrap();
        assert!(row.is_some());
    }

    #[tokio::test]
    async fn record_purchase_errors_on_missing_metadata() {
        let svc = setup().await;
        let body = serde_json::json!({
            "id": "tx",
            "status": "completed",
            "metadata": {"accountId": "acct-1"}
        })
        .to_string();
        let event = svc
            .verify_webhook(body.as_bytes(), &sign("whsec_demo", body.as_bytes()))
            .unwrap();
        let err = svc.record_purchase_from_webhook(&event).await.unwrap_err();
        assert!(err.contains("script_id"), "got: {err}");
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
        let cfg = svc
            .get_publishable_config()
            .expect("publishable key is set");
        assert_eq!(cfg.publishable_key, "pk_test_demo");
        assert_eq!(cfg.shortcode, "ic_icp");
        assert_eq!(cfg.api_url, "https://api.icpay.org");
    }

    #[tokio::test]
    async fn get_publishable_config_returns_none_when_unset() {
        let svc = PaymentService {
            publishable_key: None,
            secret_key: None,
            webhook_secret: Some("whsec".to_string()),
            purchase_repo: PurchaseRepository::new(
                SqlitePoolOptions::new()
                    .connect("sqlite::memory:")
                    .await
                    .unwrap(),
            ),
        };
        assert!(svc.get_publishable_config().is_none());
    }

    // ---- constant_time_eq + hex_encode helpers ----

    #[test]
    fn constant_time_eq_matches_and_differs_correctly() {
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(!constant_time_eq(b"abc", b"abd"));
        assert!(!constant_time_eq(b"abc", b"abcd"));
        assert!(!constant_time_eq(b"abcd", b"abc"));
        assert!(constant_time_eq(b"", b""));
        assert!(!constant_time_eq(b"", b"a"));
    }

    #[test]
    fn hex_encode_is_lowercase() {
        assert_eq!(hex_encode(&[0x01, 0xff, 0xa0]), "01ffa0");
    }
}
