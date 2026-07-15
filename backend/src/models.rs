use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Script {
    pub id: String,
    pub slug: String,
    pub owner_account_id: Option<String>,
    pub title: String,
    pub description: String,
    pub category: String,
    pub tags: Option<String>,
    pub bundle: String,
    pub author_principal: Option<String>,
    pub author_public_key: Option<String>,
    pub upload_signature: Option<String>,
    pub canister_ids: Option<String>,
    pub icon_url: Option<String>,
    pub screenshots: Option<String>,
    pub version: String,
    pub compatibility: Option<String>,
    pub price: f64,
    pub is_public: bool,
    pub downloads: i32,
    pub rating: f64,
    pub review_count: i32,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    // Author info comes from JOIN with accounts table
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_name: Option<String>,
}

/// Browse-list serialization of `&[Script]` that OMITS the heavyweight
/// `bundle` field from every item (IH-5, UXR-3).
///
/// The marketplace LIST endpoints (`/scripts`, `/scripts/featured`,
/// `/scripts/trending`, `/scripts/category/:c`, `/scripts/compatible`,
/// `/scripts/search`) only need metadata to render browse tiles; the full
/// source ships separately via `GET /scripts/:id`, the capped `/preview`, or
/// the signed `/download`.
///
/// This does NOT weaken the paid-script entitlement gate: those LIST endpoints
/// never carried an entitlement decision in the first place (they returned the
/// full bundle to EVERY caller), so dropping it entirely only tightens the
/// contract. The gate itself still lives in `GET /scripts/:id` via
/// `ScriptDetailResponse::entitled` / `::locked`.
///
/// Every non-`bundle` field is preserved verbatim — adding a column to
/// `Script` flows through automatically, so this view can never drift from
/// the model.
pub fn scripts_to_list_json(scripts: &[Script]) -> serde_json::Value {
    let mut value = serde_json::to_value(scripts)
        .expect("Script derives Serialize over plain JSON scalars; serialization is infallible");
    if let Some(arr) = value.as_array_mut() {
        for item in arr.iter_mut() {
            if let Some(obj) = item.as_object_mut() {
                obj.remove("bundle");
            }
        }
    }
    value
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Review {
    pub id: String,
    pub script_id: String,
    pub user_id: String,
    pub rating: i32,
    pub comment: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
pub struct ScriptsQuery {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    pub category: Option<String>,
    #[serde(rename = "includePrivate")]
    pub include_private: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct CreateScriptRequest {
    pub slug: String,
    pub title: String,
    pub description: String,
    pub category: String,
    pub bundle: String,
    pub author_principal: Option<String>,
    pub author_public_key: Option<String>,
    pub upload_signature: Option<String>,
    pub signature: Option<String>,
    pub timestamp: Option<String>,
    pub version: Option<String>,
    pub price: Option<f64>,
    pub is_public: Option<bool>,
    pub compatibility: Option<String>,
    pub tags: Option<Vec<String>>,
    pub action: Option<String>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct UpdateScriptRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    pub category: Option<String>,
    pub bundle: Option<String>,
    pub version: Option<String>,
    pub price: Option<f64>,
    pub is_public: Option<bool>,
    pub tags: Option<Vec<String>>,
    pub signature: Option<String>,
    pub timestamp: Option<String>,
    pub script_id: Option<String>,
    pub author_principal: Option<String>,
    pub author_public_key: Option<String>,
    pub action: Option<String>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct DeleteScriptRequest {
    pub script_id: Option<String>,
    pub author_principal: Option<String>,
    pub author_public_key: Option<String>,
    pub signature: Option<String>,
    pub timestamp: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
pub struct SearchRequest {
    #[serde(rename = "query")]
    pub query: Option<String>,
    pub category: Option<String>,
    #[serde(rename = "canisterId")]
    pub canister_id: Option<String>,
    #[serde(rename = "minRating")]
    pub min_rating: Option<f64>,
    #[serde(rename = "maxPrice")]
    pub max_price: Option<f64>,
    #[serde(rename = "sortBy")]
    pub sort_by: Option<String>,
    #[serde(rename = "order")]
    pub sort_order: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Debug)]
pub struct SearchResultPayload {
    pub scripts: Vec<Script>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}

#[derive(Debug, Deserialize)]
pub struct CreateReviewRequest {
    #[serde(rename = "userId")]
    pub user_id: String,
    pub rating: i32,
    pub comment: Option<String>,
}

pub struct AppState {
    pub pool: sqlx::SqlitePool,
    pub account_service: crate::services::AccountService,
    pub script_service: crate::services::ScriptService,
    pub review_service: crate::services::ReviewService,
    pub passkey_service: crate::services::PasskeyService,
    pub purchase_repo: crate::repositories::PurchaseRepository,
    pub payment_service: crate::services::PaymentService,
    /// Sliding-window throttle for the open `POST /recovery/verify` brute-force
    /// oracle (W7-14). Shared across all requests (process-local).
    pub recovery_rate_limiter: std::sync::Arc<crate::rate_limit::SlidingWindowRateLimiter>,
}

#[derive(Debug, Deserialize)]
pub struct ReviewsQuery {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

pub const SCRIPT_COLUMNS_WITH_ACCOUNT: &str = "scripts.id, scripts.slug, scripts.owner_account_id, scripts.title, scripts.description, scripts.category, scripts.tags, scripts.bundle, scripts.author_principal, scripts.author_public_key, scripts.upload_signature, scripts.canister_ids, scripts.icon_url, scripts.screenshots, scripts.version, scripts.compatibility, scripts.price, scripts.is_public, scripts.downloads, scripts.rating, scripts.review_count, scripts.created_at, scripts.updated_at, scripts.deleted_at, accounts.display_name as author_name";

/// Lightweight browse-time preview of a script (UX-6).
///
/// Returned by `GET /api/v1/scripts/:id/preview`. Deliberately omits the full
/// `bundle`: the preview carries only a server-side-capped excerpt (`preview`)
/// plus the browse-relevant metadata, so opening the Script Details dialog no
/// longer ships the full source over the wire — and, for paid scripts, NEVER
/// ships the paid source. The cap is `FREE_PREVIEW_LINES` for free scripts and
/// the smaller `PAID_PREVIEW_LINES` for paid scripts (see `ScriptService`).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScriptPreview {
    pub id: String,
    pub description: String,
    pub version: String,
    pub price: f64,
    /// Source language of the bundle. The runtime is TypeScript-on-QuickJS for
    /// every script (see AGENTS.md), so this is currently always "typescript".
    pub language: String,
    /// First N lines of the source bundle, joined with `\n`. N is
    /// `FREE_PREVIEW_LINES` (free) or `PAID_PREVIEW_LINES` (paid).
    pub preview: String,
    pub preview_truncated: bool,
    /// Total line count of the underlying bundle — harmless metadata (like a
    /// book's page count) that lets the UI show "first 20 of N lines". Never
    /// reveals the source content itself.
    pub total_lines: usize,
}

// ============================================================================
// ICPay payment integration + paid-script entitlement gate
// ============================================================================

/// A row from the `purchases` table — a successful ICPay payment that granted
/// `account_id` entitlement to `script_id`'s paid bundle. Mirrors the schema in
/// `migrations/006_create_purchases_sqlite.sql`.
#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct Purchase {
    pub id: String,
    pub account_id: String,
    pub script_id: String,
    pub icpay_intent_id: Option<String>,
    pub icpay_transaction_id: Option<String>,
    pub usd_amount: f64,
    pub currency: String,
    pub status: String,
    pub paid_at: String,
    pub created_at: String,
}

/// Insert shape for the purchases table. The repository's `create_or_ignore`
/// takes this by reference.
#[derive(Debug, Clone)]
pub struct NewPurchase {
    pub id: String,
    pub account_id: String,
    pub script_id: String,
    pub icpay_intent_id: Option<String>,
    pub icpay_transaction_id: Option<String>,
    pub usd_amount: f64,
    pub currency: String,
    pub status: String,
    pub paid_at: String,
    pub created_at: String,
}

/// Request body for `POST /api/v1/scripts/:id/entitlement` (W7-2). The caller
/// signs the canonical payload `{action:"entitlement", id:<script_id>,
/// nonce:<nonce>, ts:<timestamp>}` with the Ed25519 (or secp256k1) key whose
/// public half appears in `author_public_key`. The server resolves the
/// caller's `account_id` from that public key (NEVER trusts a client-supplied
/// account id) and returns `{purchased: bool, owns: bool}` so the frontend can
/// drive the Buy/Download CTA without leaking the paid bundle.
///
/// Field names are snake_case on the wire, matching the existing signed-request
/// convention (`CreateScriptRequest`, `DeleteScriptRequest`, …).
#[derive(Debug, Deserialize)]
pub struct EntitlementRequest {
    pub signature: String,
    pub author_public_key: String,
    pub author_principal: String,
    /// Unix seconds. Must be within the replay-prevention window (±5 min).
    pub timestamp: i64,
    pub nonce: String,
}

/// Public ICPay client config (browser-safe). Returned by
/// `GET /api/v1/payments/icpay/config`. `publishable_key` ships in the client;
/// the secret key never leaves the server.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PaymentConfig {
    pub publishable_key: String,
    pub shortcode: String,
    pub api_url: String,
}

/// Metadata block embedded by the client in the ICPay payment intent. The
/// webhook uses these fields to credit the right account + script.
#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct WebhookMetadata {
    pub account_id: Option<String>,
    pub script_id: Option<String>,
    pub intent_id: Option<String>,
}

/// A parsed ICPay webhook event. Field names accept the camelCase shapes
/// documented in the ICPay HTTP contract (see `payment_service::verify_webhook`
/// for the raw-JSON parse; the signature is verified against the raw body
/// before this struct is deserialised).
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WebhookEvent {
    /// ICPay transaction identifier (also accepted as `id` when `transaction_id` is absent).
    #[serde(default)]
    pub transaction_id: Option<String>,
    /// Fallback id field — some ICPay payloads identify the transaction with `id`.
    #[serde(default, rename = "id")]
    pub id: Option<String>,
    /// Payment status from ICPay. The service treats `completed` / `succeeded`
    /// / `paid` (case-insensitive) as success.
    #[serde(default)]
    pub status: Option<String>,
    /// USD amount paid. Optional: recorded for audit but not gated on.
    #[serde(default)]
    pub usd_amount: Option<f64>,
    /// Embedded client metadata (account_id, script_id, intent_id).
    #[serde(default)]
    pub metadata: WebhookMetadata,
}

impl WebhookEvent {
    /// Resolves the canonical transaction id for storage. Prefers the explicit
    /// `transaction_id` field, falling back to the bare `id`.
    pub fn resolve_transaction_id(&self) -> Option<&str> {
        self.transaction_id.as_deref().or(self.id.as_deref())
    }
}

/// Request body for `POST /api/v1/scripts/:id/download`. The signature is
/// Ed25519 over the canonical string `download:{script_id}:{timestamp}:{nonce}`
/// (built in `entitlement::resolve_download`), verified with
/// `auth::verify_ed25519_signature`. Field names are snake_case on the wire.
#[derive(Debug, Deserialize)]
pub struct DownloadRequest {
    pub public_key: String,
    pub signature: String,
    pub timestamp: String,
    pub nonce: String,
}

/// The serialisable shape returned by `GET /api/v1/scripts/:id`.
///
/// This is the entitlement-gated view of a `Script`. It mirrors `Script`'s
/// fields but:
/// - makes `bundle` an `Option<String>` (set to `None` for paid scripts the
///   caller is not entitled to, so the JSON renders `"bundle": null`);
/// - adds `purchased: bool` so the UI knows whether to render a Buy CTA.
///
/// Field names stay snake_case to match the existing `Script` serialization
/// (backward-compatible for the free-script case, where `bundle` is `Some(..)`
/// and `purchased` is `true`).
#[derive(Debug, Serialize)]
pub struct ScriptDetailResponse {
    pub id: String,
    pub slug: String,
    pub owner_account_id: Option<String>,
    pub title: String,
    pub description: String,
    pub category: String,
    pub tags: Option<String>,
    /// Full source. `None` (→ JSON `null`) when the caller is not entitled to a
    /// paid script.
    pub bundle: Option<String>,
    /// Source language DETECTED from the bundle content (UXR5-2). Single
    /// source: `ScriptLanguage::detect`. Always present — even for locked
    /// paid scripts, since detection runs in-process before the bundle is
    /// gated. `"typescript"` / `"lua"` (stale) / `"unknown"`.
    pub language: String,
    pub author_principal: Option<String>,
    pub author_public_key: Option<String>,
    pub upload_signature: Option<String>,
    pub canister_ids: Option<String>,
    pub icon_url: Option<String>,
    pub screenshots: Option<String>,
    pub version: String,
    pub compatibility: Option<String>,
    pub price: f64,
    pub is_public: bool,
    pub downloads: i32,
    pub rating: f64,
    pub review_count: i32,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub author_name: Option<String>,
    /// `true` when the caller is entitled to the full bundle (free script,
    /// paid + purchase record, or paid + owner).
    pub purchased: bool,
}

impl ScriptDetailResponse {
    /// Build an *entitled* view: full bundle present, `purchased: true`. Used
    /// for free scripts, owners, and accounts with a purchase record.
    pub fn entitled(script: Script) -> Self {
        Self::from_script(script, true, true)
    }

    /// Build a *locked* view for a paid script the caller may NOT access:
    /// bundle set to `None` (→ `null`), `purchased: false`. Metadata (price,
    /// description, etc.) is preserved so the UI can render the Buy CTA.
    pub fn locked(script: Script) -> Self {
        Self::from_script(script, false, false)
    }

    fn from_script(script: Script, purchased: bool, include_bundle: bool) -> Self {
        // UXR5-2: detect the language from the bundle CONTENT before the bundle
        // is moved/gated. Single source: `ScriptLanguage::detect`. The badge
        // reflects real content even for locked paid scripts (whose `bundle`
        // field is dropped below — the language still ships honestly).
        let language = crate::script_language::ScriptLanguage::detect(&script.bundle)
            .as_str()
            .to_string();
        let bundle = if include_bundle {
            Some(script.bundle)
        } else {
            None
        };
        Self {
            id: script.id,
            slug: script.slug,
            owner_account_id: script.owner_account_id,
            title: script.title,
            description: script.description,
            category: script.category,
            tags: script.tags,
            bundle,
            language,
            author_principal: script.author_principal,
            author_public_key: script.author_public_key,
            upload_signature: script.upload_signature,
            canister_ids: script.canister_ids,
            icon_url: script.icon_url,
            screenshots: script.screenshots,
            version: script.version,
            compatibility: script.compatibility,
            price: script.price,
            is_public: script.is_public,
            downloads: script.downloads,
            rating: script.rating,
            review_count: script.review_count,
            created_at: script.created_at,
            updated_at: script.updated_at,
            deleted_at: script.deleted_at,
            author_name: script.author_name,
            purchased,
        }
    }
}

// Account Profiles Models

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct Account {
    pub id: String,
    pub username: String,
    pub display_name: String,
    pub contact_email: Option<String>,
    pub contact_telegram: Option<String>,
    pub contact_twitter: Option<String>,
    pub contact_discord: Option<String>,
    pub website_url: Option<String>,
    pub bio: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct AccountPublicKey {
    pub id: String,
    pub account_id: String,
    pub public_key: String,
    pub ic_principal: String,
    pub is_active: bool,
    pub added_at: String,
    pub disabled_at: Option<String>,
    pub disabled_by_key_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
#[allow(dead_code)]
pub struct SignatureAudit {
    pub id: String,
    pub account_id: Option<String>,
    pub action: String,
    pub payload: String,
    pub signature: String,
    pub public_key: String,
    pub timestamp: i64,
    pub nonce: String,
    pub is_admin_action: bool,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterAccountRequest {
    pub username: String,
    pub display_name: String,
    pub contact_email: Option<String>,
    pub contact_telegram: Option<String>,
    pub contact_twitter: Option<String>,
    pub contact_discord: Option<String>,
    pub website_url: Option<String>,
    pub bio: Option<String>,
    pub public_key: String,
    pub timestamp: i64,
    pub nonce: String,
    pub signature: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddPublicKeyRequest {
    pub new_public_key: String,
    pub signing_public_key: String,
    pub timestamp: i64,
    pub nonce: String,
    pub signature: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemovePublicKeyRequest {
    pub signing_public_key: String,
    pub timestamp: i64,
    pub nonce: String,
    pub signature: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateAccountRequest {
    pub display_name: Option<String>,
    pub contact_email: Option<String>,
    pub contact_telegram: Option<String>,
    pub contact_twitter: Option<String>,
    pub contact_discord: Option<String>,
    pub website_url: Option<String>,
    pub bio: Option<String>,
    pub signing_public_key: String,
    pub timestamp: i64,
    pub nonce: String,
    pub signature: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountPublicKeyResponse {
    pub id: String,
    pub public_key: String,
    pub ic_principal: String,
    pub added_at: String,
    pub is_active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disabled_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disabled_by_key_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountResponse {
    pub id: String,
    pub username: String,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_email: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_telegram: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_twitter: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_discord: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub website_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bio: Option<String>,
    pub created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub public_keys: Vec<AccountPublicKeyResponse>,
}

// Admin operation request models
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminDisableKeyRequest {
    pub reason: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminAddRecoveryKeyRequest {
    pub public_key: String,
    pub reason: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminKeyResponse {
    pub id: String,
    pub public_key: String,
    pub ic_principal: String,
    pub is_active: bool,
    pub disabled_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disabled_by_admin: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub added_by_admin: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub added_at: Option<String>,
}

// Implement AuthenticatedRequest trait for request types
use crate::middleware::AuthenticatedRequest;

impl AuthenticatedRequest for CreateScriptRequest {
    fn signature(&self) -> Option<&str> {
        self.signature.as_deref()
    }

    fn author_principal(&self) -> Option<&str> {
        self.author_principal.as_deref()
    }

    fn author_public_key(&self) -> Option<&str> {
        self.author_public_key.as_deref()
    }
}

impl AuthenticatedRequest for UpdateScriptRequest {
    fn signature(&self) -> Option<&str> {
        self.signature.as_deref()
    }

    fn author_principal(&self) -> Option<&str> {
        self.author_principal.as_deref()
    }

    fn author_public_key(&self) -> Option<&str> {
        self.author_public_key.as_deref()
    }
}

impl AuthenticatedRequest for DeleteScriptRequest {
    fn signature(&self) -> Option<&str> {
        self.signature.as_deref()
    }

    fn author_principal(&self) -> Option<&str> {
        self.author_principal.as_deref()
    }

    fn author_public_key(&self) -> Option<&str> {
        self.author_public_key.as_deref()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXPECTED_SCRIPT_FIELDS: &[&str] = &[
        "id",
        "slug",
        "owner_account_id",
        "title",
        "description",
        "category",
        "tags",
        "bundle",
        "author_principal",
        "author_public_key",
        "upload_signature",
        "canister_ids",
        "icon_url",
        "screenshots",
        "version",
        "compatibility",
        "price",
        "is_public",
        "downloads",
        "rating",
        "review_count",
        "created_at",
        "updated_at",
        "deleted_at",
        "author_name",
    ];

    fn column_field_name(col: &str) -> &str {
        let col = col.trim();
        if let Some((_, alias)) = col.rsplit_once(" as ") {
            return alias.trim();
        }
        col.rsplit_once('.')
            .map(|(_, name)| name)
            .unwrap_or(col)
            .trim()
    }

    #[test]
    fn script_columns_with_account_match_struct_fields() {
        let parsed: Vec<&str> = SCRIPT_COLUMNS_WITH_ACCOUNT
            .split(',')
            .map(column_field_name)
            .collect();
        assert_eq!(
            parsed, EXPECTED_SCRIPT_FIELDS,
            "SCRIPT_COLUMNS_WITH_ACCOUNT drifted from struct Script. Update both the column \
             string and the struct in lockstep (including the accounts.* JOIN alias for \
             author_name)."
        );
    }

    #[test]
    fn column_field_name_parses_table_prefixed_and_aliased() {
        assert_eq!(column_field_name("scripts.id"), "id");
        assert_eq!(column_field_name(" scripts.bundle "), "bundle");
        assert_eq!(
            column_field_name("accounts.display_name as author_name"),
            "author_name"
        );
    }

    /// Locks the `Review` JSON contract to camelCase (QS-1b, UXR7-1 regression).
    ///
    /// The Flutter `ScriptReview.fromJson` reads camelCase keys (`userId`,
    /// `scriptId`, `createdAt`, `updatedAt`). When `Review` lacked
    /// `#[serde(rename_all = "camelCase")]`, serde emitted snake_case, so
    /// `json['userId']` was `null` and the Reviews tab crashed with
    /// `type 'Null' is not a subtype of type 'String' in type cast`. This test
    /// pins EVERY serialized key so the contract can never silently drift again.
    #[test]
    fn review_serializes_to_camel_case_keys() {
        let review = Review {
            id: "rev-1".to_string(),
            script_id: "script-1".to_string(),
            user_id: "user-1".to_string(),
            rating: 5,
            comment: Some("great".to_string()),
            created_at: "2025-01-01T00:00:00Z".to_string(),
            updated_at: "2025-01-02T00:00:00Z".to_string(),
        };
        let json = serde_json::to_value(&review).expect("Review must serialize");
        let obj = json.as_object().expect("Review must serialize to an object");

        // Every key the Flutter frontend reads must be present and camelCase.
        for key in ["id", "userId", "scriptId", "rating", "comment", "createdAt", "updatedAt"] {
            assert!(
                obj.contains_key(key),
                "Review JSON missing camelCase key `{key}` — got keys: {:?}",
                obj.keys().collect::<Vec<_>>()
            );
        }
        // And the snake_case shapes that caused the crash must NOT leak out.
        for stale in ["script_id", "user_id", "created_at", "updated_at"] {
            assert!(
                !obj.contains_key(stale),
                "Review JSON leaked snake_case key `{stale}` (frontend reads camelCase)"
            );
        }
        // Round-trip: the camelCase payload must deserialize back into a Review.
        let round_trip: Review =
            serde_json::from_value(json).expect("camelCase Review JSON must round-trip");
        assert_eq!(round_trip.id, "rev-1");
        assert_eq!(round_trip.user_id, "user-1");
    }

    /// `comment: None` must render as JSON `null` (not be skipped) — the Flutter
    /// model reads it as `String?` and tolerates null. This pins the null shape.
    #[test]
    fn review_serializes_null_comment() {
        let review = Review {
            id: "rev-2".to_string(),
            script_id: "script-1".to_string(),
            user_id: "user-1".to_string(),
            rating: 4,
            comment: None,
            created_at: "2025-01-01T00:00:00Z".to_string(),
            updated_at: "2025-01-02T00:00:00Z".to_string(),
        };
        let json = serde_json::to_value(&review).unwrap();
        assert!(json.get("comment").is_some(), "comment key must be present");
        assert!(json["comment"].is_null(), "None comment must serialize to null");
    }
}
