use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Script {
    pub id: String,
    pub title: String,
    pub description: String,
    pub category: String,
    pub tags: Option<String>,
    pub lua_source: String,
    pub author_name: String,
    pub author_id: String,
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
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Review {
    pub id: String,
    pub script_id: String,
    pub user_id: String,
    pub rating: i32,
    pub comment: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct IdentityProfile {
    pub id: String,
    pub principal: String,
    pub display_name: String,
    pub username: Option<String>,
    pub contact_email: Option<String>,
    pub contact_telegram: Option<String>,
    pub contact_twitter: Option<String>,
    pub contact_discord: Option<String>,
    pub website_url: Option<String>,
    pub bio: Option<String>,
    pub metadata: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
pub struct UpsertIdentityProfileRequest {
    pub principal: String,
    pub display_name: String,
    pub username: Option<String>,
    pub contact_email: Option<String>,
    pub contact_telegram: Option<String>,
    pub contact_twitter: Option<String>,
    pub contact_discord: Option<String>,
    pub website_url: Option<String>,
    pub bio: Option<String>,
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
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
    pub title: String,
    pub description: String,
    pub category: String,
    pub lua_source: String,
    pub author_name: String,
    pub author_id: Option<String>,
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
    pub lua_source: Option<String>,
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

#[derive(Debug, Deserialize)]
pub struct UpdateStatsRequest {
    #[serde(rename = "scriptId")]
    pub script_id: String,
    #[serde(rename = "incrementDownloads")]
    pub increment_downloads: Option<i32>,
}

pub struct AppState {
    pub pool: sqlx::SqlitePool,
    pub account_service: crate::services::AccountService,
    pub script_service: crate::services::ScriptService,
    pub review_service: crate::services::ReviewService,
    pub identity_service: crate::services::IdentityService,
}

#[derive(Debug, Deserialize)]
pub struct ReviewsQuery {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

pub const SCRIPT_COLUMNS: &str = "id, title, description, category, tags, lua_source, author_name, author_id, author_principal, author_public_key, upload_signature, canister_ids, icon_url, screenshots, version, compatibility, price, is_public, downloads, rating, review_count, created_at, updated_at";

// Account Profiles Models

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
pub struct Account {
    pub id: String,
    pub username: String,
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
    pub created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub public_keys: Vec<AccountPublicKeyResponse>,
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
