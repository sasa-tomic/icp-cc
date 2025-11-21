mod auth;
mod cleanup;
mod db;
mod middleware;
mod models;
mod repositories;
mod responses;
mod services;

#[cfg(test)]
use auth::create_canonical_payload;

use models::*;
use poem::{
    delete, get, handler,
    http::StatusCode,
    listener::TcpListener,
    middleware::Cors,
    post,
    web::{Data, Json, Path, Query},
    EndpointExt, IntoResponse, Response, Route, Server,
};
use responses::error_response;
use services::{AccountService, ReviewService, ScriptService};
use sqlx::sqlite::SqlitePool;
use std::{env, io::ErrorKind, net::TcpListener as StdTcpListener, sync::Arc};

#[cfg(test)]
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
        "createdAt" => "scripts.created_at",
        "rating" => "scripts.rating",
        "downloads" => "scripts.downloads",
        "price" => "scripts.price",
        "title" => "scripts.title",
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

    conditions.push("scripts.is_public = ?".to_string());
    condition_binds.push(BindValue::Bool(true));

    if let Some(query) = request
        .query
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        let like_pattern = format!("%{}%", query);
        conditions.push(
            "(scripts.title LIKE ? OR scripts.description LIKE ? OR scripts.category LIKE ?)"
                .to_string(),
        );
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
        conditions.push("scripts.category = ?".to_string());
        condition_binds.push(BindValue::Text(category.to_string()));
    }

    if let Some(min_rating) = request.min_rating {
        conditions.push("scripts.rating >= ?".to_string());
        condition_binds.push(BindValue::Float(min_rating));
    }

    if let Some(max_price) = request.max_price {
        conditions.push("scripts.price <= ?".to_string());
        condition_binds.push(BindValue::Float(max_price));
    }

    let mut where_clause = String::new();
    if !conditions.is_empty() {
        where_clause.push_str(" WHERE ");
        where_clause.push_str(&conditions.join(" AND "));
    }

    let search_sql = format!(
        "SELECT {} FROM scripts LEFT JOIN accounts ON scripts.owner_account_id = accounts.id{} ORDER BY {} {} LIMIT ? OFFSET ?",
        SCRIPT_COLUMNS_WITH_ACCOUNT, where_clause, sort_column, sort_order
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

#[cfg(test)]
mod signature_tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    /// Helper: Sign a canonical JSON payload per ACCOUNT_PROFILES_DESIGN.md
    /// Returns (hex_signature, hex_public_key)
    fn sign_test_payload(signing_key: &SigningKey, canonical_json: &str) -> (String, String) {
        use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
        // Standard Ed25519: sign message directly (RFC 8032)
        // The algorithm does SHA-512 internally as part of the signature process
        let signature = signing_key.sign(canonical_json.as_bytes());

        // Return base64-encoded signature and public key (matches Flutter app format)
        let signature_b64 = B64.encode(signature.to_bytes());
        let public_key_b64 = B64.encode(signing_key.verifying_key().as_bytes());

        (signature_b64, public_key_b64)
    }

    #[test]
    fn dart_generated_update_signature_verifies() {
        let secret_key_bytes = [11u8; 32];
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);

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
        let (signature_hex, public_key_hex) = sign_test_payload(&signing_key, &canonical_json);

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_hex),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_hex),
        );

        let req: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid canonical update request");

        assert!(
            middleware::auth::verify_script_update_signature(
                &req,
                "41935708-8561-4424-a42f-cba44e26785a"
            )
            .is_ok(),
            "Expected canonical payload signature to verify successfully"
        );
    }

    #[test]
    fn verify_update_signature_allows_extra_fields_without_affecting_signature() {
        let secret_key_bytes = [7u8; 32];
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);

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
        let (signature_hex, public_key_hex) = sign_test_payload(&signing_key, &canonical_json);

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_hex),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_hex),
        );
        request_payload.insert(
            "extra_field".to_string(),
            serde_json::Value::String("should-be-ignored".to_string()),
        );

        let request: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid update request json");

        assert!(
            middleware::auth::verify_script_update_signature(&request, "script-123").is_ok(),
            "extra fields outside canonical payload must not affect signature verification"
        );
    }
}

fn is_development() -> bool {
    env::var("ENVIRONMENT").unwrap_or_default() == "development"
}

/// Verifies that the authenticated user owns the script
async fn verify_script_ownership(
    state: &Arc<AppState>,
    script_id: &str,
    public_key: &Option<String>,
) -> Result<(), Response> {
    // Get script to check ownership
    let script = match state.script_service.get_script(script_id).await {
        Ok(Some(script)) => script,
        Ok(None) => {
            tracing::warn!("Script ownership check failed: {} not found", script_id);
            return Err(error_response(StatusCode::NOT_FOUND, "Script not found"));
        }
        Err(e) => {
            tracing::error!("Failed to get script for ownership check: {}", e);
            return Err(error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to verify ownership",
            ));
        }
    };

    // Get authenticated user's account ID from public key
    let user_account_id = if let Some(ref pk) = public_key {
        match state
            .script_service
            .account_repo
            .find_public_key_by_value(pk)
            .await
        {
            Ok(Some(account_key)) => Some(account_key.account_id),
            Ok(None) => None,
            Err(e) => {
                tracing::error!("Failed to lookup account for ownership check: {}", e);
                return Err(error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to verify ownership",
                ));
            }
        }
    } else {
        None
    };

    // Verify ownership
    if script.owner_account_id != user_account_id {
        tracing::warn!(
            "Ownership check failed: script owned by {:?}, user is {:?}",
            script.owner_account_id,
            user_account_id
        );
        return Err(error_response(
            StatusCode::FORBIDDEN,
            "Only the script owner can perform this operation",
        ));
    }

    Ok(())
}

/// Builds the canonical payload for script upload signature verification
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
    let include_private = params.include_private.unwrap_or(false);

    match state
        .script_service
        .get_scripts(limit, offset, params.category, include_private)
        .await
    {
        Ok((scripts, total)) => Json(serde_json::json!({
            "success": true,
            "data": {
                "scripts": scripts,
                "total": total,
                "hasMore": (offset + limit) < total as i32
            }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get scripts: {}", e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get scripts")
        }
    }
}

#[handler]
async fn get_script(
    Path(script_id): Path<String>,
    Query(_query): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.script_service.get_script(&script_id).await {
        Ok(Some(script)) => Json(serde_json::json!({
            "success": true,
            "data": script
        }))
        .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to get script {}: {}", script_id, e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get script")
        }
    }
}

#[handler]
async fn get_scripts_count(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_scripts_count().await {
        Ok(count) => Json(serde_json::json!({
            "success": true,
            "data": { "count": count }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get count: {}", e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get count")
        }
    }
}

#[handler]
async fn get_marketplace_stats(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_marketplace_stats().await {
        Ok((scripts_count, total_downloads, avg_rating)) => Json(serde_json::json!({
            "success": true,
            "data": {
                "totalScripts": scripts_count,
                "totalDownloads": total_downloads,
                "averageRating": avg_rating,
                "timestamp": chrono::Utc::now().to_rfc3339()
            }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get marketplace stats: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get marketplace stats",
            )
        }
    }
}

#[cfg(test)]
fn resolve_script_visibility(flag: Option<bool>) -> bool {
    flag.unwrap_or(true)
}

#[handler]
async fn create_script(
    Json(req): Json<CreateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script creation", || {
        middleware::auth::build_upload_payload(&req)
    }) {
        return *response;
    }

    // Create script via service
    match state.script_service.create_script(req).await {
        Ok(script) => {
            tracing::info!(
                "Created script: {} (slug: {}, public: {})",
                script.id,
                script.slug,
                script.is_public
            );
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": {
                        "id": script.id,
                        "slug": script.slug,
                        "title": script.title,
                        "created_at": script.created_at
                    }
                })),
            )
                .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to create script: {}", e);
            let status = if e.contains("owned by another account") {
                StatusCode::FORBIDDEN
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &e)
        }
    }
}

// Account Profiles Endpoints

#[handler]
async fn register_account(
    Json(payload): Json<RegisterAccountRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.account_service.register_account(payload).await {
        Ok(account) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "success": true,
                "data": account
            })),
        )
            .into_response(),
        Err(message) => {
            tracing::warn!("Failed to register account: {}", message);
            let status =
                if message.contains("already exists") || message.contains("already registered") {
                    StatusCode::CONFLICT
                } else if message.contains("Invalid username")
                    || message.contains("Timestamp out of range")
                {
                    StatusCode::BAD_REQUEST
                } else if message.contains("Signature verification failed")
                    || message.contains("replay attack")
                {
                    StatusCode::UNAUTHORIZED
                } else {
                    StatusCode::INTERNAL_SERVER_ERROR
                };
            error_response(status, &message)
        }
    }
}

#[handler]
async fn get_account(Path(username): Path<String>, Data(state): Data<&Arc<AppState>>) -> Response {
    match state.account_service.get_account(&username).await {
        Ok(Some(account)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": account
            })),
        )
            .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Account not found"),
        Err(message) => {
            tracing::error!("Failed to get account: {}", message);
            let status = if message.contains("Invalid username") {
                StatusCode::BAD_REQUEST
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &message)
        }
    }
}

#[handler]
async fn get_account_by_public_key(
    Path(public_key): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .account_service
        .get_account_by_public_key(&public_key)
        .await
    {
        Ok(Some(account)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": account
            })),
        )
            .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Account not found for public key"),
        Err(message) => {
            tracing::error!("Failed to get account by public key: {}", message);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, &message)
        }
    }
}

#[handler]
async fn update_account(
    Path(username): Path<String>,
    Json(payload): Json<UpdateAccountRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .account_service
        .update_profile(&username, payload)
        .await
    {
        Ok(account) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": account
            })),
        )
            .into_response(),
        Err(message) => {
            tracing::warn!("Failed to update account: {}", message);
            let status = if message.contains("Account not found") {
                StatusCode::NOT_FOUND
            } else if message.contains("Invalid username")
                || message.contains("Timestamp out of range")
            {
                StatusCode::BAD_REQUEST
            } else if message.contains("Signature verification failed")
                || message.contains("replay attack")
                || message.contains("not active")
                || message.contains("does not belong")
            {
                StatusCode::UNAUTHORIZED
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &message)
        }
    }
}

#[handler]
async fn add_account_key(
    Path(username): Path<String>,
    Json(payload): Json<AddPublicKeyRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .account_service
        .add_public_key(&username, payload)
        .await
    {
        Ok(key) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "success": true,
                "data": key
            })),
        )
            .into_response(),
        Err(message) => {
            tracing::warn!("Failed to add public key: {}", message);
            let status = if message.contains("Account not found")
                || message.contains("Key not found")
            {
                StatusCode::NOT_FOUND
            } else if message.contains("already registered") || message.contains("Maximum number") {
                StatusCode::CONFLICT
            } else if message.contains("Invalid username")
                || message.contains("Timestamp out of range")
                || message.contains("last active key")
            {
                StatusCode::BAD_REQUEST
            } else if message.contains("Signature verification failed")
                || message.contains("replay attack")
                || message.contains("not active")
                || message.contains("does not belong")
            {
                StatusCode::UNAUTHORIZED
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &message)
        }
    }
}

#[handler]
async fn remove_account_key(
    Path((username, key_id)): Path<(String, String)>,
    Json(payload): Json<RemovePublicKeyRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .account_service
        .remove_public_key(&username, &key_id, payload)
        .await
    {
        Ok(key) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": key
            })),
        )
            .into_response(),
        Err(message) => {
            tracing::warn!("Failed to remove public key: {}", message);
            let status =
                if message.contains("Account not found") || message.contains("Key not found") {
                    StatusCode::NOT_FOUND
                } else if message.contains("Invalid username")
                    || message.contains("Timestamp out of range")
                    || message.contains("last active key")
                {
                    StatusCode::BAD_REQUEST
                } else if message.contains("Signature verification failed")
                    || message.contains("replay attack")
                    || message.contains("not active")
                    || message.contains("does not belong")
                {
                    StatusCode::UNAUTHORIZED
                } else {
                    StatusCode::INTERNAL_SERVER_ERROR
                };
            error_response(status, &message)
        }
    }
}

// Admin Account Operations

#[handler]
async fn admin_disable_key(
    Path((username, key_id)): Path<(String, String)>,
    Json(payload): Json<models::AdminDisableKeyRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .account_service
        .admin_disable_key(&username, &key_id, &payload.reason)
        .await
    {
        Ok(key) => {
            tracing::info!(
                "Admin disabled key {} for account {}: {}",
                key_id,
                username,
                payload.reason
            );
            (
                StatusCode::OK,
                Json(serde_json::json!({
                    "success": true,
                    "data": key
                })),
            )
                .into_response()
        }
        Err(message) => {
            tracing::warn!("Admin failed to disable key: {}", message);
            let status = if message.contains("not found") {
                StatusCode::NOT_FOUND
            } else if message.contains("Invalid username") {
                StatusCode::BAD_REQUEST
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &message)
        }
    }
}

#[handler]
async fn admin_add_recovery_key(
    Path(username): Path<String>,
    Json(payload): Json<models::AdminAddRecoveryKeyRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .account_service
        .admin_add_recovery_key(&username, &payload.public_key, &payload.reason)
        .await
    {
        Ok(key) => {
            tracing::info!(
                "Admin added recovery key for account {}: {}",
                username,
                payload.reason
            );
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": key
                })),
            )
                .into_response()
        }
        Err(message) => {
            tracing::warn!("Admin failed to add recovery key: {}", message);
            let status = if message.contains("not found") {
                StatusCode::NOT_FOUND
            } else if message.contains("Invalid username")
                || message.contains("Maximum number")
                || message.contains("already registered")
            {
                StatusCode::BAD_REQUEST
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &message)
        }
    }
}

#[handler]
async fn update_script(
    Path(script_id): Path<String>,
    Json(req): Json<UpdateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script update", || {
        middleware::auth::build_canonical_update_payload(&req, &script_id)
    }) {
        return *response;
    }

    // Check script ownership
    if let Err(response) = verify_script_ownership(state, &script_id, &req.author_public_key).await
    {
        return response;
    }

    // Update script via service
    match state.script_service.update_script(&script_id, req).await {
        Ok(script) => {
            tracing::info!(
                "Updated script: {} (version: {})",
                script.id,
                script.version
            );
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": script.id,
                    "updated_at": script.updated_at
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to update script {}: {}", script_id, e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                &format!("Failed to update script: {}", e),
            )
        }
    }
}

#[handler]
async fn delete_script(
    Path(script_id): Path<String>,
    Json(req): Json<DeleteScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script deletion", || {
        middleware::auth::build_deletion_payload(&req, &script_id)
    }) {
        return *response;
    }

    // Check script ownership
    if let Err(response) = verify_script_ownership(state, &script_id, &req.author_public_key).await
    {
        return response;
    }

    // Check if script exists
    match state.script_service.check_script_exists(&script_id).await {
        Ok(true) => {
            // Delete script via service (soft delete)
            match state.script_service.delete_script(&script_id).await {
                Ok(()) => {
                    tracing::info!("Soft deleted script: {}", script_id);
                    Json(serde_json::json!({
                        "success": true,
                        "message": "Script deleted successfully"
                    }))
                    .into_response()
                }
                Err(e) => {
                    tracing::error!("Failed to delete script {}: {}", script_id, e);
                    error_response(
                        StatusCode::INTERNAL_SERVER_ERROR,
                        &format!("Failed to delete script: {}", e),
                    )
                }
            }
        }
        Ok(false) => {
            tracing::warn!("Script deletion failed: {} not found", script_id);
            error_response(StatusCode::NOT_FOUND, "Script not found")
        }
        Err(e) => {
            tracing::error!("Failed to check script existence: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to check script existence",
            )
        }
    }
}

#[handler]
async fn search_scripts(
    Json(request): Json<SearchRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.script_service.search_scripts(&request).await {
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
    match state
        .script_service
        .get_scripts_by_category(&category, 100)
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
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get scripts by category",
            )
        }
    }
}

#[handler]
async fn publish_script(
    Path(script_id): Path<String>,
    Json(req): Json<UpdateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script publish", || {
        middleware::auth::build_publish_payload(&req, &script_id)
    }) {
        return *response;
    }

    // Publish script via service
    match state.script_service.publish_script(&script_id).await {
        Ok(script) => {
            tracing::info!(
                "Published script: {} (is_public: {})",
                script.id,
                script.is_public
            );
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": script.id,
                    "updated_at": script.updated_at
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to publish script {}: {}", script_id, e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                &format!("Failed to publish script: {}", e),
            )
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

    match state
        .review_service
        .get_reviews(&script_id, limit, offset)
        .await
    {
        Ok((reviews, total)) => Json(serde_json::json!({
            "success": true,
            "data": {
                "reviews": reviews,
                "total": total,
                "hasMore": (offset + limit) < total
            }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get reviews for script {}: {}", script_id, e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get reviews")
        }
    }
}

#[handler]
async fn create_review(
    Path(script_id): Path<String>,
    Json(req): Json<CreateReviewRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.review_service.create_review(&script_id, req).await {
        Ok(review) => {
            tracing::info!(
                "Created review for script {} by user {}",
                script_id,
                review.user_id
            );
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": review
                })),
            )
                .into_response()
        }
        Err(err_msg) => {
            tracing::warn!("Failed to create review: {}", err_msg);
            let status = if err_msg.contains("not found") {
                StatusCode::NOT_FOUND
            } else if err_msg.contains("already reviewed") {
                StatusCode::CONFLICT
            } else if err_msg.contains("must be between") {
                StatusCode::BAD_REQUEST
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &err_msg)
        }
    }
}

#[handler]
async fn get_trending_scripts(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_trending(20).await {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get trending scripts: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get trending scripts",
            )
        }
    }
}

#[handler]
async fn get_featured_scripts(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_featured(4.5, 10, 10).await {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get featured scripts: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get featured scripts",
            )
        }
    }
}

#[handler]
async fn get_compatible_scripts(
    Query(_params): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // For now, return all compatible scripts
    match state.script_service.get_compatible("all", 20).await {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get compatible scripts: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get compatible scripts",
            )
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
            match state
                .script_service
                .increment_downloads(&req.script_id)
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
                    error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to update stats")
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

    if reset_scripts.is_ok() && reset_reviews.is_ok() {
        Json(serde_json::json!({
            "success": true,
            "message": "Database reset successfully"
        }))
        .into_response()
    } else {
        tracing::error!(
            "Failed to reset database: scripts={:?}, reviews={:?}",
            reset_scripts.err(),
            reset_reviews.err()
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

    db::initialize_database(&pool).await;

    // Clone pool for background cleanup job before moving it to state
    let cleanup_pool = pool.clone();

    let state = Arc::new(AppState {
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        pool,
    });

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
        // Account Profiles endpoints
        .at("/api/v1/accounts", post(register_account))
        .at(
            "/api/v1/accounts/:username",
            get(get_account).patch(update_account),
        )
        .at(
            "/api/v1/accounts/by-public-key/:public_key",
            get(get_account_by_public_key),
        )
        .at("/api/v1/accounts/:username/keys", post(add_account_key))
        .at(
            "/api/v1/accounts/:username/keys/:key_id",
            delete(remove_account_key),
        )
        // Admin Account endpoints (require admin authentication)
        .at(
            "/api/v1/admin/accounts/:username/keys/:key_id/disable",
            post(admin_disable_key).with(middleware::AdminAuth),
        )
        .at(
            "/api/v1/admin/accounts/:username/recovery-key",
            post(admin_add_recovery_key).with(middleware::AdminAuth),
        )
        .at("/api/v1/marketplace-stats", get(get_marketplace_stats))
        .at("/api/v1/update-script-stats", post(update_script_stats))
        .at("/api/dev/reset-database", post(reset_database))
        .with(Cors::new())
        .data(state);

    // Start server
    let port = env::var("PORT").unwrap_or_else(|_| "58000".to_string());
    let addr = format!("[::]:{}", port);

    tracing::info!("Starting server on http://{}", addr);

    // Bind once to get the actual address (important for port 0 -> random port)
    let (std_listener, bind_addr) = match StdTcpListener::bind(&addr) {
        Ok(listener) => (listener, addr.clone()),
        Err(error) if error.kind() == ErrorKind::PermissionDenied => {
            let ipv4_addr = format!("127.0.0.1:{}", port);

            tracing::warn!(
                "IPv6 bind to {} denied ({}), falling back to {}",
                addr,
                error,
                ipv4_addr
            );

            (
                StdTcpListener::bind(&ipv4_addr).expect("Failed to bind to IPv4 fallback address"),
                ipv4_addr,
            )
        }
        Err(error) => {
            panic!("Failed to bind to address {}: {}", addr, error);
        }
    };

    let free_port = std_listener
        .local_addr()
        .expect("Failed to get local address")
        .port();

    // Construct the final bind address using the actual port
    let final_bind_addr = if bind_addr.starts_with("[::]") {
        format!("[::]:{}", free_port)
    } else {
        format!("0.0.0.0:{}", free_port)
    };

    // Log the actual listening address for external tools to parse
    tracing::info!("listening on addr=socket://{}", final_bind_addr);

    // Start background cleanup job for signature audit
    cleanup::start_audit_cleanup_job(cleanup_pool).await;

    // Close the std listener since we just needed it for the address
    drop(std_listener);

    // Now bind with Poem's listener
    let listener = TcpListener::bind(final_bind_addr);

    Server::new(listener).run(app).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use poem::http::StatusCode;
    use sqlx::sqlite::SqlitePoolOptions;

    /// Helper: Sign a canonical JSON payload per ACCOUNT_PROFILES_DESIGN.md
    /// Returns (hex_signature, hex_public_key)
    fn sign_test_payload(signing_key: &SigningKey, canonical_json: &str) -> (String, String) {
        use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
        // Standard Ed25519: sign message directly (RFC 8032)
        // The algorithm does SHA-512 internally as part of the signature process
        let signature = signing_key.sign(canonical_json.as_bytes());

        // Return base64-encoded signature and public key (matches Flutter app format)
        let signature_b64 = B64.encode(signature.to_bytes());
        let public_key_b64 = B64.encode(signing_key.verifying_key().as_bytes());

        (signature_b64, public_key_b64)
    }

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
            middleware::auth::verify_script_update_signature(&request, "existing-script").is_err(),
            "tampering payload must invalidate signature verification"
        );
    }

    async fn setup_search_state() -> Arc<AppState> {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .expect("failed to create in-memory sqlite pool");

        db::initialize_database(&pool).await;

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

        Arc::new(AppState {
            account_service: AccountService::new(pool.clone()),
            script_service: ScriptService::new(pool.clone()),
            review_service: ReviewService::new(pool.clone()),
            pool,
        })
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
            "INSERT INTO scripts (id, slug, owner_account_id, title, description, category, tags, lua_source, author_principal, author_public_key, upload_signature, canister_ids, icon_url, screenshots, version, compatibility, price, is_public, downloads, rating, review_count, created_at, updated_at) VALUES (?1, ?2, NULL, ?3, ?4, ?5, '[]', ?6, NULL, NULL, NULL, NULL, NULL, NULL, '1.0.0', NULL, ?7, 1, ?8, ?9, ?10, ?11, ?11)",
        )
        .bind(fixture.id)
        .bind(format!("test-{}", fixture.id))  // Generate slug from id
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
        let (signature_hex, public_key_hex) = sign_test_payload(&signing_key, &canonical_json);

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_hex),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_hex),
        );

        let request: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid update request json");

        assert!(
            middleware::auth::verify_script_update_signature(&request, "script-123").is_ok(),
            "author_public_key should be ignored by signature verification logic"
        );
    }

    #[test]
    fn verify_update_signature_accepts_fixture_payload() {
        // Regenerate with correct signature format
        let secret_key_bytes = [11u8; 32];
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);

        let canonical_payload = serde_json::json!({
            "action": "update",
            "script_id": "93e91d19-ce61-4497-821e-4d32c03c6cc2",
            "timestamp": "2025-11-06T16:11:26.756452Z",
            "author_principal": "yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
            "title": "Updated Title",
            "description": "Updated description",
            "category": "Utility",
            "lua_source": "-- Updated source",
            "tags": ["modified", "updated"],
            "version": "2.0.0",
            "price": 1.0,
            "is_public": true
        });

        let canonical_json = create_canonical_payload(&canonical_payload);
        let (signature_hex, public_key_hex) = sign_test_payload(&signing_key, &canonical_json);

        let mut request_payload = canonical_payload
            .as_object()
            .expect("canonical payload must be an object")
            .clone();
        request_payload.insert(
            "author_public_key".to_string(),
            serde_json::Value::String(public_key_hex),
        );
        request_payload.insert(
            "signature".to_string(),
            serde_json::Value::String(signature_hex),
        );

        let request: UpdateScriptRequest =
            serde_json::from_value(serde_json::Value::Object(request_payload))
                .expect("valid fixture request json");

        assert!(
            middleware::auth::verify_script_update_signature(
                &request,
                "93e91d19-ce61-4497-821e-4d32c03c6cc2"
            )
            .is_ok(),
            "fixture payload signature should verify successfully"
        );
    }
}
