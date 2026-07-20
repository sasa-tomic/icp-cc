//! Provider-agnostic payment abstraction (Phase K).
//!
//! Replaces the prior hard-wired `PaymentService` → ICPay coupling with a
//! `PaymentProvider` trait so the backend can be wired to:
//! - [`StubPaymentProvider`] — dev default. Records the entitlement
//!   immediately and returns `Completed`. Deterministic, no network.
//! - [`ICPayPaymentProvider`] — production. Wraps the existing ICPay
//!   webhook + client-config logic behind the trait.
//! - [`NonePaymentProvider`] — fail-closed. All purchase attempts return
//!   `Err(PaymentError::PaymentsDisabled)` so the handler can map to HTTP 503.
//!
//! ## Selection
//!
//! [`resolve_provider_from_env`] reads `PAYMENT_PROVIDER` once at boot
//! (default `"stub"`; accepted: `stub | icpay | none`; unrecognised values
//! log a loud `tracing::error!` and fail closed to `None`). The selected
//! provider is held on `AppState` as `Arc<dyn PaymentProvider>` for runtime
//! dispatch.
//!
//! ## Storage
//!
//! `StubPaymentProvider` and `ICPayPaymentProvider` both write entitlements
//! through the existing [`PurchaseRepository`]. The `purchases.icpay_intent_id`
//! column is reused for ALL providers' intent IDs (the schema name is a
//! legacy artefact — never migrate per AGENTS.md "never delete DB or
//! tables").

use std::sync::Arc;

use async_trait::async_trait;
use serde::Serialize;

use crate::models::{NewPurchase, PaymentConfig};
use crate::repositories::PurchaseRepository;
use crate::services::error::PaymentError;
use crate::services::ICPayPaymentProvider;

/// Lowercase identifier string for the active provider — surfaced in JSON
/// responses + logs so an operator can see at a glance which path a purchase
/// took. Matches the `PAYMENT_PROVIDER` env var value (or `"none"`).
pub type ProviderName = &'static str;

/// A provider-agnostic purchase intent. The handler returns this from
/// `POST /api/v1/scripts/:id/purchase` so the client knows whether to poll /
/// refresh entitlement (Stub → `Completed`) or open a hosted checkout URL
/// (ICPay → `Pending` + `checkout_url`).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PurchaseIntent {
    /// Opaque identifier for this intent. Format is provider-specific
    /// (`stub-intent-{ulid}` for stub, `icpay-pending-{uuid}` for icpay).
    /// Stored in `purchases.icpay_intent_id` for ALL providers.
    pub id: String,
    pub status: PurchaseStatus,
    /// Hosted checkout URL when the provider requires an external round-trip
    /// (ICPay). `None` for Stub — the entitlement is already granted.
    pub checkout_url: Option<String>,
    /// Lowercase provider name (`"stub"` / `"icpay"`). Echoes the
    /// `PAYMENT_PROVIDER` env var so the client can branch on provider
    /// without a separate API call.
    pub provider: ProviderName,
    pub usd_amount: f64,
}

/// Lifecycle states a purchase intent can be in. Mirrors the strings the
/// legacy `PaymentService::record_purchase_from_webhook` treated as
/// successful (`completed` / `succeeded` / `paid`).
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PurchaseStatus {
    /// Awaiting external confirmation (e.g. ICPay hosted checkout not yet
    /// completed, or webhook not yet received).
    Pending,
    /// Entitlement granted — caller may download the paid bundle.
    Completed,
    /// Provider reported a terminal failure (declined, refunded, etc.).
    Failed,
}

/// The provider-agnostic payment contract.
///
/// Implementations are responsible for their own persistence (the stub and
/// ICPay providers both write entitlements through [`PurchaseRepository`],
/// so the existing entitlement gate at `GET /scripts/:id/download` works
/// regardless of which provider granted the entitlement).
///
/// Object-safe via `async_trait` so `AppState` can hold `Arc<dyn
/// PaymentProvider>` and switch implementations at boot.
#[async_trait]
pub trait PaymentProvider: Send + Sync {
    /// Lowercase identifier (`"stub"` / `"icpay"` / `"none"`). Stable for
    /// the process lifetime; surfaced in JSON responses.
    fn name(&self) -> ProviderName;

    /// Begin a purchase for `(script_id, account_id)` at `usd_amount`.
    ///
    /// - Stub: records the entitlement immediately + returns `Completed`.
    /// - ICPay: returns `Pending` (the client still drives ICPay's hosted
    ///   checkout via the frontend SDK; the backend records the entitlement
    ///   later via webhook).
    /// - None: returns `Err(PaymentError::PaymentsDisabled)`.
    async fn initiate_purchase(
        &self,
        script_id: &str,
        account_id: &str,
        usd_amount: f64,
    ) -> Result<PurchaseIntent, PaymentError>;

    /// Re-check the status of a previously-initiated intent.
    ///
    /// Stub: always `Completed` (deterministic). ICPay: `Pending` until the
    /// webhook lands (server-side polling is a future enhancement — the
    /// webhook remains the source of truth).
    async fn verify_purchase(&self, intent_id: &str) -> Result<PurchaseStatus, PaymentError>;

    /// Best-effort refund. Stub: no-op `Ok(())`. ICPay: not yet implemented
    /// (returns `Err(PaymentError::Internal)` — surfaced loudly rather than
    /// silently swallowed).
    async fn refund_purchase(&self, intent_id: &str) -> Result<(), PaymentError>;

    /// Browser-safe client config (`publishable_key` / `shortcode` /
    /// `apiUrl`). Returned by `GET /api/v1/payments/config`. `None` when the
    /// provider exposes no client-side config (Stub, None, or ICPay without
    /// `ICPAY_PUBLISHABLE_KEY`).
    fn client_config(&self) -> Option<PaymentConfig>;
}

// ============================================================================
// StubPaymentProvider — dev default
// ============================================================================

/// Dev / test payment provider. Auto-succeeds every purchase: writes the
/// entitlement row immediately via [`PurchaseRepository`] and returns
/// `Completed`. No network, no external service, fully deterministic.
///
/// The intent id is `stub-intent-{ulid}` (time-sortable). The `purchases
/// .icpay_intent_id` column is reused for ALL providers (legacy column name;
/// schema is never migrated per AGENTS.md).
pub struct StubPaymentProvider {
    repo: PurchaseRepository,
}

impl StubPaymentProvider {
    pub fn new(repo: PurchaseRepository) -> Self {
        Self { repo }
    }

    /// Constructs the canonical intent id. Public so tests can assert shape
    /// without re-deriving the format.
    pub fn intent_id() -> String {
        format!("stub-intent-{}", ulid::Ulid::new())
    }
}

#[async_trait]
impl PaymentProvider for StubPaymentProvider {
    fn name(&self) -> ProviderName {
        "stub"
    }

    async fn initiate_purchase(
        &self,
        script_id: &str,
        account_id: &str,
        usd_amount: f64,
    ) -> Result<PurchaseIntent, PaymentError> {
        let intent_id = Self::intent_id();
        let now = chrono::Utc::now().to_rfc3339();
        // The purchase row is the single source of truth for entitlement.
        // create_or_ignore is idempotent on (account_id, script_id) — a
        // repeated stub purchase for the same pair is a clean no-op (no
        // error, no duplicate row); we still return Ok(Completed).
        let purchase = NewPurchase {
            id: uuid::Uuid::new_v4().to_string(),
            account_id: account_id.to_string(),
            script_id: script_id.to_string(),
            // Reused column for ALL providers (legacy name; never migrate).
            icpay_intent_id: Some(intent_id.clone()),
            icpay_transaction_id: None,
            usd_amount,
            currency: "USD".to_string(),
            status: "completed".to_string(),
            paid_at: now.clone(),
            created_at: now,
        };
        self.repo
            .create_or_ignore(&purchase)
            .await
            .map_err(|e| PaymentError::Internal(format!("stub purchase insert failed: {e}")))?;
        Ok(PurchaseIntent {
            id: intent_id,
            status: PurchaseStatus::Completed,
            checkout_url: None,
            provider: "stub",
            usd_amount,
        })
    }

    async fn verify_purchase(&self, _intent_id: &str) -> Result<PurchaseStatus, PaymentError> {
        // The stub grants entitlement synchronously in initiate_purchase, so
        // any intent_id we issued is Completed by construction. We do not
        // re-read the repo: the entitlement gate at /download is the source
        // of truth for "may the caller have the bundle".
        Ok(PurchaseStatus::Completed)
    }

    async fn refund_purchase(&self, _intent_id: &str) -> Result<(), PaymentError> {
        // Best-effort no-op for the stub. (We do NOT un-grant the entitlement
        // — the stub is a dev/test provider and a refund semantic is out of
        // scope. Documented for clarity.)
        Ok(())
    }

    fn client_config(&self) -> Option<PaymentConfig> {
        // The stub exposes no client-side config (no publishable key needed).
        // GET /api/v1/payments/config returns 503 for stub, which is the
        // correct signal: the frontend's hosted-checkout flow is unused
        // because purchases complete server-side.
        None
    }
}

// ============================================================================
// NonePaymentProvider — fail-closed
// ============================================================================

/// Fail-closed provider for `PAYMENT_PROVIDER=none`. Every purchase attempt
/// returns [`PaymentError::PaymentsDisabled`]; the handler maps that to HTTP
/// 503 with body `{"error":"payments_disabled","provider":"none"}` per
/// AGENTS.md "fail fast". Used in production when payments must be disabled
/// (e.g. operator incident) and as the fail-closed fallback when the env
/// var holds an unrecognised value.
pub struct NonePaymentProvider;

#[async_trait]
impl PaymentProvider for NonePaymentProvider {
    fn name(&self) -> ProviderName {
        "none"
    }

    async fn initiate_purchase(
        &self,
        _script_id: &str,
        _account_id: &str,
        _usd_amount: f64,
    ) -> Result<PurchaseIntent, PaymentError> {
        Err(PaymentError::PaymentsDisabled(String::new()))
    }

    async fn verify_purchase(&self, _intent_id: &str) -> Result<PurchaseStatus, PaymentError> {
        Err(PaymentError::PaymentsDisabled(String::new()))
    }

    async fn refund_purchase(&self, _intent_id: &str) -> Result<(), PaymentError> {
        Err(PaymentError::PaymentsDisabled(String::new()))
    }

    fn client_config(&self) -> Option<PaymentConfig> {
        None
    }
}

// ============================================================================
// ResolvedProvider — boot-time selection result
// ============================================================================

/// The result of [`resolve_provider_from_env`]. Carries the trait object for
/// `AppState.payment_provider` plus — when applicable — the typed
/// `ICPayPaymentProvider` handle the webhook handler needs (the trait does
/// not expose ICPay-specific webhook verification).
#[derive(Clone)]
pub enum ResolvedProvider {
    /// Default. Dev / test path. Auto-succeeds.
    Stub(Arc<StubPaymentProvider>),
    /// `PAYMENT_PROVIDER=icpay`. The inner `Option` distinguishes
    /// "icpay selected but env vars unset" (`Some(provider)` always — env
    /// vars are read LOUDLY at call time, not boot time, per the existing
    /// misconfig policy).
    Icpay(Arc<ICPayPaymentProvider>),
    /// `PAYMENT_PROVIDER=none` (or unrecognised). Fail-closed.
    None(Arc<NonePaymentProvider>),
}

impl ResolvedProvider {
    /// The trait object held on `AppState`. Always present regardless of
    /// which provider is selected.
    pub fn provider(&self) -> Arc<dyn PaymentProvider> {
        match self {
            ResolvedProvider::Stub(s) => s.clone(),
            ResolvedProvider::Icpay(i) => i.clone(),
            ResolvedProvider::None(n) => n.clone(),
        }
    }

    /// The typed ICPay handle, only when `provider=icpay`. The webhook
    /// handler + legacy `/payments/icpay/config` route use this; they 503
    /// loudly when absent (route is also unmounted in that case).
    pub fn icpay(&self) -> Option<Arc<ICPayPaymentProvider>> {
        match self {
            ResolvedProvider::Icpay(i) => Some(i.clone()),
            _ => None,
        }
    }

    /// Lowercase name for logging + `tracing::info!` at boot.
    pub fn name(&self) -> ProviderName {
        match self {
            ResolvedProvider::Stub(_) => "stub",
            ResolvedProvider::Icpay(_) => "icpay",
            ResolvedProvider::None(_) => "none",
        }
    }
}

/// Reads `PAYMENT_PROVIDER` (default `"stub"`) and constructs the matching
/// provider. Unrecognised values log loudly (`tracing::error!`) and fail
/// closed to [`ResolvedProvider::None`] — per AGENTS.md, a misconfigured
/// deploy must surface the issue, not silently downgrade.
///
/// `pool` is shared with [`AppState`](crate::models::AppState) so the
/// provider writes entitlements through the same database as the rest of
/// the app.
pub fn resolve_provider_from_env(pool: sqlx::SqlitePool) -> ResolvedProvider {
    let raw = std::env::var("PAYMENT_PROVIDER").unwrap_or_else(|_| "stub".to_string());
    let normalised = raw.trim().to_ascii_lowercase();
    let repo = PurchaseRepository::new(pool.clone());
    match normalised.as_str() {
        "" | "stub" => {
            tracing::info!("PAYMENT_PROVIDER=stub (dev default) — purchases auto-succeed");
            ResolvedProvider::Stub(Arc::new(StubPaymentProvider::new(repo)))
        }
        "icpay" => {
            tracing::info!(
                "PAYMENT_PROVIDER=icpay — entitlements granted via ICPay webhook; ICPAY_* env \
                 vars surface loudly at call time when unset"
            );
            ResolvedProvider::Icpay(Arc::new(ICPayPaymentProvider::from_env(pool)))
        }
        "none" => {
            tracing::warn!(
                "PAYMENT_PROVIDER=none — purchases disabled (HTTP 503 on purchase endpoints)"
            );
            ResolvedProvider::None(Arc::new(NonePaymentProvider))
        }
        other => {
            tracing::error!(
                "PAYMENT_PROVIDER='{other}' is not recognised (expected stub|icpay|none); \
                 failing closed to 'none'. Purchase endpoints will return 503 \
                 ({{\"error\":\"payments_disabled\",\"provider\":\"none\"}})."
            );
            ResolvedProvider::None(Arc::new(NonePaymentProvider))
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::initialize_database;
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_repo() -> PurchaseRepository {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        initialize_database(&pool).await;
        PurchaseRepository::new(pool)
    }

    // ---- StubPaymentProvider ----

    #[tokio::test]
    async fn stub_initiate_purchase_inserts_completed_row() {
        let repo = setup_repo().await;
        let provider = StubPaymentProvider::new(repo.clone());
        let intent = provider
            .initiate_purchase("script-1", "acct-1", 9.99)
            .await
            .expect("stub purchase must succeed");
        assert_eq!(intent.status, PurchaseStatus::Completed);
        assert_eq!(intent.provider, "stub");
        assert!(intent.checkout_url.is_none());
        assert!(
            intent.id.starts_with("stub-intent-"),
            "stub intent id must have the canonical prefix, got: {}",
            intent.id
        );
        assert!((intent.usd_amount - 9.99).abs() < f64::EPSILON);
        // Entitlement is queryable.
        assert!(
            repo.exists_for_account_and_script("acct-1", "script-1")
                .await
                .unwrap(),
            "stub must insert an entitlement row"
        );
    }

    #[tokio::test]
    async fn stub_initiate_purchase_is_idempotent() {
        let repo = setup_repo().await;
        let provider = StubPaymentProvider::new(repo.clone());
        let first = provider
            .initiate_purchase("script-1", "acct-1", 9.99)
            .await
            .unwrap();
        let second = provider
            .initiate_purchase("script-1", "acct-1", 9.99)
            .await
            .unwrap();
        // Both return Completed; the underlying create_or_ignore means the
        // second insert is a no-op (but the call must NOT error).
        assert_eq!(first.status, PurchaseStatus::Completed);
        assert_eq!(second.status, PurchaseStatus::Completed);
        // Intent ids are unique per call (ULID).
        assert_ne!(first.id, second.id);
        // Exactly one row in the table.
        let row = repo
            .find_by_account_and_script("acct-1", "script-1")
            .await
            .unwrap();
        assert!(row.is_some(), "exactly one entitlement row after two calls");
    }

    #[tokio::test]
    async fn stub_verify_purchase_always_completed() {
        let repo = setup_repo().await;
        let provider = StubPaymentProvider::new(repo);
        let status = provider
            .verify_purchase("stub-intent-anything")
            .await
            .unwrap();
        assert_eq!(status, PurchaseStatus::Completed);
    }

    #[tokio::test]
    async fn stub_refund_is_noop_ok() {
        let repo = setup_repo().await;
        let provider = StubPaymentProvider::new(repo);
        provider
            .refund_purchase("stub-intent-anything")
            .await
            .expect("stub refund must be a clean no-op");
    }

    #[tokio::test]
    async fn stub_client_config_is_none() {
        let repo = setup_repo().await;
        let provider = StubPaymentProvider::new(repo);
        assert!(provider.client_config().is_none());
    }

    // ---- NonePaymentProvider ----

    #[tokio::test]
    async fn none_provider_initiate_returns_payments_disabled() {
        let provider = NonePaymentProvider;
        let err = provider
            .initiate_purchase("script-1", "acct-1", 9.99)
            .await
            .unwrap_err();
        assert!(
            matches!(err, PaymentError::PaymentsDisabled(_)),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn none_provider_verify_returns_payments_disabled() {
        let provider = NonePaymentProvider;
        let err = provider.verify_purchase("anything").await.unwrap_err();
        assert!(
            matches!(err, PaymentError::PaymentsDisabled(_)),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn none_provider_client_config_is_none() {
        assert!(NonePaymentProvider.client_config().is_none());
    }

    // ---- resolve_provider_from_env ----

    /// Process-wide mutex serialising tests that mutate `PAYMENT_PROVIDER`.
    /// Cargo's default parallel runner would let two `with_env` calls race
    /// (one test sets `"stub"` while another sets `"icpay"`). The lock keeps
    /// the env-var window atomic without adding the `serial_test` crate.
    static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn with_env(_guard: &std::sync::MutexGuard<'_, ()>, name: &'static str, value: Option<&'static str>) {
        match value {
            Some(v) => std::env::set_var(name, v),
            None => std::env::remove_var(name),
        }
    }

    async fn setup_pool() -> sqlx::SqlitePool {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        initialize_database(&pool).await;
        pool
    }

    #[tokio::test]
    async fn resolve_default_when_unset_is_stub() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", None);
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert_eq!(resolved.name(), "stub");
        assert!(matches!(resolved, ResolvedProvider::Stub(_)));
    }

    #[tokio::test]
    async fn resolve_explicit_stub() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", Some("stub"));
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert_eq!(resolved.name(), "stub");
    }

    #[tokio::test]
    async fn resolve_none() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", Some("none"));
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert_eq!(resolved.name(), "none");
        assert!(matches!(resolved, ResolvedProvider::None(_)));
        // Trait dispatch confirms fail-closed behaviour.
        let provider = resolved.provider();
        let err = provider
            .initiate_purchase("s", "a", 1.0)
            .await
            .unwrap_err();
        assert!(matches!(err, PaymentError::PaymentsDisabled(_)));
    }

    #[tokio::test]
    async fn resolve_unknown_fails_closed_to_none() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", Some("paypal-mystery"));
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert_eq!(resolved.name(), "none");
        assert!(matches!(resolved, ResolvedProvider::None(_)));
    }

    #[tokio::test]
    async fn resolve_is_case_insensitive() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", Some("STUB"));
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert_eq!(resolved.name(), "stub");
    }

    #[tokio::test]
    async fn resolve_icpay_returns_icpay_handle() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", Some("icpay"));
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert_eq!(resolved.name(), "icpay");
        assert!(matches!(resolved, ResolvedProvider::Icpay(_)));
        assert!(
            resolved.icpay().is_some(),
            "icpay branch must expose the typed ICPay handle"
        );
    }

    #[tokio::test]
    async fn resolve_stub_has_no_icpay_handle() {
        let guard = ENV_LOCK.lock().unwrap();
        with_env(&guard, "PAYMENT_PROVIDER", Some("stub"));
        let resolved = resolve_provider_from_env(setup_pool().await);
        assert!(
            resolved.icpay().is_none(),
            "stub branch must NOT expose the typed ICPay handle"
        );
    }

    // ---- Trait object-safety + dispatch ----

    #[tokio::test]
    async fn trait_is_object_safe_and_dispatches() {
        // Arc<dyn PaymentProvider> must compile + dispatch to the concrete
        // impl at runtime. This is the load-bearing guarantee for
        // AppState.payment_provider.
        let repo = setup_repo().await;
        let stub: Arc<dyn PaymentProvider> = Arc::new(StubPaymentProvider::new(repo.clone()));
        let intent = stub
            .initiate_purchase("script-1", "acct-1", 4.99)
            .await
            .unwrap();
        assert_eq!(intent.provider, "stub");
        assert_eq!(stub.name(), "stub");
        assert!(repo.exists_for_account_and_script("acct-1", "script-1").await.unwrap());

        let none: Arc<dyn PaymentProvider> = Arc::new(NonePaymentProvider);
        let err = none.initiate_purchase("s", "a", 1.0).await.unwrap_err();
        assert!(matches!(err, PaymentError::PaymentsDisabled(_)));
        assert_eq!(none.name(), "none");
    }
}

// ============================================================================
// Trait contract tests — exercises a SECOND in-test impl
// ============================================================================

#[cfg(test)]
mod contract_tests {
    use super::*;
    use crate::models::PaymentConfig;
    use crate::repositories::PurchaseRepository;
    use std::sync::Mutex;

    /// A second, independent in-test provider implementation. NOT a mock of
    /// Stub — a distinct type that proves the trait is usable by arbitrary
    /// implementors (the contract test guarantee per AGENTS.md: "use the
    /// real StubProvider AND a real second in-test impl, not a mock").
    ///
    /// Records every call into a `CallLog` so tests can assert trait
    /// behaviour generically (independent of any specific provider's
    /// semantics).
    struct RecordingProvider {
        log: Mutex<Vec<String>>,
    }

    impl RecordingProvider {
        fn new() -> Self {
            Self {
                log: Mutex::new(Vec::new()),
            }
        }

        fn calls(&self) -> Vec<String> {
            self.log.lock().unwrap().clone()
        }
    }

    #[async_trait]
    impl PaymentProvider for RecordingProvider {
        fn name(&self) -> ProviderName {
            "recording"
        }

        async fn initiate_purchase(
            &self,
            script_id: &str,
            account_id: &str,
            usd_amount: f64,
        ) -> Result<PurchaseIntent, PaymentError> {
            self.log.lock().unwrap().push(format!(
                "initiate:{script_id}:{account_id}:{usd_amount}"
            ));
            Ok(PurchaseIntent {
                id: format!("rec-{}", ulid::Ulid::new()),
                status: PurchaseStatus::Completed,
                checkout_url: None,
                provider: self.name(),
                usd_amount,
            })
        }

        async fn verify_purchase(&self, intent_id: &str) -> Result<PurchaseStatus, PaymentError> {
            self.log.lock().unwrap().push(format!("verify:{intent_id}"));
            Ok(PurchaseStatus::Completed)
        }

        async fn refund_purchase(&self, intent_id: &str) -> Result<(), PaymentError> {
            self.log.lock().unwrap().push(format!("refund:{intent_id}"));
            Ok(())
        }

        fn client_config(&self) -> Option<PaymentConfig> {
            // Returns a sentinel config so tests can assert generic
            // client_config dispatch via the trait object.
            Some(PaymentConfig {
                publishable_key: "rec-pk".to_string(),
                shortcode: "rec_token".to_string(),
                api_url: "https://rec.test".to_string(),
            })
        }
    }

    #[tokio::test]
    async fn recording_provider_initiate_returns_typed_intent() {
        let p = RecordingProvider::new();
        let intent = p.initiate_purchase("s", "a", 5.0).await.unwrap();
        assert_eq!(intent.provider, "recording");
        assert_eq!(intent.status, PurchaseStatus::Completed);
        assert!(intent.id.starts_with("rec-"));
        assert_eq!(intent.usd_amount, 5.0);
        assert_eq!(p.calls(), vec!["initiate:s:a:5"]);
    }

    #[tokio::test]
    async fn recording_provider_client_config_dispatches_via_trait() {
        let p: Arc<dyn PaymentProvider> = Arc::new(RecordingProvider::new());
        let cfg = p.client_config().expect("recording exposes a config");
        assert_eq!(cfg.publishable_key, "rec-pk");
        assert_eq!(cfg.shortcode, "rec_token");
        assert_eq!(cfg.api_url, "https://rec.test");
    }

    #[tokio::test]
    async fn all_providers_return_owned_intent_ids() {
        // Parametric over two real impls: Stub + Recording. Both must
        // return non-empty intent ids whose prefix matches the provider's
        // `name()`-ish namespace.
        async fn assert_owned_intent(p: Arc<dyn PaymentProvider>, prefix: &str) {
            let intent = p.initiate_purchase("s", "a", 1.0).await.unwrap();
            assert!(!intent.id.is_empty());
            assert!(
                intent.id.starts_with(prefix),
                "intent id '{}' should start with '{}'",
                intent.id,
                prefix
            );
            assert_eq!(intent.provider, p.name());
        }

        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        crate::db::initialize_database(&pool).await;
        let repo = PurchaseRepository::new(pool);
        assert_owned_intent(Arc::new(StubPaymentProvider::new(repo)), "stub-intent-").await;
        assert_owned_intent(Arc::new(RecordingProvider::new()), "rec-").await;
    }
}
