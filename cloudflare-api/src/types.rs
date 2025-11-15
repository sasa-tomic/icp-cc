use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use crate::utils::timestamp_format;

pub struct AppEnv {
    pub db: worker::D1Database,
    pub test_db: worker::D1Database,
    pub environment: String,
    pub test_db_name: Option<String>,
}

// Note: D1Database doesn't implement Clone or Copy
// We'll handle this by using references instead

// Implement conversion from worker::Env to our AppEnv
impl From<worker::Env> for AppEnv {
    fn from(env: worker::Env) -> Self {
        // For testing, always use TEST_DB binding
        // In production, this should be based on ENVIRONMENT variable
        let test_db_name = Some("icp-marketplace-test".to_string());

        Self {
            db: env.d1("DB").unwrap_or_else(|_| {
                // Fallback for environments without D1
                panic!("D1 database binding 'DB' not found in environment")
            }),
            test_db: env.d1("TEST_DB").unwrap_or_else(|_| {
                // Fallback for environments without TEST_DB
                panic!("D1 database binding 'TEST_DB' not found in environment")
            }),
            environment: "local".to_string(),
            test_db_name,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Script {
    pub id: String,
    pub title: String,
    pub description: String,
    pub category: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    pub lua_source: String,
    pub author_name: String,
    pub author_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_principal: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_public_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub upload_signature: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canister_ids: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub screenshots: Option<Vec<String>>,
    pub version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compatibility: Option<String>,
    pub price: f64,
    pub is_public: bool,
    pub downloads: i32,
    pub rating: f64,
    pub review_count: i32,
    #[serde(with = "time::serde::iso8601")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::iso8601")]
    pub updated_at: OffsetDateTime,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<Author>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reviews: Option<Vec<Review>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Author {
    pub id: String,
    pub username: String,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar: Option<String>,
    pub is_verified_developer: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    pub name: String,
    pub is_verified_developer: bool,
    #[serde(with = "time::serde::iso8601")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::iso8601")]
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Review {
    pub id: String,
    pub script_id: String,
    pub user_id: String,
    pub rating: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
    #[serde(with = "time::serde::iso8601")]
    pub created_at: OffsetDateTime,
    #[serde(with = "time::serde::iso8601")]
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Purchase {
    pub id: String,
    pub script_id: String,
    pub user_id: String,
    pub price: f64,
    #[serde(with = "time::serde::iso8601")]
    pub purchase_date: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T = serde_json::Value> {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginatedResponse<T> {
    #[serde(flatten)]
    pub api_response: ApiResponse<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub has_more: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignaturePayload {
    pub action: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub script_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lua_source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compatibility: Option<String>,
    pub author_principal: String,
    #[serde(with = "timestamp_format")]
    pub timestamp: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateScriptRequest {
    pub title: String,
    pub description: String,
    pub category: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    pub lua_source: String,
    pub author_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canister_ids: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub screenshots: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compatibility: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub price: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_public: Option<bool>,
    pub author_principal: String,
    pub author_public_key: String,
    pub signature: String,
    #[serde(with = "timestamp_format")]
    pub timestamp: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateScriptRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lua_source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canister_ids: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub screenshots: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compatibility: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub price: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_public: Option<bool>,
    pub author_principal: String,
    pub signature: String,
    #[serde(with = "timestamp_format")]
    pub timestamp: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteScriptRequest {
    pub author_principal: String,
    pub signature: String,
    #[serde(with = "timestamp_format")]
    pub timestamp: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub query: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canister_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub min_rating: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_price: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_by: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_public: Option<bool>,
}

// Query parameter structs for API endpoints
#[derive(Debug, Deserialize, Default)]
pub struct ScriptsQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    #[serde(rename = "public")]
    pub is_public: Option<bool>,
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
    pub order: Option<String>,
    #[serde(rename = "includePrivate")]
    pub include_private: Option<bool>,
}

#[derive(Debug, Deserialize, Default)]
pub struct SearchQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
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
    pub order: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
pub struct ReviewsQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

#[derive(Debug, Deserialize, Default)]
pub struct CategoryQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
    #[serde(rename = "sort_by")]
    pub sort_by: Option<String>,
    #[serde(rename = "sort_order")]
    pub sort_order: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CompatibleQueryParams {
    #[serde(rename = "canisterId")]
    pub canister_id: String,
}