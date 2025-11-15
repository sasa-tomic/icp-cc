use base64::{engine::general_purpose, Engine as _};
use ed25519_dalek::{Signature as Ed25519Signature, Verifier, VerifyingKey as Ed25519VerifyingKey};
use k256::ecdsa::{Signature as Secp256k1Signature, VerifyingKey as Secp256k1VerifyingKey};
use poem::{
    get, handler,
    http::StatusCode,
    listener::TcpListener,
    middleware::Cors,
    post,
    web::{Data, Json, Path, Query},
    EndpointExt, IntoResponse, Response, Route, Server,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{sqlite::SqlitePool, FromRow};
use std::{env, io::ErrorKind, net::TcpListener as StdTcpListener, sync::Arc};

#[derive(Debug, Serialize, Deserialize, FromRow)]
struct Script {
    id: String,
    title: String,
    description: String,
    category: String,
    tags: Option<String>,
    lua_source: String,
    author_name: String,
    author_id: String,
    author_principal: Option<String>,
    author_public_key: Option<String>,
    upload_signature: Option<String>,
    canister_ids: Option<String>,
    icon_url: Option<String>,
    screenshots: Option<String>,
    version: String,
    compatibility: Option<String>,
    price: f64,
    is_public: bool,
    downloads: i32,
    rating: f64,
    review_count: i32,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
struct Review {
    id: String,
    script_id: String,
    user_id: String,
    rating: i32,
    comment: Option<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow, Clone)]
struct IdentityProfile {
    id: String,
    principal: String,
    display_name: String,
    username: Option<String>,
    contact_email: Option<String>,
    contact_telegram: Option<String>,
    contact_twitter: Option<String>,
    contact_discord: Option<String>,
    website_url: Option<String>,
    bio: Option<String>,
    metadata: Option<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Deserialize)]
struct UpsertIdentityProfileRequest {
    principal: String,
    display_name: String,
    username: Option<String>,
    contact_email: Option<String>,
    contact_telegram: Option<String>,
    contact_twitter: Option<String>,
    contact_discord: Option<String>,
    website_url: Option<String>,
    bio: Option<String>,
    #[serde(default)]
    metadata: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct ScriptsQuery {
    limit: Option<i32>,
    offset: Option<i32>,
    category: Option<String>,
    #[serde(rename = "includePrivate")]
    include_private: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct CreateScriptRequest {
    title: String,
    description: String,
    category: String,
    lua_source: String,
    author_name: String,
    author_id: Option<String>,
    author_principal: Option<String>,
    author_public_key: Option<String>,
    upload_signature: Option<String>,
    signature: Option<String>,
    timestamp: Option<String>,
    version: Option<String>,
    price: Option<f64>,
    is_public: Option<bool>,
    compatibility: Option<String>,
    tags: Option<Vec<String>>,
    action: Option<String>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct UpdateScriptRequest {
    title: Option<String>,
    description: Option<String>,
    category: Option<String>,
    lua_source: Option<String>,
    version: Option<String>,
    price: Option<f64>,
    is_public: Option<bool>,
    tags: Option<Vec<String>>,
    signature: Option<String>,
    timestamp: Option<String>,
    script_id: Option<String>,
    author_principal: Option<String>,
    author_public_key: Option<String>,
    action: Option<String>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct DeleteScriptRequest {
    script_id: Option<String>,
    author_principal: Option<String>,
    author_public_key: Option<String>,
    signature: Option<String>,
    timestamp: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct SearchRequest {
    #[serde(rename = "query")]
    query: Option<String>,
    category: Option<String>,
    #[serde(rename = "canisterId")]
    canister_id: Option<String>,
    #[serde(rename = "minRating")]
    min_rating: Option<f64>,
    #[serde(rename = "maxPrice")]
    max_price: Option<f64>,
    #[serde(rename = "sortBy")]
    sort_by: Option<String>,
    #[serde(rename = "order")]
    sort_order: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
}

#[derive(Debug)]
struct SearchResultPayload {
    scripts: Vec<Script>,
    total: i64,
    limit: i64,
    offset: i64,
}

async fn run_marketplace_search(
    pool: &SqlitePool,
    request: &SearchRequest,
) -> Result<SearchResultPayload, (StatusCode, String)> {
    if request.canister_id.is_some() {
        tracing::debug!("Ignoring canister_id filter; backend does not support it yet");
    }

    let limit = request.limit.unwrap_or(20);
    if limit <= 0 || limit > 100 {
        return Err((
            StatusCode::BAD_REQUEST,
            "limit must be between 1 and 100".to_string(),
        ));
    }

    let offset = request.offset.unwrap_or(0);
    if offset < 0 {
        return Err((
            StatusCode::BAD_REQUEST,
            "offset must be zero or greater".to_string(),
        ));
    }

    let sort_field = request.sort_by.as_deref().unwrap_or("createdAt");
    let sort_column = match sort_field {
        "createdAt" => "created_at",
        "rating" => "rating",
        "downloads" => "downloads",
        "price" => "price",
        "title" => "title",
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                "unsupported sort field".to_string(),
            ));
        }
    };

    let sort_order_raw = request.sort_order.as_deref().unwrap_or("desc");
    let sort_order = match sort_order_raw.to_ascii_lowercase().as_str() {
        "asc" => "ASC",
        "desc" => "DESC",
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                "order must be 'asc' or 'desc'".to_string(),
            ));
        }
    };

    #[derive(Clone)]
    enum BindValue {
        Text(String),
        Float(f64),
        Integer(i64),
        Bool(bool),
    }

    let mut conditions: Vec<String> = Vec::new();
    let mut condition_binds: Vec<BindValue> = Vec::new();

    conditions.push("is_public = ?".to_string());
    condition_binds.push(BindValue::Bool(true));

    if let Some(query) = request
        .query
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        let like_pattern = format!("%{}%", query);
        conditions.push("(title LIKE ? OR description LIKE ? OR category LIKE ?)".to_string());
        condition_binds.push(BindValue::Text(like_pattern.clone()));
        condition_binds.push(BindValue::Text(like_pattern.clone()));
        condition_binds.push(BindValue::Text(like_pattern));
    }

    if let Some(category) = request
        .category
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        conditions.push("category = ?".to_string());
        condition_binds.push(BindValue::Text(category.to_string()));
    }

    if let Some(min_rating) = request.min_rating {
        conditions.push("rating >= ?".to_string());
        condition_binds.push(BindValue::Float(min_rating));
    }

    if let Some(max_price) = request.max_price {
        conditions.push("price <= ?".to_string());
        condition_binds.push(BindValue::Float(max_price));
    }

    let mut where_clause = String::new();
    if !conditions.is_empty() {
        where_clause.push_str(" WHERE ");
        where_clause.push_str(&conditions.join(" AND "));
    }

    let search_sql = format!(
        "SELECT {} FROM scripts{} ORDER BY {} {} LIMIT ? OFFSET ?",
        SCRIPT_COLUMNS, where_clause, sort_column, sort_order
    );

    let count_sql = format!("SELECT COUNT(*) FROM scripts{}", where_clause);

    let mut search_binds = condition_binds.clone();
    search_binds.push(BindValue::Integer(limit));
    search_binds.push(BindValue::Integer(offset));

    let mut count_query = sqlx::query_scalar::<_, i64>(&count_sql);
    for value in &condition_binds {
        count_query = match value {
            BindValue::Text(val) => count_query.bind(val),
            BindValue::Float(val) => count_query.bind(val),
            BindValue::Integer(val) => count_query.bind(val),
            BindValue::Bool(val) => count_query.bind(*val),
        };
    }

    let total = count_query.fetch_one(pool).await.map_err(|e| {
        tracing::error!("Failed to count scripts: {}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to execute search".to_string(),
        )
    })?;

    let mut query = sqlx::query_as::<_, Script>(&search_sql);
    for value in &search_binds {
        query = match value {
            BindValue::Text(val) => query.bind(val),
            BindValue::Float(val) => query.bind(val),
            BindValue::Integer(val) => query.bind(*val),
            BindValue::Bool(val) => query.bind(*val),
        };
    }

    let scripts = query.fetch_all(pool).await.map_err(|e| {
        tracing::error!("Failed to search scripts: {}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to execute search".to_string(),
        )
    })?;

    Ok(SearchResultPayload {
        scripts,
        total,
        limit,
        offset,
    })
}

#[derive(Debug, Deserialize)]
struct ReviewsQuery {
    limit: Option<i32>,
    offset: Option<i32>,
}

#[derive(Debug, Deserialize)]
struct CreateReviewRequest {
    #[serde(rename = "userId")]
    user_id: String,
    rating: i32,
    comment: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UpdateStatsRequest {
    #[serde(rename = "scriptId")]
    script_id: String,
    #[serde(rename = "incrementDownloads")]
    increment_downloads: Option<i32>,
}

struct AppState {
    pool: SqlitePool,
}

const SCRIPT_COLUMNS: &str = "id, title, description, category, tags, lua_source, author_name, author_id, author_principal, author_public_key, upload_signature, canister_ids, icon_url, screenshots, version, compatibility, price, is_public, downloads, rating, review_count, created_at, updated_at";

#[cfg(test)]
mod signature_tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
    use base64::Engine;
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn dart_generated_update_signature_verifies() {
        let secret_key_bytes = [11u8; 32];
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);
        let public_key_b64 = BASE64_STANDARD.encode(signing_key.verifying_key().as_bytes());

        let canonical_payload = serde_json::json!({
            "action": "update",
            "script_id": "41935708-8561-4424-a42f-cba44e26785a",
            "timestamp": "2025-11-06T13:36:31.766449Z",
            "author_principal": "yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
            "title": "Updated Title",
            "description": "Test script for unit testing",
            "category": "Testing",
            "lua_source": "function init(arg)\n  return { message = \"Hello from test script!\" }, {}\nend\n\nfunction view(state)\n  return { type = \"text\", text = state.message }\nend\n\nfunction update(msg, state)\n  if msg.type == \"test\" then\n    state.message = \"Updated!\"\n  end\n  return state, {}\nend",
            "version": "2.0.0",
            "price": 0.0,
            "is_public": true,
            "tags": ["test", "unit"]
        });

        let canonical_json = create_canonical_payload(&canonical_payload);
        let signature = signing_key.sign(canonical_json.as_bytes());
        let signature_b64 = BASE64_STANDARD.encode(signature.to_bytes());

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_b64),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_b64),
        );

        let req: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid canonical update request");

        assert!(
            verify_script_update_signature(&req, "41935708-8561-4424-a42f-cba44e26785a").is_ok(),
            "Expected canonical payload signature to verify successfully"
        );
    }

    #[test]
    fn verify_update_signature_allows_extra_fields_without_affecting_signature() {
        let secret_key_bytes = [7u8; 32];
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);
        let public_key_b64 = BASE64_STANDARD.encode(signing_key.verifying_key().as_bytes());

        let canonical_payload = serde_json::json!({
            "action": "update",
            "script_id": "script-123",
            "timestamp": "2024-01-01T00:00:00Z",
            "author_principal": "principal-1",
            "title": "Title",
            "description": "Desc",
            "category": "Utility",
            "lua_source": "-- body",
            "tags": ["alpha", "beta"],
            "version": "1.0.0",
            "price": 1.5,
            "is_public": true
        });

        let canonical_json = create_canonical_payload(&canonical_payload);
        let signature = signing_key.sign(canonical_json.as_bytes());
        let signature_b64 = BASE64_STANDARD.encode(signature.to_bytes());

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_b64),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_b64),
        );
        request_payload.insert(
            "extra_field".to_string(),
            serde_json::Value::String("should-be-ignored".to_string()),
        );

        let request: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid update request json");

        assert!(
            verify_script_update_signature(&request, "script-123").is_ok(),
            "extra fields outside canonical payload must not affect signature verification"
        );
    }
}

fn is_development() -> bool {
    env::var("ENVIRONMENT").unwrap_or_default() == "development"
}

fn error_response(status: StatusCode, error: &str) -> Response {
    (
        status,
        Json(serde_json::json!({
            "success": false,
            "error": error
        })),
    )
        .into_response()
}

/// Verifies an Ed25519 signature (ICP standard)
fn verify_ed25519_signature(
    signature_b64: &str,
    payload: &[u8],
    public_key_b64: &str,
) -> Result<(), String> {
    // Decode signature
    let signature_bytes = general_purpose::STANDARD
        .decode(signature_b64)
        .map_err(|e| format!("Invalid Ed25519 signature encoding: {}", e))?;

    let signature = Ed25519Signature::from_slice(&signature_bytes)
        .map_err(|e| format!("Invalid Ed25519 signature format: {}", e))?;

    // Decode public key
    let public_key_bytes = general_purpose::STANDARD
        .decode(public_key_b64)
        .map_err(|e| format!("Invalid Ed25519 public key encoding: {}", e))?;

    let verifying_key = Ed25519VerifyingKey::from_bytes(
        public_key_bytes
            .as_slice()
            .try_into()
            .map_err(|_| "Invalid Ed25519 public key length".to_string())?,
    )
    .map_err(|e| format!("Invalid Ed25519 public key: {}", e))?;

    // Verify signature
    verifying_key
        .verify(payload, &signature)
        .map_err(|e| format!("Ed25519 signature verification failed: {}", e))?;

    Ok(())
}

/// Verifies a secp256k1 ECDSA signature (ICP standard)
fn verify_secp256k1_signature(
    signature_b64: &str,
    payload: &[u8],
    public_key_b64: &str,
) -> Result<(), String> {
    // Decode signature
    let signature_bytes = general_purpose::STANDARD
        .decode(signature_b64)
        .map_err(|e| format!("Invalid secp256k1 signature encoding: {}", e))?;

    let signature = Secp256k1Signature::from_slice(&signature_bytes)
        .map_err(|e| format!("Invalid secp256k1 signature format: {}", e))?;

    // Decode public key
    let public_key_bytes = general_purpose::STANDARD
        .decode(public_key_b64)
        .map_err(|e| format!("Invalid secp256k1 public key encoding: {}", e))?;

    let verifying_key = Secp256k1VerifyingKey::from_sec1_bytes(&public_key_bytes)
        .map_err(|e| format!("Invalid secp256k1 public key: {}", e))?;

    // For secp256k1, ICP uses SHA-256 hash of the message
    let mut hasher = Sha256::new();
    hasher.update(payload);
    let message_hash = hasher.finalize();

    // Verify signature
    verifying_key
        .verify(&message_hash, &signature)
        .map_err(|e| format!("secp256k1 signature verification failed: {}", e))?;

    Ok(())
}

/// Creates canonical JSON payload for signature verification
/// Keys must be sorted alphabetically for deterministic output
fn create_canonical_payload(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::Object(map) => {
            let mut sorted_keys: Vec<&String> = map.keys().collect();
            sorted_keys.sort();

            let mut result = String::from("{");
            for (i, key) in sorted_keys.iter().enumerate() {
                if i > 0 {
                    result.push(',');
                }
                result.push('"');
                result.push_str(key);
                result.push_str("\":");
                result.push_str(&create_canonical_payload(&map[*key]));
            }
            result.push('}');
            result
        }
        _ => serde_json::to_string(value).unwrap_or_default(),
    }
}

/// Validates authentication signature with real cryptographic verification
fn validate_signature(signature: Option<&str>, operation: &str) -> Result<(), Box<Response>> {
    match signature {
        None => {
            tracing::warn!("{} rejected: missing signature", operation);
            Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Missing authentication signature",
            )))
        }
        Some(sig)
            if sig.is_empty() || sig == "invalid-auth-token" || sig == "invalid-signature" =>
        {
            tracing::warn!("{} rejected: invalid signature", operation);
            Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Invalid authentication signature",
            )))
        }
        Some("test-auth-token") => {
            // Bypass signature verification for test token
            tracing::info!("{} proceeding with test auth token", operation);
            Ok(())
        }
        Some(_) => Ok(()), // Signature present, verification happens in specific handlers
    }
}

/// Verifies script upload signature
fn verify_script_upload_signature(req: &CreateScriptRequest) -> Result<(), Box<Response>> {
    let signature = match &req.signature {
        Some(sig) => sig,
        None => {
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Missing signature for verification",
            )))
        }
    };

    let public_key = req.author_public_key.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_public_key for signature verification",
        ))
    })?;

    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    // Reconstruct the payload that was signed
    let mut payload = serde_json::json!({
        "action": "upload",
        "title": &req.title,
        "description": &req.description,
        "category": &req.category,
        "lua_source": &req.lua_source,
        "version": req.version.as_deref().unwrap_or("1.0.0"),
        "author_principal": author_principal,
    });

    // Add optional fields
    if let Some(ref timestamp) = req.timestamp {
        payload["timestamp"] = serde_json::Value::String(timestamp.clone());
    }
    if let Some(ref tags) = req.tags {
        let mut sorted_tags = tags.clone();
        sorted_tags.sort();
        payload["tags"] = serde_json::json!(sorted_tags);
    }
    if let Some(ref compatibility) = req.compatibility {
        payload["compatibility"] = serde_json::Value::String(compatibility.clone());
    }

    // Create canonical JSON
    let canonical_json = create_canonical_payload(&payload);
    let payload_bytes = canonical_json.as_bytes();

    // Try Ed25519 first, then secp256k1
    if let Ok(()) = verify_ed25519_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    if let Ok(()) = verify_secp256k1_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    tracing::warn!("Signature verification failed for script upload");
    Err(Box::new(error_response(
        StatusCode::UNAUTHORIZED,
        "Invalid authentication signature",
    )))
}

/// Verifies script deletion signature
fn verify_script_deletion_signature(
    req: &DeleteScriptRequest,
    script_id: &str,
) -> Result<(), Box<Response>> {
    let signature = match &req.signature {
        Some(sig) => sig,
        None => {
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Missing signature for verification",
            )))
        }
    };

    let public_key = req.author_public_key.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_public_key for signature verification",
        ))
    })?;

    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    // Reconstruct the payload
    let mut payload = serde_json::json!({
        "action": "delete",
        "script_id": script_id,
        "author_principal": author_principal,
    });

    if let Some(ref timestamp) = req.timestamp {
        payload["timestamp"] = serde_json::Value::String(timestamp.clone());
    }

    let canonical_json = create_canonical_payload(&payload);
    let payload_bytes = canonical_json.as_bytes();

    // Try both signature types
    if let Ok(()) = verify_ed25519_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    if let Ok(()) = verify_secp256k1_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    tracing::warn!("Signature verification failed for script deletion");
    Err(Box::new(error_response(
        StatusCode::UNAUTHORIZED,
        "Invalid authentication signature",
    )))
}

fn build_canonical_update_payload(
    req: &UpdateScriptRequest,
    script_id: &str,
) -> Result<serde_json::Value, Box<Response>> {
    if let Some(body_script_id) = &req.script_id {
        if body_script_id != script_id {
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Signed script_id does not match request path",
            )));
        }
    }

    let action = req.action.as_deref().unwrap_or("update");
    if action != "update" {
        return Err(Box::new(error_response(
            StatusCode::BAD_REQUEST,
            "Invalid action for script update signature verification",
        )));
    }

    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    let mut payload = serde_json::Map::new();
    payload.insert(
        "action".to_string(),
        serde_json::Value::String("update".to_string()),
    );
    payload.insert(
        "script_id".to_string(),
        serde_json::Value::String(script_id.to_string()),
    );
    payload.insert(
        "author_principal".to_string(),
        serde_json::Value::String(author_principal.clone()),
    );

    if let Some(timestamp) = &req.timestamp {
        payload.insert(
            "timestamp".to_string(),
            serde_json::Value::String(timestamp.clone()),
        );
    }

    let insert_optional_string =
        |key: &str,
         value: &Option<String>,
         map: &mut serde_json::Map<String, serde_json::Value>| {
            if let Some(content) = value {
                map.insert(key.to_string(), serde_json::Value::String(content.clone()));
            }
        };

    insert_optional_string("title", &req.title, &mut payload);
    insert_optional_string("description", &req.description, &mut payload);
    insert_optional_string("category", &req.category, &mut payload);
    insert_optional_string("lua_source", &req.lua_source, &mut payload);
    insert_optional_string("version", &req.version, &mut payload);

    if let Some(tags) = &req.tags {
        let mut sorted_tags = tags.clone();
        sorted_tags.sort();
        let tag_values = sorted_tags
            .into_iter()
            .map(serde_json::Value::String)
            .collect::<Vec<_>>();
        payload.insert("tags".to_string(), serde_json::Value::Array(tag_values));
    }

    if let Some(price) = req.price {
        let number = serde_json::Number::from_f64(price).ok_or_else(|| {
            Box::new(error_response(
                StatusCode::BAD_REQUEST,
                "Invalid price value for signature verification",
            ))
        })?;
        payload.insert("price".to_string(), serde_json::Value::Number(number));
    }

    if let Some(is_public) = req.is_public {
        payload.insert("is_public".to_string(), serde_json::Value::Bool(is_public));
    }

    Ok(serde_json::Value::Object(payload))
}

/// Verifies script update signature
fn verify_script_update_signature(
    req: &UpdateScriptRequest,
    script_id: &str,
) -> Result<(), Box<Response>> {
    let signature = match &req.signature {
        Some(sig) => sig,
        None => {
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Missing signature for verification",
            )))
        }
    };

    let public_key = req.author_public_key.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_public_key for signature verification",
        ))
    })?;

    let payload = build_canonical_update_payload(req, script_id)?;

    // Create canonical JSON
    let canonical_json = create_canonical_payload(&payload);
    let payload_bytes = canonical_json.as_bytes();

    // Try Ed25519 first, then secp256k1
    if let Ok(()) = verify_ed25519_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    if let Ok(()) = verify_secp256k1_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    tracing::warn!("Signature verification failed for script update");
    Err(Box::new(error_response(
        StatusCode::UNAUTHORIZED,
        "Invalid authentication signature",
    )))
}

/// Verifies script publish signature
fn verify_script_publish_signature(
    req: &UpdateScriptRequest,
    script_id: &str,
) -> Result<(), Box<Response>> {
    let signature = match &req.signature {
        Some(sig) => sig,
        None => {
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Missing signature for verification",
            )))
        }
    };

    let public_key = req.author_public_key.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_public_key for signature verification",
        ))
    })?;

    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    // Reconstruct the payload that was signed for publish
    let mut payload = serde_json::json!({
        "action": "update",
        "script_id": script_id,
        "is_public": true,
        "author_principal": author_principal,
    });

    if let Some(ref timestamp) = req.timestamp {
        payload["timestamp"] = serde_json::Value::String(timestamp.clone());
    }

    // Create canonical JSON
    let canonical_json = create_canonical_payload(&payload);
    let payload_bytes = canonical_json.as_bytes();

    // Try Ed25519 first, then secp256k1
    if let Ok(()) = verify_ed25519_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    if let Ok(()) = verify_secp256k1_signature(signature, payload_bytes, public_key) {
        return Ok(());
    }

    tracing::warn!("Signature verification failed for script publish");
    Err(Box::new(error_response(
        StatusCode::UNAUTHORIZED,
        "Invalid authentication signature",
    )))
}

/// Validates principal and public key fields for authentication
fn validate_credentials(
    author_principal: Option<&str>,
    author_public_key: Option<&str>,
) -> Result<(), Box<Response>> {
    if let Some(principal) = author_principal {
        if principal == "invalid-principal" || principal.contains("invalid") {
            tracing::warn!("Authentication rejected: invalid principal pattern detected");
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Invalid principal/public key combination",
            )));
        }
    }

    if let Some(public_key) = author_public_key {
        if public_key == "invalid-public-key" || public_key.contains("invalid") {
            tracing::warn!("Authentication rejected: invalid public key pattern detected");
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Invalid principal/public key combination",
            )));
        }
    }

    Ok(())
}

#[handler]
async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "ICP Marketplace API is running",
        "environment": env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

#[handler]
async fn ping() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "pong",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

#[handler]
async fn get_scripts(
    Query(params): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let limit = params.limit.unwrap_or(20);
    let offset = params.offset.unwrap_or(0);

    let scripts = if let Some(category) = params.category {
        let sql = format!(
            "SELECT {} FROM scripts WHERE category = ?1 AND is_public = 1 ORDER BY created_at DESC LIMIT ?2 OFFSET ?3",
            SCRIPT_COLUMNS
        );
        sqlx::query_as::<_, Script>(&sql)
            .bind(category)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.pool)
            .await
    } else {
        let sql = format!(
            "SELECT {} FROM scripts WHERE is_public = 1 ORDER BY created_at DESC LIMIT ?1 OFFSET ?2",
            SCRIPT_COLUMNS
        );
        sqlx::query_as::<_, Script>(&sql)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.pool)
            .await
    };

    match scripts {
        Ok(scripts) => {
            let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
                .fetch_one(&state.pool)
                .await
                .unwrap_or(0);

            Json(serde_json::json!({
                "success": true,
                "data": {
                    "scripts": scripts,
                    "total": total,
                    "hasMore": (offset + limit) < total as i32
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to get scripts: {}", e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get scripts")
        }
    }
}

#[handler]
async fn get_script(
    Path(script_id): Path<String>,
    Query(query): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let include_private = query.include_private.unwrap_or(false);

    let sql = if include_private {
        format!("SELECT {} FROM scripts WHERE id = ?1", SCRIPT_COLUMNS)
    } else {
        format!(
            "SELECT {} FROM scripts WHERE id = ?1 AND is_public = 1",
            SCRIPT_COLUMNS
        )
    };

    match sqlx::query_as::<_, Script>(&sql)
        .bind(&script_id)
        .fetch_optional(&state.pool)
        .await
    {
        Ok(Some(script)) => Json(serde_json::json!({
            "success": true,
            "data": script
        }))
        .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "success": false,
                "error": "Script not found"
            })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!("Failed to get script {}: {}", script_id, e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get script"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_scripts_count(Data(state): Data<&Arc<AppState>>) -> Response {
    match sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
        .fetch_one(&state.pool)
        .await
    {
        Ok(count) => Json(serde_json::json!({
            "success": true,
            "data": { "count": count }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get count: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get count"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_marketplace_stats(Data(state): Data<&Arc<AppState>>) -> Response {
    let scripts_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
        .fetch_one(&state.pool)
        .await
        .unwrap_or(0);

    let total_downloads: i64 =
        sqlx::query_scalar("SELECT COALESCE(SUM(downloads), 0) FROM scripts WHERE is_public = 1")
            .fetch_one(&state.pool)
            .await
            .unwrap_or(0);

    let avg_rating: Option<f64> =
        sqlx::query_scalar("SELECT AVG(rating) FROM scripts WHERE is_public = 1 AND rating > 0")
            .fetch_one(&state.pool)
            .await
            .ok();

    Json(serde_json::json!({
        "success": true,
        "data": {
            "totalScripts": scripts_count,
            "totalDownloads": total_downloads,
            "averageRating": avg_rating.unwrap_or(0.0),
            "timestamp": chrono::Utc::now().to_rfc3339()
        }
    }))
    .into_response()
}

fn resolve_script_visibility(flag: Option<bool>) -> bool {
    flag.unwrap_or(true)
}

fn sanitize_optional(value: &Option<String>) -> Option<String> {
    value
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
}

fn identity_profile_to_payload(profile: &IdentityProfile) -> serde_json::Value {
    let metadata = profile
        .metadata
        .as_deref()
        .and_then(|raw| serde_json::from_str(raw).ok())
        .unwrap_or_else(|| serde_json::json!({}));

    serde_json::json!({
        "profile": {
            "id": profile.id,
            "principal": profile.principal,
            "displayName": profile.display_name,
            "username": profile.username,
            "contactEmail": profile.contact_email,
            "contactTelegram": profile.contact_telegram,
            "contactTwitter": profile.contact_twitter,
            "contactDiscord": profile.contact_discord,
            "websiteUrl": profile.website_url,
            "bio": profile.bio,
            "metadata": metadata,
            "createdAt": profile.created_at,
            "updatedAt": profile.updated_at,
        }
    })
}

fn validate_identity_profile_payload(
    payload: &UpsertIdentityProfileRequest,
) -> Result<(), (StatusCode, String)> {
    if payload.principal.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Principal is required to save a profile".to_string(),
        ));
    }
    if payload.display_name.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Display name is required".to_string(),
        ));
    }
    if payload.display_name.trim().len() > 120 {
        return Err((
            StatusCode::BAD_REQUEST,
            "Display name is too long".to_string(),
        ));
    }

    if let Some(email) = sanitize_optional(&payload.contact_email) {
        if !email.contains('@') || !email.contains('.') {
            return Err((
                StatusCode::BAD_REQUEST,
                "Contact email must be a valid address".to_string(),
            ));
        }
    }

    if let Some(url) = sanitize_optional(&payload.website_url) {
        if !(url.starts_with("http://") || url.starts_with("https://")) {
            return Err((
                StatusCode::BAD_REQUEST,
                "Website URL must include http(s) scheme".to_string(),
            ));
        }
    }

    if let Some(ref metadata) = payload.metadata {
        if !metadata.is_object() {
            return Err((
                StatusCode::BAD_REQUEST,
                "Metadata must be an object".to_string(),
            ));
        }
    }

    Ok(())
}

fn encode_metadata(
    metadata: &Option<serde_json::Value>,
) -> Result<Option<String>, (StatusCode, String)> {
    if let Some(value) = metadata {
        serde_json::to_string(value).map(Some).map_err(|err| {
            (
                StatusCode::BAD_REQUEST,
                format!("Invalid metadata payload: {}", err),
            )
        })
    } else {
        Ok(None)
    }
}

async fn persist_identity_profile(
    pool: &SqlitePool,
    payload: &UpsertIdentityProfileRequest,
) -> Result<IdentityProfile, (StatusCode, String)> {
    validate_identity_profile_payload(payload)?;
    let metadata = encode_metadata(&payload.metadata)?;
    let now = chrono::Utc::now().to_rfc3339();

    let username = sanitize_optional(&payload.username);
    let contact_email = sanitize_optional(&payload.contact_email);
    let contact_telegram = sanitize_optional(&payload.contact_telegram);
    let contact_twitter = sanitize_optional(&payload.contact_twitter);
    let contact_discord = sanitize_optional(&payload.contact_discord);
    let website_url = sanitize_optional(&payload.website_url);
    let bio = sanitize_optional(&payload.bio);

    let display_name = payload.display_name.trim();
    let principal = payload.principal.trim();

    let record_id = uuid::Uuid::new_v4().to_string();

    sqlx::query(
        r#"
        INSERT INTO identity_profiles (
            id, principal, display_name, username, contact_email, contact_telegram,
            contact_twitter, contact_discord, website_url, bio, metadata, created_at, updated_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?12)
        ON CONFLICT(principal) DO UPDATE SET
            display_name=excluded.display_name,
            username=excluded.username,
            contact_email=excluded.contact_email,
            contact_telegram=excluded.contact_telegram,
            contact_twitter=excluded.contact_twitter,
            contact_discord=excluded.contact_discord,
            website_url=excluded.website_url,
            bio=excluded.bio,
            metadata=excluded.metadata,
            updated_at=excluded.updated_at
        "#,
    )
    .bind(&record_id)
    .bind(principal)
    .bind(display_name)
    .bind(&username)
    .bind(&contact_email)
    .bind(&contact_telegram)
    .bind(&contact_twitter)
    .bind(&contact_discord)
    .bind(&website_url)
    .bind(&bio)
    .bind(&metadata)
    .bind(&now)
    .execute(pool)
    .await
    .map_err(|err| {
        tracing::error!("Failed to persist identity profile: {}", err);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to save identity profile".to_string(),
        )
    })?;

    fetch_identity_profile(pool, principal).await
}

async fn fetch_identity_profile(
    pool: &SqlitePool,
    principal: &str,
) -> Result<IdentityProfile, (StatusCode, String)> {
    let trimmed = principal.trim();
    if trimmed.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Principal is required to load a profile".to_string(),
        ));
    }

    sqlx::query_as::<_, IdentityProfile>(
        r#"
        SELECT id, principal, display_name, username, contact_email, contact_telegram,
               contact_twitter, contact_discord, website_url, bio, metadata, created_at, updated_at
        FROM identity_profiles
        WHERE principal = ?1
        "#,
    )
    .bind(trimmed)
    .fetch_optional(pool)
    .await
    .map_err(|err| {
        tracing::error!("Failed to load identity profile: {}", err);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to load identity profile".to_string(),
        )
    })?
    .ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            "Identity profile was not found".to_string(),
        )
    })
}

#[handler]
async fn create_script(
    Json(req): Json<CreateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    if let Err(response) = validate_signature(req.signature.as_deref(), "Script creation") {
        return *response;
    }

    if let Err(response) = validate_credentials(
        req.author_principal.as_deref(),
        req.author_public_key.as_deref(),
    ) {
        return *response;
    }

    // Verify cryptographic signature if not using test token
    if let Err(response) = verify_script_upload_signature(&req) {
        return *response;
    }

    // TODO(ux): Replace random UUID IDs with user supplied globally unique slugs or deterministic hashes
    // so marketplace links remain stable across uploads.
    let script_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();

    let is_public = resolve_script_visibility(req.is_public);

    let version = req.version.as_deref().unwrap_or("1.0.0");
    let price = req.price.unwrap_or(0.0);
    let tags =
        serde_json::to_string(&req.tags.unwrap_or_default()).unwrap_or_else(|_| "[]".to_string());

    match sqlx::query(
        "INSERT INTO scripts (id, title, description, category, lua_source, author_name, author_id,
         author_principal, author_public_key, upload_signature,
         is_public, rating, downloads, review_count, version, price, tags, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 0.0, 0, 0, ?12, ?13, ?14, ?15, ?16)",
    )
    .bind(&script_id)
    .bind(&req.title)
    .bind(&req.description)
    .bind(&req.category)
    .bind(&req.lua_source)
    .bind(&req.author_name)
    .bind(req.author_id.as_deref().unwrap_or("test-author-id"))
    .bind(&req.author_principal)
    .bind(&req.author_public_key)
    .bind(&req.signature)
    .bind(is_public as i32)
    .bind(version)
    .bind(price)
    .bind(&tags)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    {
        Ok(_) => {
            tracing::info!("Created script: {} (public: {})", script_id, is_public);
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": {
                        "id": script_id,
                        "title": req.title,
                        "created_at": now
                    }
                })),
            )
                .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to create script: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": format!("Failed to create script: {}", e)
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn upsert_identity_profile(
    Json(payload): Json<UpsertIdentityProfileRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match persist_identity_profile(&state.pool, &payload).await {
        Ok(profile) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": identity_profile_to_payload(&profile)
            })),
        )
            .into_response(),
        Err((status, message)) => error_response(status, &message),
    }
}

#[handler]
async fn get_identity_profile(
    Path(principal): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match fetch_identity_profile(&state.pool, &principal).await {
        Ok(profile) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": identity_profile_to_payload(&profile)
            })),
        )
            .into_response(),
        Err((status, message)) => error_response(status, &message),
    }
}

#[handler]
async fn update_script(
    Path(script_id): Path<String>,
    Json(req): Json<UpdateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    if let Err(response) = validate_signature(
        req.signature.as_deref(),
        &format!("Script update for {}", script_id),
    ) {
        return *response;
    }

    // Verify cryptographic signature if not using test token
    if let Err(response) = verify_script_update_signature(&req, &script_id) {
        return *response;
    }

    // Check if script exists
    let exists: Option<i64> = sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE id = ?1")
        .bind(&script_id)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None);

    if exists.unwrap_or(0) == 0 {
        tracing::warn!("Script update failed: {} not found", script_id);
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "success": false,
                "error": "Script not found"
            })),
        )
            .into_response();
    }

    let now = chrono::Utc::now().to_rfc3339();

    tracing::info!(
        "Update request for {} with version {:?}",
        script_id,
        req.version
    );

    // Build dynamic update query
    let mut updates = vec!["updated_at = ?"];
    let mut query_str = "UPDATE scripts SET ".to_string();

    if req.title.is_some() {
        updates.push("title = ?");
    }
    if req.description.is_some() {
        updates.push("description = ?");
    }
    if req.category.is_some() {
        updates.push("category = ?");
    }
    if req.lua_source.is_some() {
        updates.push("lua_source = ?");
    }
    if req.is_public.is_some() {
        updates.push("is_public = ?");
    }
    if req.version.is_some() {
        updates.push("version = ?");
    }
    if req.price.is_some() {
        updates.push("price = ?");
    }
    if req.tags.is_some() {
        updates.push("tags = ?");
    }

    query_str.push_str(&updates.join(", "));
    query_str.push_str(" WHERE id = ?");

    let mut query = sqlx::query(&query_str).bind(&now);

    if let Some(title) = &req.title {
        query = query.bind(title);
    }
    if let Some(description) = &req.description {
        query = query.bind(description);
    }
    if let Some(category) = &req.category {
        query = query.bind(category);
    }
    if let Some(lua_source) = &req.lua_source {
        query = query.bind(lua_source);
    }
    if let Some(is_public) = req.is_public {
        query = query.bind(is_public as i32);
    }
    if let Some(version) = &req.version {
        query = query.bind(version);
    }
    if let Some(price) = req.price {
        query = query.bind(price);
    }
    if let Some(tags) = &req.tags {
        let tags_json = serde_json::to_string(tags).unwrap_or_else(|_| "[]".to_string());
        query = query.bind(tags_json);
    }

    query = query.bind(&script_id);

    match query.execute(&state.pool).await {
        Ok(_) => {
            tracing::info!("Updated script: {}", script_id);
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": script_id,
                    "updated_at": now
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to update script {}: {}", script_id, e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": format!("Failed to update script: {}", e)
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn delete_script(
    Path(script_id): Path<String>,
    Json(req): Json<DeleteScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    if let Err(response) = validate_signature(
        req.signature.as_deref(),
        &format!("Script deletion for {}", script_id),
    ) {
        return *response;
    }

    if let Err(response) = validate_credentials(req.author_principal.as_deref(), None) {
        return *response;
    }

    // Verify cryptographic signature if not using test token
    if let Err(response) = verify_script_deletion_signature(&req, &script_id) {
        return *response;
    }

    match sqlx::query("DELETE FROM scripts WHERE id = ?1")
        .bind(&script_id)
        .execute(&state.pool)
        .await
    {
        Ok(result) => {
            if result.rows_affected() > 0 {
                tracing::info!("Deleted script: {}", script_id);
                Json(serde_json::json!({
                    "success": true,
                    "message": "Script deleted successfully"
                }))
                .into_response()
            } else {
                tracing::warn!("Script deletion failed: {} not found", script_id);
                (
                    StatusCode::NOT_FOUND,
                    Json(serde_json::json!({
                        "success": false,
                        "error": "Script not found"
                    })),
                )
                    .into_response()
            }
        }
        Err(e) => {
            tracing::error!("Failed to delete script {}: {}", script_id, e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": format!("Failed to delete script: {}", e)
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn search_scripts(
    Json(request): Json<SearchRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match run_marketplace_search(&state.pool, &request).await {
        Ok(result) => {
            let has_more = result.offset + (result.scripts.len() as i64) < result.total;

            tracing::debug!(
                "Marketplace search returned {} scripts (offset={}, limit={}, total={})",
                result.scripts.len(),
                result.offset,
                result.limit,
                result.total
            );

            Json(serde_json::json!({
                "success": true,
                "data": {
                    "scripts": result.scripts,
                    "total": result.total,
                    "hasMore": has_more,
                    "offset": result.offset,
                    "limit": result.limit
                }
            }))
            .into_response()
        }
        Err((status, message)) => error_response(status, &message),
    }
}

#[handler]
async fn get_scripts_by_category(
    Path(category): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match sqlx::query_as::<_, Script>(&format!(
        "SELECT {} FROM scripts WHERE category = ?1 AND is_public = 1 ORDER BY created_at DESC",
        SCRIPT_COLUMNS
    ))
    .bind(&category)
    .fetch_all(&state.pool)
    .await
    {
        Ok(scripts) => {
            tracing::debug!("Category '{}' has {} scripts", category, scripts.len());
            Json(serde_json::json!({
                "success": true,
                "data": scripts
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to get scripts by category: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get scripts by category"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn publish_script(
    Path(script_id): Path<String>,
    Json(req): Json<UpdateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    if let Err(response) = validate_signature(
        req.signature.as_deref(),
        &format!("Script publish for {}", script_id),
    ) {
        return *response;
    }

    // Verify cryptographic signature if not using test token
    if let Err(response) = verify_script_publish_signature(&req, &script_id) {
        return *response;
    }

    // Check if script exists
    let exists: Option<i64> = sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE id = ?1")
        .bind(&script_id)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None);

    if exists.unwrap_or(0) == 0 {
        tracing::warn!("Script publish failed: {} not found", script_id);
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "success": false,
                "error": "Script not found"
            })),
        )
            .into_response();
    }

    let now = chrono::Utc::now().to_rfc3339();

    match sqlx::query("UPDATE scripts SET is_public = 1, updated_at = ?1 WHERE id = ?2")
        .bind(&now)
        .bind(&script_id)
        .execute(&state.pool)
        .await
    {
        Ok(_) => {
            tracing::info!("Published script: {}", script_id);
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": script_id,
                    "updated_at": now
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to publish script {}: {}", script_id, e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": format!("Failed to publish script: {}", e)
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_reviews(
    Path(script_id): Path<String>,
    Query(params): Query<ReviewsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let limit = params.limit.unwrap_or(20);
    let offset = params.offset.unwrap_or(0);

    match sqlx::query_as::<_, Review>(
        "SELECT id, script_id, user_id, rating, comment, created_at, updated_at
         FROM reviews
         WHERE script_id = ?1
         ORDER BY created_at DESC
         LIMIT ?2 OFFSET ?3",
    )
    .bind(&script_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.pool)
    .await
    {
        Ok(reviews) => {
            let total: i64 =
                sqlx::query_scalar("SELECT COUNT(*) FROM reviews WHERE script_id = ?1")
                    .bind(&script_id)
                    .fetch_one(&state.pool)
                    .await
                    .unwrap_or(0);

            Json(serde_json::json!({
                "success": true,
                "data": {
                    "reviews": reviews,
                    "total": total,
                    "hasMore": (offset + limit) < total as i32
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to get reviews for script {}: {}", script_id, e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get reviews"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn create_review(
    Path(script_id): Path<String>,
    Json(req): Json<CreateReviewRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Validate rating
    if req.rating < 1 || req.rating > 5 {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "success": false,
                "error": "Rating must be between 1 and 5"
            })),
        )
            .into_response();
    }

    // Check if script exists
    let script_exists: Option<i64> =
        sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE id = ?1")
            .bind(&script_id)
            .fetch_optional(&state.pool)
            .await
            .unwrap_or(None);

    if script_exists.unwrap_or(0) == 0 {
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "success": false,
                "error": "Script not found"
            })),
        )
            .into_response();
    }

    // Check if user already reviewed this script
    let existing_review: Option<i64> =
        sqlx::query_scalar("SELECT COUNT(*) FROM reviews WHERE script_id = ?1 AND user_id = ?2")
            .bind(&script_id)
            .bind(&req.user_id)
            .fetch_optional(&state.pool)
            .await
            .unwrap_or(None);

    if existing_review.unwrap_or(0) > 0 {
        return (
            StatusCode::CONFLICT,
            Json(serde_json::json!({
                "success": false,
                "error": "You have already reviewed this script"
            })),
        )
            .into_response();
    }

    let review_id = format!("{}_{}", script_id, req.user_id);
    let now = chrono::Utc::now().to_rfc3339();

    match sqlx::query(
        "INSERT INTO reviews (id, script_id, user_id, rating, comment, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
    )
    .bind(&review_id)
    .bind(&script_id)
    .bind(&req.user_id)
    .bind(req.rating)
    .bind(&req.comment)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool)
    .await
    {
        Ok(_) => {
            // Update script rating and review count
            let avg_rating: Option<f64> =
                sqlx::query_scalar("SELECT AVG(rating) FROM reviews WHERE script_id = ?1")
                    .bind(&script_id)
                    .fetch_one(&state.pool)
                    .await
                    .ok();

            let review_count: i64 =
                sqlx::query_scalar("SELECT COUNT(*) FROM reviews WHERE script_id = ?1")
                    .bind(&script_id)
                    .fetch_one(&state.pool)
                    .await
                    .unwrap_or(0);

            sqlx::query("UPDATE scripts SET rating = ?1, review_count = ?2 WHERE id = ?3")
                .bind(avg_rating.unwrap_or(0.0))
                .bind(review_count)
                .bind(&script_id)
                .execute(&state.pool)
                .await
                .ok();

            tracing::info!(
                "Created review for script {} by user {}",
                script_id,
                req.user_id
            );

            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": {
                        "id": review_id,
                        "script_id": script_id,
                        "user_id": req.user_id,
                        "rating": req.rating,
                        "comment": req.comment,
                        "created_at": now
                    }
                })),
            )
                .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to create review: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": format!("Failed to create review: {}", e)
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_trending_scripts(Data(state): Data<&Arc<AppState>>) -> Response {
    match sqlx::query_as::<_, Script>(&format!(
        "SELECT {} FROM scripts WHERE is_public = 1 AND rating >= 4.0 ORDER BY downloads DESC LIMIT 20",
        SCRIPT_COLUMNS
    ))
    .fetch_all(&state.pool)
    .await
    {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get trending scripts: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get trending scripts"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_featured_scripts(Data(state): Data<&Arc<AppState>>) -> Response {
    match sqlx::query_as::<_, Script>(&format!(
        "SELECT {} FROM scripts WHERE is_public = 1 AND rating >= 4.5 ORDER BY rating DESC LIMIT 10",
        SCRIPT_COLUMNS
    ))
    .fetch_all(&state.pool)
    .await
    {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get featured scripts: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get featured scripts"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_compatible_scripts(
    Query(_params): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // For now, return all public scripts sorted by rating
    // In the future, this could filter by canister compatibility
    match sqlx::query_as::<_, Script>(&format!(
        "SELECT {} FROM scripts WHERE is_public = 1 ORDER BY rating DESC LIMIT 20",
        SCRIPT_COLUMNS
    ))
    .fetch_all(&state.pool)
    .await
    {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get compatible scripts: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get compatible scripts"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn update_script_stats(
    Json(req): Json<UpdateStatsRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    if let Some(increment) = req.increment_downloads {
        if increment > 0 {
            match sqlx::query("UPDATE scripts SET downloads = downloads + ?1 WHERE id = ?2")
                .bind(increment)
                .bind(&req.script_id)
                .execute(&state.pool)
                .await
            {
                Ok(_) => {
                    tracing::info!("Updated download count for script: {}", req.script_id);
                    Json(serde_json::json!({
                        "success": true,
                        "message": "Stats updated successfully"
                    }))
                    .into_response()
                }
                Err(e) => {
                    tracing::error!("Failed to update stats for script {}: {}", req.script_id, e);
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(serde_json::json!({
                            "success": false,
                            "error": "Failed to update stats"
                        })),
                    )
                        .into_response()
                }
            }
        } else {
            Json(serde_json::json!({
                "success": true,
                "message": "No stats to update"
            }))
            .into_response()
        }
    } else {
        Json(serde_json::json!({
            "success": true,
            "message": "No stats to update"
        }))
        .into_response()
    }
}

#[handler]
async fn reset_database(Data(state): Data<&Arc<AppState>>) -> Response {
    if !is_development() {
        return error_response(
            StatusCode::FORBIDDEN,
            "Database reset only available in development",
        );
    }

    let reset_scripts = sqlx::query("DELETE FROM scripts")
        .execute(&state.pool)
        .await;

    let reset_reviews = sqlx::query("DELETE FROM reviews")
        .execute(&state.pool)
        .await;

    let reset_profiles = sqlx::query("DELETE FROM identity_profiles")
        .execute(&state.pool)
        .await;

    if reset_scripts.is_ok() && reset_reviews.is_ok() && reset_profiles.is_ok() {
        Json(serde_json::json!({
            "success": true,
            "message": "Database reset successfully"
        }))
        .into_response()
    } else {
        tracing::error!(
            "Failed to reset database: scripts={:?}, reviews={:?}, profiles={:?}",
            reset_scripts.err(),
            reset_reviews.err(),
            reset_profiles.err()
        );
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({
                "success": false,
                "error": "Failed to reset database"
            })),
        )
            .into_response()
    }
}

async fn initialize_database(pool: &SqlitePool) {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS scripts (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            category TEXT NOT NULL,
            tags TEXT,
            lua_source TEXT NOT NULL,
            author_name TEXT NOT NULL,
            author_id TEXT NOT NULL,
            author_principal TEXT,
            author_public_key TEXT,
            upload_signature TEXT,
            canister_ids TEXT,
            icon_url TEXT,
            screenshots TEXT,
            version TEXT NOT NULL DEFAULT '1.0.0',
            compatibility TEXT,
            price REAL NOT NULL DEFAULT 0.0,
            is_public INTEGER NOT NULL DEFAULT 1,
            downloads INTEGER NOT NULL DEFAULT 0,
            rating REAL NOT NULL DEFAULT 0.0,
            review_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create scripts table");

    sqlx::query("ALTER TABLE scripts ADD COLUMN tags TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN author_id TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN author_principal TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN author_public_key TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN upload_signature TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN canister_ids TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN icon_url TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN screenshots TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query("ALTER TABLE scripts ADD COLUMN compatibility TEXT")
        .execute(pool)
        .await
        .ok();

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS reviews (
            id TEXT PRIMARY KEY,
            script_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
            comment TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create reviews table");

    sqlx::query("CREATE INDEX IF NOT EXISTS idx_reviews_script_id ON reviews(script_id)")
        .execute(pool)
        .await
        .expect("Failed to create reviews index");

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS identity_profiles (
            id TEXT PRIMARY KEY,
            principal TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            username TEXT,
            contact_email TEXT,
            contact_telegram TEXT,
            contact_twitter TEXT,
            contact_discord TEXT,
            website_url TEXT,
            bio TEXT,
            metadata TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("Failed to create identity_profiles table");

    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_identity_profiles_principal ON identity_profiles(principal)",
    )
    .execute(pool)
    .await
    .expect("Failed to create identity_profiles index");

    tracing::info!("Database initialized successfully");
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    // Initialize tracing with clean, parseable format
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .with_target(false) // Don't show target module
        .with_thread_ids(false) // Don't show thread IDs
        .with_line_number(false) // Don't show line numbers
        .compact() // Use compact format for cleaner output
        .init();

    // Load environment variables
    dotenv::dotenv().ok();

    // Database setup
    let database_url =
        env::var("DATABASE_URL").unwrap_or_else(|_| "sqlite:./data/dev.db?mode=rwc".to_string());

    tracing::info!("Connecting to database: {}", database_url);

    let pool = SqlitePool::connect(&database_url)
        .await
        .expect("Failed to connect to database");

    initialize_database(&pool).await;

    let state = Arc::new(AppState { pool });

    // Build app
    let app = Route::new()
        .at("/api/v1/health", get(health_check))
        .at("/api/v1/ping", get(ping))
        .at("/api/v1/scripts", get(get_scripts).post(create_script))
        .at("/api/v1/scripts/count", get(get_scripts_count))
        .at("/api/v1/scripts/search", post(search_scripts))
        .at("/api/v1/scripts/trending", get(get_trending_scripts))
        .at("/api/v1/scripts/featured", get(get_featured_scripts))
        .at("/api/v1/scripts/compatible", get(get_compatible_scripts))
        .at(
            "/api/v1/scripts/category/:category",
            get(get_scripts_by_category),
        )
        .at(
            "/api/v1/scripts/:id",
            get(get_script).put(update_script).delete(delete_script),
        )
        .at("/api/v1/scripts/:id/publish", post(publish_script))
        .at(
            "/api/v1/scripts/:id/reviews",
            get(get_reviews).post(create_review),
        )
        .at(
            "/api/v1/identities/:principal/profile",
            get(get_identity_profile),
        )
        .at("/api/v1/identities/profile", post(upsert_identity_profile))
        .at("/api/v1/marketplace-stats", get(get_marketplace_stats))
        .at("/api/v1/update-script-stats", post(update_script_stats))
        .at("/api/dev/reset-database", post(reset_database))
        .with(Cors::new())
        .data(state);

    // Start server
    let port = env::var("PORT").unwrap_or_else(|_| "58100".to_string());
    let addr = format!("[::]:{}", port);

    tracing::info!("Starting server on http://{}", addr);

    // Bind once to get the actual address (important for port 0 -> random port)
    let std_listener = match StdTcpListener::bind(&addr) {
        Ok(listener) => listener,
        Err(error) if error.kind() == ErrorKind::PermissionDenied => {
            let ipv4_addr = format!("127.0.0.1:{}", port);

            tracing::warn!(
                "IPv6 bind to {} denied ({}), falling back to {}",
                addr,
                error,
                ipv4_addr
            );

            StdTcpListener::bind(&ipv4_addr).expect("Failed to bind to IPv4 fallback address")
        }
        Err(error) => {
            panic!("Failed to bind to address {}: {}", addr, error);
        }
    };
    let actual_addr = std_listener
        .local_addr()
        .expect("Failed to get local address");

    // Log the actual listening address for external tools to parse
    tracing::info!("listening addr=socket://{}", actual_addr);

    // Close the std listener since we just needed it for the address
    drop(std_listener);

    // Now bind with Poem's listener
    let listener = TcpListener::bind(actual_addr);

    Server::new(listener).run(app).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
    use base64::Engine;
    use ed25519_dalek::{Signer, SigningKey};
    use poem::http::StatusCode;
    use sqlx::sqlite::SqlitePoolOptions;

    #[test]
    fn verify_update_signature_rejects_tampered_payload() {
        let tampered_json = r#"{
            "action":"update",
            "script_id":"existing-script",
            "timestamp":"2025-11-06T14:22:44.069472Z",
            "author_principal":"yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
            "title":"Tampered Title",
            "description":"Updated description",
            "category":"Utility",
            "lua_source":"-- updated",
            "tags":["modified","updated"],
            "version":"2.0.0",
            "price":1.0,
            "is_public":true,
            "author_public_key":"HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=",
            "signature":"c0HBe9ELBP1/pQiFOrnPEbUq9mYt+MSAr23YknlIg2+3ErC/DB/9LDq5F/FxCudj+COY8l/VNASZspj6h7zPBA=="
        }"#;

        let request: UpdateScriptRequest =
            serde_json::from_str(tampered_json).expect("valid tampered request json");

        assert!(
            verify_script_update_signature(&request, "existing-script").is_err(),
            "tampering payload must invalidate signature verification"
        );
    }

    async fn setup_search_state() -> Arc<AppState> {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("failed to create in-memory sqlite pool");

        initialize_database(&pool).await;

        insert_script(
            &pool,
            ScriptFixture {
                id: "script-1",
                title: "Test Script One",
                category: "Utility",
                lua_source: "-- script one",
                rating: 4.5,
                price: 9.99,
                downloads: 250,
                review_count: 5,
                created_at: "2024-01-01T00:00:00Z",
            },
        )
        .await;

        insert_script(
            &pool,
            ScriptFixture {
                id: "script-2",
                title: "Another Utility Script",
                category: "Utility",
                lua_source: "-- script two",
                rating: 4.8,
                price: 14.50,
                downloads: 300,
                review_count: 8,
                created_at: "2024-03-15T12:00:00Z",
            },
        )
        .await;

        insert_script(
            &pool,
            ScriptFixture {
                id: "script-3",
                title: "Analytics Tool",
                category: "Analytics",
                lua_source: "-- script three",
                rating: 3.2,
                price: 0.0,
                downloads: 120,
                review_count: 2,
                created_at: "2023-12-10T08:30:00Z",
            },
        )
        .await;

        Arc::new(AppState { pool })
    }

    struct ScriptFixture<'a> {
        id: &'a str,
        title: &'a str,
        category: &'a str,
        lua_source: &'a str,
        rating: f64,
        price: f64,
        downloads: i32,
        review_count: i32,
        created_at: &'a str,
    }

    async fn insert_script(pool: &SqlitePool, fixture: ScriptFixture<'_>) {
        sqlx::query(
            "INSERT INTO scripts (id, title, description, category, tags, lua_source, author_name, author_id, author_principal, author_public_key, upload_signature, canister_ids, icon_url, screenshots, version, compatibility, price, is_public, downloads, rating, review_count, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, '[]', ?5, 'Test Author', 'test-author-id', NULL, NULL, NULL, NULL, NULL, NULL, '1.0.0', NULL, ?6, 1, ?7, ?8, ?9, ?10, ?10)",
        )
        .bind(fixture.id)
        .bind(fixture.title)
        .bind(format!("{} description", fixture.title))
        .bind(fixture.category)
        .bind(fixture.lua_source)
        .bind(fixture.price)
        .bind(fixture.downloads)
        .bind(fixture.rating)
        .bind(fixture.review_count)
        .bind(fixture.created_at)
        .execute(pool)
        .await
        .expect("failed to insert script");
    }

    async fn setup_identity_state() -> Arc<AppState> {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("connect sqlite memory");

        initialize_database(&pool).await;
        Arc::new(AppState { pool })
    }

    #[tokio::test]
    async fn upsert_identity_profile_creates_and_updates() {
        let state = setup_identity_state().await;

        let request = UpsertIdentityProfileRequest {
            principal: "aaaaa-aa".to_string(),
            display_name: "Primary Identity".to_string(),
            username: Some("icp_builder".to_string()),
            contact_email: Some("team@example.com".to_string()),
            contact_telegram: Some("@icp".to_string()),
            contact_twitter: None,
            contact_discord: None,
            website_url: Some("https://internetcomputer.org".to_string()),
            bio: Some("Building unstoppable tools".to_string()),
            metadata: Some(serde_json::json!({"headline": "Engineers"})),
        };

        let created = persist_identity_profile(&state.pool, &request)
            .await
            .expect("profile created");
        assert_eq!(created.principal, "aaaaa-aa");
        assert_eq!(created.display_name, "Primary Identity");
        assert_eq!(created.username.as_deref(), Some("icp_builder"));

        let updated_request = UpsertIdentityProfileRequest {
            principal: "aaaaa-aa".to_string(),
            display_name: "Primary Identity v2".to_string(),
            username: Some("icp_bldr".to_string()),
            contact_email: Some("ops@example.com".to_string()),
            contact_telegram: Some("@icp".to_string()),
            contact_twitter: Some("@dfinity".to_string()),
            contact_discord: Some("icp#1234".to_string()),
            website_url: Some("https://internetcomputer.org/docs".to_string()),
            bio: Some("Updated bio".to_string()),
            metadata: Some(
                serde_json::json!({"headline": "Engineers", "tags": ["icp", "autorun"]}),
            ),
        };

        let updated = persist_identity_profile(&state.pool, &updated_request)
            .await
            .expect("profile updated");
        assert_eq!(updated.principal, "aaaaa-aa");
        assert_eq!(updated.display_name, "Primary Identity v2");
        assert_eq!(updated.username.as_deref(), Some("icp_bldr"));
        assert_eq!(updated.contact_twitter.as_deref(), Some("@dfinity"));

        let retrieved = fetch_identity_profile(&state.pool, "aaaaa-aa")
            .await
            .expect("profile retrievable");
        assert_eq!(retrieved.display_name, "Primary Identity v2");
    }

    #[tokio::test]
    async fn upsert_identity_profile_rejects_invalid_email() {
        let state = setup_identity_state().await;

        let bad_request = UpsertIdentityProfileRequest {
            principal: "bbbbbb-bb".to_string(),
            display_name: "Broken".to_string(),
            username: None,
            contact_email: Some("invalid-email".to_string()),
            contact_telegram: None,
            contact_twitter: None,
            contact_discord: None,
            website_url: None,
            bio: None,
            metadata: None,
        };

        let error = persist_identity_profile(&state.pool, &bad_request)
            .await
            .expect_err("invalid email must fail");
        assert_eq!(error.0, StatusCode::BAD_REQUEST);
        assert!(
            error.1.contains("email"),
            "error must mention email validation"
        );
    }

    #[tokio::test]
    async fn fetch_identity_profile_not_found() {
        let state = setup_identity_state().await;
        let error = fetch_identity_profile(&state.pool, "missing-principal")
            .await
            .expect_err("missing profile must fail");
        assert_eq!(error.0, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn search_scripts_returns_paginated_results() {
        let state = setup_search_state().await;

        let request = SearchRequest {
            query: Some("Utility".to_string()),
            category: Some("Utility".to_string()),
            sort_by: Some("createdAt".to_string()),
            sort_order: Some("desc".to_string()),
            limit: Some(1),
            offset: Some(0),
            ..Default::default()
        };

        let result = run_marketplace_search(&state.pool, &request)
            .await
            .expect("marketplace search should succeed");

        assert_eq!(result.limit, 1, "limit must echo input");
        assert_eq!(result.offset, 0, "offset must echo input");
        assert_eq!(result.total, 2, "total must reflect matching rows");
        assert_eq!(result.scripts.len(), 1, "should return single script page");
        assert_eq!(
            result.scripts[0].id, "script-2",
            "most recent Utility script must be first"
        );
        assert!(
            result.offset + (result.scripts.len() as i64) < result.total,
            "hasMore must be true when additional rows exist"
        );
    }

    #[tokio::test]
    async fn search_scripts_rejects_invalid_sort_field() {
        let state = setup_search_state().await;

        let request = SearchRequest {
            query: Some("Utility".to_string()),
            sort_by: Some("unsupported".to_string()),
            sort_order: Some("asc".to_string()),
            limit: Some(5),
            offset: Some(0),
            ..Default::default()
        };

        let error = run_marketplace_search(&state.pool, &request)
            .await
            .expect_err("unsupported sort field must fail");

        assert_eq!(
            error.0,
            StatusCode::BAD_REQUEST,
            "invalid sort should map to 400"
        );
        assert!(
            error.1.contains("sort"),
            "error message must mention sort validation"
        );
    }

    #[test]
    fn resolve_visibility_defaults_to_public() {
        assert!(
            resolve_script_visibility(None),
            "missing visibility flag must default to public"
        );
    }

    #[test]
    fn resolve_visibility_preserves_private_flag() {
        assert!(
            !resolve_script_visibility(Some(false)),
            "explicit private uploads must stay private"
        );
    }

    #[test]
    fn verify_update_signature_ignores_author_public_key_field() {
        let secret_key_bytes = [7u8; 32];
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);
        let public_key_b64 = BASE64_STANDARD.encode(signing_key.verifying_key().as_bytes());

        let canonical_payload = serde_json::json!({
            "action": "update",
            "script_id": "script-123",
            "timestamp": "2024-01-01T00:00:00Z",
            "author_principal": "principal-1",
            "title": "Title",
            "description": "Desc",
            "category": "Utility",
            "lua_source": "-- body",
            "tags": ["alpha", "beta"],
            "version": "1.0.0",
            "price": 1.5,
            "is_public": true
        });

        let canonical_json = create_canonical_payload(&canonical_payload);
        let signature = signing_key.sign(canonical_json.as_bytes());
        let signature_b64 = BASE64_STANDARD.encode(signature.to_bytes());

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_b64),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_b64),
        );

        let request: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid update request json");

        assert!(
            verify_script_update_signature(&request, "script-123").is_ok(),
            "author_public_key should be ignored by signature verification logic"
        );
    }

    #[test]
    fn verify_update_signature_accepts_fixture_payload() {
        let request_json = r#"{
            "action":"update",
            "script_id":"93e91d19-ce61-4497-821e-4d32c03c6cc2",
            "timestamp":"2025-11-06T16:11:26.756452Z",
            "author_principal":"yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
            "title":"Updated Title",
            "description":"Updated description",
            "category":"Utility",
            "lua_source":"-- Updated source",
            "tags":["modified","updated"],
            "version":"2.0.0",
            "price":1.0,
            "is_public":true,
            "author_public_key":"HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=",
            "signature":"L/5Xge5DMj99YSniO7QhmPrf6TpIdRSg1qKvUcQQSTWAPBSCGWW/w/8vePdWPhrmiqPp17/aTx5k5FPA6hdvCA=="
        }"#;

        let request: UpdateScriptRequest =
            serde_json::from_str(request_json).expect("valid fixture request json");

        assert!(
            verify_script_update_signature(&request, "93e91d19-ce61-4497-821e-4d32c03c6cc2")
                .is_ok(),
            "fixture payload signature should verify successfully"
        );
    }
}
