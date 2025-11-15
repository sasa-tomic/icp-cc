use crate::types::*;
use worker::{console_log, Response, Result};
use sha2::{Digest, Sha256};
use base64::{Engine as _, engine::general_purpose};
use std::collections::BTreeMap;
use serde_json::Value;
use serde::{Deserialize, Deserializer, Serializer};
use serde::ser::Error as SerError;
use serde::de::Error as DeError;

pub mod timestamp_format {
    use super::*;
    use time::format_description::well_known::Rfc3339;
    use time::OffsetDateTime;
    use serde::{Deserialize, Deserializer, Serializer};
    use serde_json::Value;

    pub fn serialize<S>(date: &OffsetDateTime, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let s = date.format(&Rfc3339).map_err(SerError::custom)?;
        serializer.serialize_str(&s)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> std::result::Result<OffsetDateTime, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;

        let timestamp_str = match value {
            Value::String(s) => s,
            Value::Number(n) => n.to_string(),
            _ => return Err(DeError::custom("timestamp must be a string or number")),
        };

        // Try parsing as RFC3339 first
        if let Ok(dt) = OffsetDateTime::parse(&timestamp_str, &Rfc3339) {
            return Ok(dt);
        }

        // Try parsing as other common formats
        if let Ok(dt) = OffsetDateTime::parse(&timestamp_str, &time::format_description::well_known::Iso8601::PARSING) {
            return Ok(dt);
        }

        // If all else fails, try to parse as a Unix timestamp in milliseconds
        if let Ok(timestamp_ms) = timestamp_str.parse::<i64>() {
            // Check if it's in milliseconds (typical JavaScript timestamp)
            if timestamp_ms > 1_000_000_000_000 {
                // It's in milliseconds, convert to seconds
                if let Some(dt) = OffsetDateTime::from_unix_timestamp(timestamp_ms / 1000).ok() {
                    return Ok(dt);
                }
            } else {
                // It's already in seconds
                if let Some(dt) = OffsetDateTime::from_unix_timestamp(timestamp_ms).ok() {
                    return Ok(dt);
                }
            }
        }

        Err(DeError::custom(format!("Failed to parse timestamp: {}", timestamp_str)))
    }
}

pub struct SignatureVerifier;

impl SignatureVerifier {
    pub fn create_canonical_payload(payload: &SignaturePayload) -> String {
        let mut sorted_map = BTreeMap::new();

        // Add all fields to sorted map for deterministic ordering
        if let Some(script_id) = &payload.script_id {
            sorted_map.insert("script_id", Value::String(script_id.clone()));
        }
        if let Some(title) = &payload.title {
            sorted_map.insert("title", Value::String(title.clone()));
        }
        if let Some(description) = &payload.description {
            sorted_map.insert("description", Value::String(description.clone()));
        }
        if let Some(category) = &payload.category {
            sorted_map.insert("category", Value::String(category.clone()));
        }
        if let Some(lua_source) = &payload.lua_source {
            sorted_map.insert("lua_source", Value::String(lua_source.clone()));
        }
        if let Some(version) = &payload.version {
            sorted_map.insert("version", Value::String(version.clone()));
        }
        if let Some(tags) = &payload.tags {
            sorted_map.insert("tags", Value::Array(tags.iter().cloned().map(Value::String).collect()));
        }
        if let Some(compatibility) = &payload.compatibility {
            sorted_map.insert("compatibility", Value::String(compatibility.clone()));
        }

        sorted_map.insert("action", Value::String(payload.action.clone()));
        sorted_map.insert("author_principal", Value::String(payload.author_principal.clone()));
        sorted_map.insert("timestamp", Value::String(payload.timestamp.to_string()));

        serde_json::to_string(&sorted_map).unwrap_or_default()
    }

    pub fn generate_signature(payload: &SignaturePayload, secret_key: &str) -> String {
        let canonical_payload = Self::create_canonical_payload(payload);
        let mut hasher = Sha256::new();

        // Combine payload and secret key
        let combined = format!("{}|{}", canonical_payload, secret_key);
        hasher.update(combined.as_bytes());

        let result = hasher.finalize();
        general_purpose::STANDARD.encode(result)
    }

    pub fn verify_signature(
        signature: &str,
        payload: &SignaturePayload,
        public_key: &str,
    ) -> bool {
        let expected_signature = Self::generate_signature(payload, public_key);
        signature == expected_signature
    }
}

pub struct TestIdentity;

impl TestIdentity {
    const TEST_SECRET_KEY: &'static str = "test-secret-key-for-icp-compatibility";
    const TEST_PUBLIC_KEY: &'static str = "test-public-key-for-icp-compatibility";
    const TEST_PRINCIPAL: &'static str = "2vxsx-fae";

    pub fn get_secret_key() -> &'static str {
        Self::TEST_SECRET_KEY
    }

    pub fn get_public_key() -> &'static str {
        Self::TEST_PUBLIC_KEY
    }

    pub fn get_principal() -> &'static str {
        Self::TEST_PRINCIPAL
    }

    pub fn generate_test_signature(payload: &SignaturePayload) -> String {
        SignatureVerifier::generate_signature(payload, Self::get_secret_key())
    }
}

pub struct SignatureEnforcement;

impl SignatureEnforcement {
    pub async fn enforce_signature_verification(
        env: &AppEnv,
        signature: &str,
        payload: &SignaturePayload,
        public_key: &str,
    ) -> Result<bool> {
        // Allow test token bypass
        if signature == "test-auth-token" {
            console_log!("Using test-auth-token bypass for action: {}", payload.action);
            return Ok(true);
        }

        // Always require signature, author_principal, and public_key
        if signature.is_empty() || payload.author_principal.is_empty() || public_key.is_empty() {
            console_log!("Missing required signature fields: signature={}, author_principal={}, public_key={}",
                       !signature.is_empty(),
                       !payload.author_principal.is_empty(),
                       !public_key.is_empty());
            return Ok(false);
        }

        console_log!("Enforcing signature verification: action={}, environment={}, author_principal={}",
                    payload.action, env.environment, payload.author_principal);

        // For test environment, verify against test public key
        if public_key == TestIdentity::get_public_key() {
            let is_valid = SignatureVerifier::verify_signature(
                signature,
                payload,
                TestIdentity::get_secret_key(),
            );

            if !is_valid {
                console_log!("Test signature verification failed");
                return Ok(false);
            }

            console_log!("✅ Signature verification successful: action={}, author_principal={}",
                        payload.action, payload.author_principal);
            return Ok(true);
        }

        // For production, ICP signature verification would go here
        console_log!("Only test signatures are supported in this implementation");
        Ok(false)
    }

    pub fn create_signature_error_response() -> Response {
        JsonResponse::error(
            "Valid signature, author_principal, and author_public_key are required for all script operations. Use TestIdentity utilities in development/testing.",
            401,
        )
    }
}

pub struct CorsHandler;

impl CorsHandler {
    pub fn handle() -> Response {
        Response::empty()
            .map(|mut resp| {
                let headers = resp.headers_mut();
                let _ = headers.set("Access-Control-Allow-Origin", "*");
                let _ = headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
                let _ = headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
                resp
            })
            .unwrap_or_else(|_| Response::error("Failed to create CORS response", 500).unwrap())
    }

    pub fn add_headers(mut response: Response) -> Response {
        let headers = response.headers_mut();
        let _ = headers.set("Access-Control-Allow-Origin", "*");
        let _ = headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        let _ = headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        response
    }
}

pub struct JsonResponse;

impl JsonResponse {
    pub fn success<T: serde::Serialize>(data: T, _status: u16) -> Response {
        let api_response = ApiResponse {
            success: true,
            data: Some(data),
            error: None,
            details: None,
        };
        
        // Pass the STRUCT to from_json, not a JSON string
        match Response::from_json(&api_response) {
            Ok(response) => CorsHandler::add_headers(response),
            Err(_) => Response::error("Failed to serialize response", 500).unwrap(),
        }
    }

    pub fn error(message: &str, _status: u16) -> Response {
        let api_response: ApiResponse<()> = ApiResponse {
            success: false,
            data: None,
            error: Some(message.to_string()),
            details: None,
        };
        
        match Response::from_json(&api_response) {
            Ok(response) => CorsHandler::add_headers(response),
            Err(_) => Response::error("Failed to serialize error response", 500).unwrap(),
        }
    }

    pub fn error_with_details(message: &str, details: &str, _status: u16) -> Response {
        let api_response: ApiResponse<()> = ApiResponse {
            success: false,
            data: None,
            error: Some(message.to_string()),
            details: Some(details.to_string()),
        };
        
        match Response::from_json(&api_response) {
            Ok(response) => CorsHandler::add_headers(response),
            Err(_) => Response::error("Failed to serialize error response", 500).unwrap(),
        }
    }
}

pub struct DatabaseService<'a> {
    env: &'a AppEnv,
}

impl<'a> DatabaseService<'a> {
    pub fn new(env: &'a AppEnv) -> Self {
        Self { env }
    }

    pub fn get_database(&self) -> &worker::D1Database {
        // If TEST_DB_NAME is specified, use dynamic database selection
        if self.env.test_db_name.is_some() {
            console_log!("Using TEST_DB database (test_db_name: {:?})", self.env.test_db_name);
            &self.env.test_db
        } else {
            console_log!("Using PROD database (test_db_name: None)");
            &self.env.db
        }
    }

    pub async fn get_script_with_details(&self, script_id: &str, include_private: bool) -> Result<Option<Script>> {
        let db = self.get_database();

        let query = if include_private {
            "SELECT * FROM scripts WHERE id = ?1"
        } else {
            "SELECT * FROM scripts WHERE id = ?1 AND is_public = 1"
        };

        match db.prepare(query).bind(&[script_id.into()])?.first::<serde_json::Value>(None).await {
            Ok(Some(result)) => {
                // Convert database result to Script
                let script = self.json_value_to_script(&result).await?;
                Ok(Some(script))
            }
            Ok(None) => Ok(None),
            Err(e) => {
                console_log!("Error fetching script: {:?}", e);
                Ok(None)
            }
        }
    }

    pub async fn search_scripts(&self, params: &SearchParams) -> Result<(Vec<Script>, i32)> {
        let db = self.get_database();
        let mut where_conditions = vec![];
        let mut bindings = vec![];

        if params.is_public.unwrap_or(true) {
            where_conditions.push("is_public = 1".to_string());
        }

        if let Some(query) = &params.query {
            where_conditions.push("(title LIKE ?1 OR description LIKE ?2)".to_string());
            bindings.push(format!("%{}%", query));
            bindings.push(format!("%{}%", query));
        }

        if let Some(category) = &params.category {
            where_conditions.push("category = ?".to_string());
            bindings.push(category.clone());
        }

        if let Some(min_rating) = params.min_rating {
            where_conditions.push("rating >= ?".to_string());
            bindings.push(min_rating.to_string());
        }

        if let Some(max_price) = params.max_price {
            where_conditions.push("price <= ?".to_string());
            bindings.push(max_price.to_string());
        }

        let where_clause = where_conditions.join(" AND ");
        let sort_by = params.sort_by.as_deref().unwrap_or("created_at");
        let order = params.order.as_deref().unwrap_or("desc");
        let limit = params.limit.unwrap_or(20);
        let offset = params.offset.unwrap_or(0);

        // Get total count
        let count_query = format!("SELECT COUNT(*) as total FROM scripts WHERE {}", where_clause);
        let total = match db.prepare(&count_query)
            .bind(&bindings.iter().map(|b| b.clone().into()).collect::<Vec<_>>())?
            .first::<serde_json::Value>(None)
            .await
        {
            Ok(Some(result)) => result["total"].as_i64().unwrap_or(0) as i32,
            _ => 0,
        };

        // Get scripts
        let query = format!(
            "SELECT * FROM scripts WHERE {} ORDER BY {} {} LIMIT ? OFFSET ?",
            where_clause, sort_by, order.to_uppercase()
        );

        let mut query_bindings = bindings.iter().map(|b| b.clone().into()).collect::<Vec<_>>();
        query_bindings.push(limit.into());
        query_bindings.push(offset.into());

        let results = match db.prepare(&query)
            .bind(&query_bindings)?
            .all()
            .await
        {
            Ok(results) => results.results()?.to_vec(),
            Err(e) => {
                console_log!("Error searching scripts: {:?}", e);
                vec![]
            }
        };

        let scripts = futures::future::join_all(
            results.into_iter().map(|result| async move {
                self.json_value_to_script(&result).await.unwrap_or_else(|_| {
                    // Return a basic script if conversion fails
                    Script {
                        id: String::new(),
                        title: "Error".to_string(),
                        description: String::new(),
                        category: String::new(),
                        tags: None,
                        lua_source: String::new(),
                        author_name: String::new(),
                        author_id: String::new(),
                        author_principal: None,
                        author_public_key: None,
                        upload_signature: None,
                        canister_ids: None,
                        icon_url: None,
                        screenshots: None,
                        version: "1.0.0".to_string(),
                        compatibility: None,
                        price: 0.0,
                        is_public: false,
                        downloads: 0,
                        rating: 0.0,
                        review_count: 0,
                        created_at: time::OffsetDateTime::now_utc(),
                        updated_at: time::OffsetDateTime::now_utc(),
                        author: None,
                        reviews: None,
                    }
                })
            })
        ).await;

        Ok((scripts, total))
    }

    async fn json_value_to_script(&self, result: &serde_json::Value) -> Result<Script> {
        // Helper method to convert database JSON result to Script
        let script = Script {
            id: result.get("id").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            title: result.get("title").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            description: result.get("description").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            category: result.get("category").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            tags: result.get("tags").and_then(|v| v.as_array()).map(|arr| {
                arr.iter().filter_map(|v| v.as_str().map(String::from)).collect()
            }),
            lua_source: result.get("lua_source").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            author_name: result.get("author_name").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            author_id: result.get("author_id").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            author_principal: result.get("author_principal").and_then(|v| v.as_str()).map(String::from),
            author_public_key: result.get("author_public_key").and_then(|v| v.as_str()).map(String::from),
            upload_signature: result.get("upload_signature").and_then(|v| v.as_str()).map(String::from),
            canister_ids: result.get("canister_ids").and_then(|v| v.as_array()).map(|arr| {
                arr.iter().filter_map(|v| v.as_str().map(String::from)).collect()
            }),
            icon_url: result.get("icon_url").and_then(|v| v.as_str()).map(String::from),
            screenshots: result.get("screenshots").and_then(|v| v.as_array()).map(|arr| {
                arr.iter().filter_map(|v| v.as_str().map(String::from)).collect()
            }),
            version: result.get("version").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            compatibility: result.get("compatibility").and_then(|v| v.as_str()).map(String::from),
            price: result.get("price").and_then(|v| v.as_f64()).unwrap_or(0.0),
            is_public: result.get("is_public").and_then(|v| v.as_i64()).unwrap_or(0) != 0,
            downloads: result.get("downloads").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            rating: result.get("rating").and_then(|v| v.as_f64()).unwrap_or(0.0),
            review_count: result.get("review_count").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            // Parse timestamps from database, use fallback if parsing fails
            created_at: result.get("created_at")
                .and_then(|v| v.as_str())
                .and_then(|s| time::OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339).ok())
                .unwrap_or_else(time::OffsetDateTime::now_utc),
            updated_at: result.get("updated_at")
                .and_then(|v| v.as_str())
                .and_then(|s| time::OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339).ok())
                .unwrap_or_else(time::OffsetDateTime::now_utc),
            author: None, // Fetch separately
            reviews: None, // Fetch separately
        };

        Ok(script)
    }

    pub async fn generate_script_id(
        title: &str,
        description: &str,
        category: &str,
        lua_source: &str,
        author_name: &str,
        version: &str,
        timestamp: &str,
    ) -> Result<String> {
        let script_content = format!("{}|{}|{}|{}|{}|{}|{}", title, description, category, lua_source, author_name, version, timestamp);
        let mut hasher = Sha256::new();
        hasher.update(script_content.as_bytes());
        let result = hasher.finalize();
        Ok(result.iter().map(|b| format!("{:02x}", b)).collect())
    }
}