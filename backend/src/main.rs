use icp_marketplace_api::{
    auth, cleanup, db, handlers, middleware,
    models::{self, *},
    repositories::PurchaseRepository,
    responses::error_response,
    services::{
        AccountService, PasskeyAuthenticationFinish, PasskeyRegistrationFinish, PasskeyService,
        PaymentService, ReviewService, ScriptService,
    },
    startup_checks::{
        is_development, verify_script_ownership, warn_if_broken_prod_passkey_rp,
        warn_if_icpay_unconfigured, warn_if_insecure_prod_admin_token,
    },
};
use poem::{
    delete, get, handler,
    http::StatusCode,
    listener::TcpListener,
    middleware::Cors,
    post,
    web::{Data, Json, Path, Query},
    EndpointExt, IntoResponse, Request, Response, Route, Server,
};
use sqlx::sqlite::SqlitePool;
use std::{env, io::ErrorKind, net::TcpListener as StdTcpListener, sync::Arc, time::Duration};
use tokio_util::sync::CancellationToken;

#[cfg(test)]
mod admin_token_tests {
    use icp_marketplace_api::startup_checks::{
        is_insecure_admin_token, warn_if_insecure_prod_admin_token,
    };

    #[test]
    fn default_token_is_detected() {
        assert!(is_insecure_admin_token("change-me-in-production"));
    }

    #[test]
    fn empty_token_is_detected() {
        assert!(is_insecure_admin_token(""));
    }

    #[test]
    fn real_token_is_not_detected() {
        assert!(!is_insecure_admin_token(
            "super-secret-operator-token-9f3a7c1e"
        ));
    }

    #[test]
    fn warning_fires_for_production_insecure_only() {
        assert!(warn_if_insecure_prod_admin_token(
            "production",
            "change-me-in-production"
        ));
        assert!(!warn_if_insecure_prod_admin_token(
            "development",
            "change-me-in-production"
        ));
        assert!(!warn_if_insecure_prod_admin_token(
            "production",
            "super-secret-operator-token-9f3a7c1e"
        ));
    }
}

/// Builds the canonical payload for script upload signature verification
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
    Query(query): Query<ScriptDetailQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let script = match state.script_service.get_script(&script_id).await {
        Ok(Some(script)) => script,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to get script {}: {}", script_id, e);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get script");
        }
    };

    // Entitlement gate. Free scripts (price <= 0) always ship the full bundle.
    // Paid scripts ship the bundle ONLY when the caller owns the script OR has
    // a purchase record; otherwise `bundle` is dropped (rendered as `null`) and
    // `purchased: false` so the UI can render a Buy CTA. This is the security
    // fix for the HIGH-severity leak where the public endpoint used to return
    // the full paid bundle to anyone.
    let entitled = if script.price <= 0.0 {
        true
    } else if let Some(account_id) = query.account_id.as_deref() {
        // Owner of the script is always entitled to their own bundle.
        if script.owner_account_id.as_deref() == Some(account_id) {
            true
        } else {
            match state
                .purchase_repo
                .exists_for_account_and_script(account_id, &script_id)
                .await
            {
                Ok(purchased) => purchased,
                Err(e) => {
                    tracing::error!(
                        "Failed to check purchase entitlement for account={} script={}: {}",
                        account_id,
                        script_id,
                        e
                    );
                    return error_response(
                        StatusCode::INTERNAL_SERVER_ERROR,
                        "Failed to verify purchase entitlement",
                    );
                }
            }
        }
    } else {
        false
    };

    let detail = if entitled {
        ScriptDetailResponse::entitled(script)
    } else {
        ScriptDetailResponse::locked(script)
    };

    Json(serde_json::json!({
        "success": true,
        "data": detail
    }))
    .into_response()
}

/// Lightweight browse-time preview (UX-6). Returns a CAPPED excerpt of the
/// source plus browse-relevant metadata instead of the full bundle, so the
/// Script Details dialog stops downloading the whole script just to show 50
/// lines. For paid scripts the cap is smaller and the full source is NEVER
/// sent. Public (no auth) — same reachability as `get_script` / `get_scripts`.
#[handler]
async fn get_script_preview(
    Path(script_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.script_service.get_script_preview(&script_id).await {
        Ok(Some(preview)) => Json(serde_json::json!({
            "success": true,
            "data": preview
        }))
        .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to get script preview {}: {}", script_id, e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get script preview",
            )
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

// ============================================================================
// Passkey Authentication Handlers
// ============================================================================

#[derive(Debug, serde::Deserialize)]
struct PasskeyRegisterStartRequest {
    account_id: String,
    username: String,
}

#[handler]
async fn passkey_register_start(
    Json(req): Json<PasskeyRegisterStartRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .passkey_service
        .start_registration(&req.account_id, &req.username)
        .await
    {
        Ok(result) => Json(serde_json::json!({
            "success": true,
            "data": result
        }))
        .into_response(),
        Err(e) => error_response(StatusCode::BAD_REQUEST, &e),
    }
}

#[handler]
async fn passkey_register_finish(
    Json(req): Json<PasskeyRegistrationFinish>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.passkey_service.finish_registration(req).await {
        Ok(passkey) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "success": true,
                "data": passkey
            })),
        )
            .into_response(),
        Err(e) => error_response(StatusCode::BAD_REQUEST, &e),
    }
}

#[derive(Debug, serde::Deserialize)]
struct PasskeyAuthStartRequest {
    account_id: String,
}

#[handler]
async fn passkey_authenticate_start(
    Json(req): Json<PasskeyAuthStartRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .passkey_service
        .start_authentication(&req.account_id)
        .await
    {
        Ok(result) => Json(serde_json::json!({
            "success": true,
            "data": result
        }))
        .into_response(),
        Err(e) => error_response(StatusCode::BAD_REQUEST, &e),
    }
}

#[handler]
async fn passkey_authenticate_finish(
    Json(req): Json<PasskeyAuthenticationFinish>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.passkey_service.finish_authentication(req).await {
        Ok(account_id) => Json(serde_json::json!({
            "success": true,
            "data": { "account_id": account_id }
        }))
        .into_response(),
        Err(e) => error_response(StatusCode::UNAUTHORIZED, &e),
    }
}

#[handler]
async fn passkey_list(
    Path(account_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.passkey_service.list_passkeys(&account_id).await {
        Ok(passkeys) => Json(serde_json::json!({
            "success": true,
            "data": passkeys
        }))
        .into_response(),
        Err(e) => error_response(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

#[derive(Debug, serde::Deserialize)]
struct PasskeyDeleteRequest {
    account_id: String,
}

#[handler]
async fn passkey_delete(
    Path(passkey_id): Path<String>,
    Json(req): Json<PasskeyDeleteRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .passkey_service
        .delete_passkey(&passkey_id, &req.account_id)
        .await
    {
        Ok(()) => Json(serde_json::json!({
            "success": true
        }))
        .into_response(),
        Err(e) => {
            let status = if e.contains("not found") {
                StatusCode::NOT_FOUND
            } else if e.contains("Cannot delete last") {
                StatusCode::BAD_REQUEST
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(status, &e)
        }
    }
}

// ============================================================================
// Vault Handlers
// ============================================================================
//
// ## A-4 W4 wire contract — opaque-blob store (zero-knowledge)
//
// The backend performs NO vault cryptography. The Dart client derives an
// Argon2id key from the user's password locally, encrypts the vault payload
// with AES-256-GCM via FFI, and POSTs the resulting OPAQUE BLOB. The server
// stores and returns the bytes verbatim — it never sees the password or the
// plaintext and has no decryption code path.
//
// ### Single source of truth for field names
//
// The wire field names are defined ONLY by the serde struct field names below
// (`account_id`, `encrypted_data`, `salt`, `nonce`). The Dart client (W2)
// MUST match these exactly.
//
// ### Shapes
//
// POST /api/v1/vault           (create)
// PUT  /api/v1/vault           (update)
//   Request body:
//     {
//       "account_id":     String,   // keypair principal that owns the vault
//       "encrypted_data": String,   // base64 of the AES-256-GCM ciphertext
//       "salt":           String,   // base64 of the Argon2id salt (16 bytes)
//       "nonce":          String    // base64 of the AES-GCM nonce (12 bytes)
//     }
//   Success response: 201 (POST) / 200 (PUT)
//     { "success": true }
//
// GET /api/v1/vault?account_id=...
//   Success response (200):
//     {
//       "success": true,
//       "data": {
//         "encrypted_data": String,  // base64 — identical bytes to what was POSTed
//         "salt":           String,
//         "nonce":          String
//       }
//     }
//   Not found (404): { "success": false, "error": "Vault not found" }

/// Base64-encoded opaque vault blob + owning account. See the wire-contract
/// doc above. Used for both POST (create) and PUT (update).
#[derive(Debug, serde::Deserialize)]
struct VaultBlobRequest {
    account_id: String,
    encrypted_data: String, // base64
    salt: String,           // base64
    nonce: String,          // base64
}

/// Decodes a base64 field from a [`VaultBlobRequest`]. Returns the decoded
/// bytes or a human-readable error string that the caller surfaces as a 400.
fn decode_blob_field(field: &'static str, encoded: &str) -> Result<Vec<u8>, String> {
    base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        .map_err(|e| format!("Invalid base64 for '{}': {}", field, e))
}

#[handler]
async fn vault_create(
    Json(req): Json<VaultBlobRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let encrypted_data = match decode_blob_field("encrypted_data", &req.encrypted_data) {
        Ok(v) => v,
        Err(e) => return error_response(StatusCode::BAD_REQUEST, &e),
    };
    let salt = match decode_blob_field("salt", &req.salt) {
        Ok(v) => v,
        Err(e) => return error_response(StatusCode::BAD_REQUEST, &e),
    };
    let nonce = match decode_blob_field("nonce", &req.nonce) {
        Ok(v) => v,
        Err(e) => return error_response(StatusCode::BAD_REQUEST, &e),
    };

    match state
        .passkey_service
        .create_vault(&req.account_id, &encrypted_data, &salt, &nonce)
        .await
    {
        Ok(()) => (
            StatusCode::CREATED,
            Json(serde_json::json!({ "success": true })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(
                account_id = %req.account_id,
                "vault create failed: {}",
                e
            );
            error_response(StatusCode::BAD_REQUEST, &e)
        }
    }
}

#[derive(Debug, serde::Deserialize)]
struct VaultGetQuery {
    account_id: String,
}

#[handler]
async fn vault_get(
    Query(query): Query<VaultGetQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.passkey_service.get_vault(&query.account_id).await {
        Ok(Some(vault)) => Json(serde_json::json!({
            "success": true,
            "data": vault
        }))
        .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Vault not found"),
        Err(e) => {
            tracing::error!(
                account_id = %query.account_id,
                "vault get failed: {}",
                e
            );
            error_response(StatusCode::INTERNAL_SERVER_ERROR, &e)
        }
    }
}

#[handler]
async fn vault_update(
    Json(req): Json<VaultBlobRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let encrypted_data = match decode_blob_field("encrypted_data", &req.encrypted_data) {
        Ok(v) => v,
        Err(e) => return error_response(StatusCode::BAD_REQUEST, &e),
    };
    let salt = match decode_blob_field("salt", &req.salt) {
        Ok(v) => v,
        Err(e) => return error_response(StatusCode::BAD_REQUEST, &e),
    };
    let nonce = match decode_blob_field("nonce", &req.nonce) {
        Ok(v) => v,
        Err(e) => return error_response(StatusCode::BAD_REQUEST, &e),
    };

    match state
        .passkey_service
        .update_vault(&req.account_id, &encrypted_data, &salt, &nonce)
        .await
    {
        Ok(()) => Json(serde_json::json!({ "success": true })).into_response(),
        Err(e) => {
            let status = if e.contains("not found") {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::BAD_REQUEST
            };
            tracing::error!(
                account_id = %req.account_id,
                "vault update failed: {}",
                e
            );
            error_response(status, &e)
        }
    }
}

// ============================================================================
// Recovery Code Handlers
// ============================================================================

#[derive(Debug, serde::Deserialize)]
struct RecoveryGenerateRequest {
    account_id: String,
}

#[handler]
async fn recovery_generate(
    Json(req): Json<RecoveryGenerateRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .passkey_service
        .generate_recovery_codes_for_account(&req.account_id)
        .await
    {
        Ok(result) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "success": true,
                "data": result
            })),
        )
            .into_response(),
        Err(e) => error_response(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

#[derive(Debug, serde::Deserialize)]
struct RecoveryVerifyRequest {
    account_id: String,
    code: String,
}

#[handler]
async fn recovery_verify(
    Json(req): Json<RecoveryVerifyRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .passkey_service
        .verify_recovery_code_for_account(&req.account_id, &req.code)
        .await
    {
        Ok(true) => Json(serde_json::json!({
            "success": true,
            "data": { "valid": true }
        }))
        .into_response(),
        Ok(false) => Json(serde_json::json!({
            "success": true,
            "data": { "valid": false }
        }))
        .into_response(),
        Err(e) => error_response(StatusCode::INTERNAL_SERVER_ERROR, &e),
    }
}

#[handler]
async fn recovery_status(
    Path(account_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .passkey_service
        .get_recovery_code_status(&account_id)
        .await
    {
        Ok(remaining) => Json(serde_json::json!({
            "success": true,
            "data": { "remaining_codes": remaining }
        }))
        .into_response(),
        Err(e) => error_response(StatusCode::INTERNAL_SERVER_ERROR, &e),
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
    tracing::info!(
        "Search request: query={:?}, category={:?}, limit={:?}, offset={:?}",
        request.query,
        request.category,
        request.limit,
        request.offset
    );

    match state.script_service.search_scripts(&request).await {
        Ok(result) => {
            let has_more = result.offset + (result.scripts.len() as i64) < result.total;

            tracing::info!(
                "Search returned {} scripts (offset={}, limit={}, total={})",
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
        Err((status, message)) => {
            tracing::error!("Search failed with status {}: {}", status, message);
            error_response(status, &message)
        }
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

// ============================================================================
// ICPay payment integration + paid-script entitlement gate
// ============================================================================

/// Canonical signature payload for `POST /api/v1/scripts/:id/download`. The
/// client signs this exact string (no JSON, no canonicalisation) with the
/// Ed25519 private key whose public half appears in `DownloadRequest.public_key`.
/// Kept here (next to the handler) so the wire format is obvious from a single
/// place; the Dart `script_download_service` must build the identical string.
fn build_download_payload(script_id: &str, timestamp: &str, nonce: &str) -> Vec<u8> {
    format!("download:{script_id}:{timestamp}:{nonce}").into_bytes()
}

/// Authenticated paid-bundle retrieval. `POST /api/v1/scripts/:id/download`.
///
/// The ONLY endpoint that returns the paid bundle. Verifies an Ed25519
/// signature over `download:{script_id}:{timestamp}:{nonce}` with the public
/// key in the body, resolves the owning account via the public-keys table,
/// then gates on a purchase record (or script ownership / free-tier). Free
/// scripts also flow through here so the client has one download path.
#[handler]
async fn download_script(
    Path(script_id): Path<String>,
    Json(req): Json<DownloadRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // 1. Resolve account_id from public_key FIRST. Unknown key → 401 (do not
    //    even attempt signature verify against an unbound key).
    let account_id = match state
        .script_service
        .account_repo
        .find_public_key_by_value(&req.public_key)
        .await
    {
        Ok(Some(key)) => key.account_id,
        Ok(None) => {
            tracing::warn!(
                "Download rejected: public key not bound to any account (script={})",
                script_id
            );
            return error_response(StatusCode::UNAUTHORIZED, "Unknown public key");
        }
        Err(e) => {
            tracing::error!(
                "Failed to lookup public key for download (script={}): {}",
                script_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to resolve account for download",
            );
        }
    };

    // 2. Verify Ed25519 signature over the canonical payload.
    let payload = build_download_payload(&script_id, &req.timestamp, &req.nonce);
    if let Err(e) = auth::verify_ed25519_signature(&req.signature, &payload, &req.public_key) {
        tracing::warn!(
            "Download rejected: signature verification failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(StatusCode::UNAUTHORIZED, "Invalid signature");
    }

    // 3. Load script.
    let script = match state.script_service.get_script(&script_id).await {
        Ok(Some(s)) => s,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to load script for download {}: {}", script_id, e);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to load script for download",
            );
        }
    };

    // 4. Entitlement: free → yes; paid → owner OR purchase record. The owner
    //    and free cases both short-circuit to "entitled" without hitting the
    //    purchases table (clippy recognises this as the same branch body).
    let entitled =
        if script.price <= 0.0 || script.owner_account_id.as_deref() == Some(account_id.as_str()) {
            true
        } else {
            match state
                .purchase_repo
                .exists_for_account_and_script(&account_id, &script_id)
                .await
            {
                Ok(purchased) => purchased,
                Err(e) => {
                    tracing::error!(
                        "Failed to check purchase for download (script={}, account={}): {}",
                        script_id,
                        account_id,
                        e
                    );
                    return error_response(
                        StatusCode::INTERNAL_SERVER_ERROR,
                        "Failed to verify purchase entitlement",
                    );
                }
            }
        };

    if !entitled {
        return (
            StatusCode::PAYMENT_REQUIRED,
            Json(serde_json::json!({
                "success": false,
                "error": "Purchase required",
                "data": { "price": script.price }
            })),
        )
            .into_response();
    }

    // 5. Bump downloads counter (mirrors `update_script_stats`). Best-effort:
    //    a counter failure does NOT block the download — the entitlement
    //    decision is the security-relevant part and already succeeded.
    if let Err(e) = state.script_service.increment_downloads(&script_id).await {
        tracing::warn!(
            "Download succeeded but failed to bump downloads counter for {}: {}",
            script_id,
            e
        );
    }

    Json(serde_json::json!({
        "success": true,
        "data": {
            "bundle": script.bundle,
            "purchased": true
        }
    }))
    .into_response()
}

/// Public ICPay client config. `GET /api/v1/payments/icpay/config`.
///
/// Returns the browser-safe publishable key + token shortcode + API URL. The
/// secret key never leaves the server. 503 (LOUD) when the publishable key is
/// unset so the client can distinguish "payments not configured" from a
/// transient error.
#[handler]
async fn payment_config(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.payment_service.get_publishable_config() {
        Some(cfg) => Json(serde_json::json!({
            "success": true,
            "data": cfg
        }))
        .into_response(),
        None => error_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "ICPAY_PUBLISHABLE_KEY not configured",
        ),
    }
}

/// ICPay webhook receiver. `POST /api/v1/payments/icpay/webhook`.
///
/// UNAUTHENTICATED — ICPay calls this. Verifies an HMAC-SHA256 over the RAW
/// request body (the exact bytes the sender produced) with the shared
/// `ICPAY_WEBHOOK_SECRET`, then idempotently records the purchase. Both
/// `X-Icpay-Signature` and `Icmpay-Signature` header spellings are accepted
/// (the exact header name is an assumption pending live ICPay docs — see the
/// note in `payment_service::verify_webhook`).
#[handler]
async fn icpay_webhook(
    req: &Request,
    body: Vec<u8>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // LOUD misconfig: refuse to verify when the secret is unset (500). This
    // surfaces a real configuration error rather than silently accepting or
    // rejecting every webhook.
    if !state.payment_service.has_webhook_secret() {
        tracing::error!("ICPay webhook received but ICPAY_WEBHOOK_SECRET is not configured");
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            "ICPAY_WEBHOOK_SECRET not configured",
        );
    }

    // Signature header — accept both documented spellings.
    let sig_header = req
        .header("x-icpay-signature")
        .or_else(|| req.header("icmpay-signature"));
    let sig_header = match sig_header {
        Some(h) => h,
        None => {
            tracing::warn!("ICPay webhook rejected: missing signature header");
            return error_response(StatusCode::UNAUTHORIZED, "Missing X-Icpay-Signature header");
        }
    };

    // RAW body bytes — the HMAC was computed over the exact bytes the sender
    // produced, so we use the `Vec<u8>` extractor (NOT `Json`, which would
    // re-serialise and invalidate the signature).
    let event = match state.payment_service.verify_webhook(&body, sig_header) {
        Ok(event) => event,
        Err(msg) => {
            // Distinguish bad signature (401) from malformed JSON (400).
            let status = if msg.contains("signature") {
                tracing::warn!("ICPay webhook rejected: bad signature");
                StatusCode::UNAUTHORIZED
            } else {
                tracing::warn!("ICPay webhook rejected: {}", msg);
                StatusCode::BAD_REQUEST
            };
            return error_response(status, &msg);
        }
    };

    tracing::info!(
        "ICPay webhook received: script_id={:?}, account_id={:?}, status={:?}",
        event.metadata.script_id,
        event.metadata.account_id,
        event.status
    );

    let recorded = match state
        .payment_service
        .record_purchase_from_webhook(&event)
        .await
    {
        Ok(recorded) => recorded,
        Err(e) => {
            tracing::error!(
                "ICPay webhook failed to record purchase (script={:?}, account={:?}): {}",
                event.metadata.script_id,
                event.metadata.account_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to record purchase",
            );
        }
    };

    Json(serde_json::json!({
        "success": true,
        "data": { "recorded": recorded }
    }))
    .into_response()
}

#[handler]
async fn reset_database(Data(state): Data<&Arc<AppState>>) -> Response {
    if !is_development() {
        return error_response(
            StatusCode::FORBIDDEN,
            "Database reset only available in development",
        );
    }

    if let Err(e) = sqlx::query("DELETE FROM scripts")
        .execute(&state.pool)
        .await
    {
        tracing::error!("Failed to reset scripts table: {}", e);
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to reset database",
        );
    }

    if let Err(e) = sqlx::query("DELETE FROM reviews")
        .execute(&state.pool)
        .await
    {
        tracing::error!("Failed to reset reviews table: {}", e);
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to reset database",
        );
    }

    Json(serde_json::json!({
        "success": true,
        "message": "Database reset successfully"
    }))
    .into_response()
}

/// Wait for a process shutdown signal (ctrl-c and, on Unix, SIGTERM) and then
/// cancel `shutdown`. Falls back to ctrl-c only if the SIGTERM handler cannot
/// be installed. Never returns before a signal arrives.
async fn shutdown_on_signal(shutdown: CancellationToken) {
    let ctrl_c = async {
        if tokio::signal::ctrl_c().await.is_err() {
            tracing::warn!("Failed to install ctrl-c handler");
        }
    };

    #[cfg(unix)]
    {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut sig) => {
                tokio::select! {
                    _ = ctrl_c => {}
                    _ = sig.recv() => {}
                }
            }
            Err(e) => {
                tracing::warn!(
                    "Failed to install SIGTERM handler ({}); falling back to ctrl-c only",
                    e
                );
                ctrl_c.await;
            }
        }
    }

    #[cfg(not(unix))]
    {
        ctrl_c.await;
    }

    tracing::info!("Shutdown signal received; initiating graceful shutdown");
    shutdown.cancel();
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
    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite:./data/marketplace-dev.db?mode=rwc".to_string());

    // Ensure data directory exists
    if let Some(db_path) = database_url.strip_prefix("sqlite:") {
        let path = db_path.split('?').next().unwrap_or(db_path);
        if let Some(parent) = std::path::Path::new(path).parent() {
            std::fs::create_dir_all(parent).expect("Failed to create database directory");
        }
    }

    tracing::info!("Connecting to database: {}", database_url);

    let pool = SqlitePool::connect(&database_url)
        .await
        .expect("Failed to connect to database");

    tracing::info!("Initializing database schema...");
    db::initialize_database(&pool).await;
    tracing::info!("Database schema initialized successfully");

    // Clone pool for background cleanup job before moving it to state
    let cleanup_pool = pool.clone();

    // WebAuthn configuration
    let rp_id = env::var("WEBAUTHN_RP_ID").unwrap_or_else(|_| "localhost".to_string());
    let rp_origin =
        env::var("WEBAUTHN_RP_ORIGIN").unwrap_or_else(|_| "http://localhost:58000".to_string());
    warn_if_broken_prod_passkey_rp(
        &env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
        &rp_id,
        &rp_origin,
    );

    let admin_token =
        env::var("ADMIN_TOKEN").unwrap_or_else(|_| "change-me-in-production".to_string());
    warn_if_insecure_prod_admin_token(
        &env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
        &admin_token,
    );

    // ICPay payment integration: warn (do NOT crash) when env vars are unset.
    // The marketplace still boots and browses; only the payment endpoints
    // themselves 5xx/503 when invoked without config (LOUD-misconfig policy).
    warn_if_icpay_unconfigured();

    let passkey_service = PasskeyService::new(pool.clone(), &rp_id, &rp_origin)
        .expect("Failed to create PasskeyService");

    let purchase_repo = PurchaseRepository::new(pool.clone());
    let payment_service = PaymentService::from_env(pool.clone());

    let state = Arc::new(AppState {
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        passkey_service,
        purchase_repo,
        payment_service,
        pool,
    });

    // ========================================================================
    // Route map — every public API route wired below, grouped by resource.
    // Keep this in sync with the `.at(...)` chain. (Admin routes wear AdminAuth.)
    // ------------------------------------------------------------------------
    // Health & misc
    //   GET    /api/v1/health                         -> health_check
    //   GET    /api/v1/ping                           -> ping
    //   GET    /api/v1/marketplace-stats              -> get_marketplace_stats
    //   POST   /api/v1/update-script-stats            -> update_script_stats
    //   POST   /api/dev/reset-database                -> reset_database (dev only)
    // Scripts
    //   GET    /api/v1/scripts                        -> get_scripts
    //   POST   /api/v1/scripts                        -> create_script
    //   GET    /api/v1/scripts/count                  -> get_scripts_count
    //   POST   /api/v1/scripts/search                 -> search_scripts
    //   GET    /api/v1/scripts/trending               -> get_trending_scripts
    //   GET    /api/v1/scripts/featured               -> get_featured_scripts
    //   GET    /api/v1/scripts/compatible             -> get_compatible_scripts
    //   GET    /api/v1/scripts/category/:category     -> get_scripts_by_category
    //   GET    /api/v1/scripts/:id                    -> get_script
    //   PUT    /api/v1/scripts/:id                    -> update_script
    //   DELETE /api/v1/scripts/:id                    -> delete_script
    //   POST   /api/v1/scripts/:id/publish            -> publish_script
    //   GET    /api/v1/scripts/:id/preview            -> get_script_preview
    //   GET    /api/v1/scripts/:id/reviews            -> get_reviews
    //   POST   /api/v1/scripts/:id/reviews            -> create_review
    //   POST   /api/v1/scripts/:id/download           -> download_script (signed; entitlement gate)
    // Accounts
    //   POST   /api/v1/accounts                       -> register_account
    //   GET    /api/v1/accounts/:username             -> get_account
    //   PATCH  /api/v1/accounts/:username             -> update_account
    //   GET    /api/v1/accounts/by-public-key/:pubkey -> get_account_by_public_key
    //   POST   /api/v1/accounts/:username/keys        -> add_account_key
    //   DELETE /api/v1/accounts/:username/keys/:key_id-> remove_account_key
    // Passkeys
    //   POST   /api/v1/passkey/register/start         -> passkey_register_start
    //   POST   /api/v1/passkey/register/finish        -> passkey_register_finish
    //   POST   /api/v1/passkey/authenticate/start     -> passkey_authenticate_start
    //   POST   /api/v1/passkey/authenticate/finish    -> passkey_authenticate_finish
    //   GET    /api/v1/passkey/list/:account_id       -> passkey_list
    //   DELETE /api/v1/passkey/:passkey_id            -> passkey_delete
    // Vault
    //   POST   /api/v1/vault                          -> vault_create
    //   GET    /api/v1/vault                          -> vault_get
    //   PUT    /api/v1/vault                          -> vault_update
    // Recovery codes
    //   POST   /api/v1/recovery/generate              -> recovery_generate
    //   POST   /api/v1/recovery/verify                -> recovery_verify
    //   GET    /api/v1/recovery/status/:account_id    -> recovery_status
    // Admin (AdminAuth middleware)
    //   POST   /api/v1/admin/accounts/:username/keys/:key_id/disable -> admin_disable_key
    //   POST   /api/v1/admin/accounts/:username/recovery-key         -> admin_add_recovery_key
    // Payments (ICPay)
    //   GET    /api/v1/payments/icpay/config          -> payment_config (public; 503 if unset)
    //   POST   /api/v1/payments/icpay/webhook         -> icpay_webhook (unauthenticated; HMAC-verified)
    // ========================================================================
    // Build app
    let app = Route::new()
        .at("/api/v1/health", get(handlers::health_check))
        .at("/api/v1/ping", get(handlers::ping))
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
        .at("/api/v1/scripts/:id/preview", get(get_script_preview))
        .at(
            "/api/v1/scripts/:id/reviews",
            get(handlers::get_reviews).post(handlers::create_review),
        )
        .at("/api/v1/scripts/:id/download", post(download_script))
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
        // Passkey Authentication endpoints
        .at(
            "/api/v1/passkey/register/start",
            post(passkey_register_start),
        )
        .at(
            "/api/v1/passkey/register/finish",
            post(passkey_register_finish),
        )
        .at(
            "/api/v1/passkey/authenticate/start",
            post(passkey_authenticate_start),
        )
        .at(
            "/api/v1/passkey/authenticate/finish",
            post(passkey_authenticate_finish),
        )
        .at("/api/v1/passkey/list/:account_id", get(passkey_list))
        .at("/api/v1/passkey/:passkey_id", delete(passkey_delete))
        // Vault endpoints
        .at(
            "/api/v1/vault",
            post(vault_create).get(vault_get).put(vault_update),
        )
        // Recovery code endpoints
        .at("/api/v1/recovery/generate", post(recovery_generate))
        .at("/api/v1/recovery/verify", post(recovery_verify))
        .at("/api/v1/recovery/status/:account_id", get(recovery_status))
        // Admin Account endpoints (require admin authentication)
        .at(
            "/api/v1/admin/accounts/:username/keys/:key_id/disable",
            post(admin_disable_key).with(middleware::AdminAuth),
        )
        .at(
            "/api/v1/admin/accounts/:username/recovery-key",
            post(admin_add_recovery_key).with(middleware::AdminAuth),
        )
        // ICPay payment endpoints (webhook is unauthenticated; HMAC-verified)
        .at("/api/v1/payments/icpay/config", get(payment_config))
        .at("/api/v1/payments/icpay/webhook", post(icpay_webhook))
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

    // Graceful shutdown: one token drives both the background cleanup job and
    // the HTTP server, triggered by ctrl-c or SIGTERM.
    let shutdown = CancellationToken::new();
    tokio::spawn(shutdown_on_signal(shutdown.clone()));

    // Start background cleanup job for signature audit
    cleanup::start_audit_cleanup_job(cleanup_pool, shutdown.clone());

    // Close the std listener since we just needed it for the address
    drop(std_listener);

    // Now bind with Poem's listener
    let listener = TcpListener::bind(final_bind_addr);

    // Run until a shutdown signal arrives; when it does, drain in-flight
    // connections (hard limit 30s) then return. With no signal this runs
    // forever, identical to the previous behavior.
    Server::new(listener)
        .run_with_graceful_shutdown(app, shutdown.cancelled(), Some(Duration::from_secs(30)))
        .await
}

// ============================================================================
// ICPay payment integration — handler-level integration tests
// ============================================================================
//
// These tests exercise the REAL `#[handler]` functions end-to-end via poem's
// `TestClient`, including HTTP status codes and JSON bodies. They cover the
// HIGH-severity fix (paid bundle MUST NOT leak via the public `get_script`)
// and the authenticated download / webhook / config endpoints. Cryptography
// is real (a generated Ed25519 keypair signs the download payload); no
// mocking of crypto, per AGENTS.md.

#[cfg(test)]
mod payment_http_tests {
    use super::*;
    use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
    use ed25519_dalek::{Signer, SigningKey};
    use hmac::{Hmac, Mac};
    use poem::test::TestClient;
    use sha2::Sha256;

    type HmacSha256 = Hmac<Sha256>;

    /// A real Ed25519 keypair + the public key row inserted into the DB so the
    /// download handler can resolve `account_id` from the public key.
    struct TestIdentity {
        signing_key: SigningKey,
        public_key_b64: String,
        account_id: String,
    }

    impl TestIdentity {
        fn new(seed: [u8; 32], account_id: &str) -> Self {
            let signing_key = SigningKey::from_bytes(&seed);
            let public_key_b64 = B64.encode(signing_key.verifying_key().as_bytes());
            Self {
                signing_key,
                public_key_b64,
                account_id: account_id.to_string(),
            }
        }

        /// Signs the canonical `download:{script_id}:{timestamp}:{nonce}` payload
        /// and returns the base64 signature.
        fn sign_download(&self, script_id: &str, timestamp: &str, nonce: &str) -> String {
            let payload = build_download_payload(script_id, timestamp, nonce);
            let sig = self.signing_key.sign(&payload);
            B64.encode(sig.to_bytes())
        }
    }

    async fn insert_identity(pool: &SqlitePool, identity: &TestIdentity) {
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query(
            r#"INSERT INTO accounts (id, username, display_name, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)"#,
        )
        .bind(&identity.account_id)
        .bind(identity.account_id.to_lowercase())
        .bind(format!("Display {}", identity.account_id))
        .bind(&now)
        .bind(&now)
        .execute(pool)
        .await
        .unwrap();

        sqlx::query(
            r#"INSERT INTO account_public_keys
               (id, account_id, public_key, ic_principal, is_active, added_at)
               VALUES (?, ?, ?, ?, 1, ?)"#,
        )
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(&identity.account_id)
        .bind(&identity.public_key_b64)
        .bind("principal-placeholder")
        .bind(&now)
        .execute(pool)
        .await
        .unwrap();
    }

    /// Inserts a script with an explicit price; returns its id.
    async fn insert_script(pool: &SqlitePool, id: &str, price: f64, bundle: &str) {
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query(
            r#"INSERT INTO scripts (
                id, slug, owner_account_id, title, description, category, tags,
                bundle, author_principal, author_public_key, upload_signature,
                canister_ids, icon_url, screenshots, version, compatibility,
                price, is_public, downloads, rating, review_count,
                created_at, updated_at, deleted_at
            ) VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 1, 0, 0.0, 0, ?, ?, NULL)"#,
        )
        .bind(id)
        .bind(format!("slug-{id}"))
        .bind(format!("Title {id}"))
        .bind("description")
        .bind("utility")
        .bind(bundle)
        .bind("1.0.0")
        .bind(price)
        .bind(&now)
        .bind(&now)
        .execute(pool)
        .await
        .unwrap();
    }

    /// Builds a test `AppState` over an in-memory SQLite DB. Optionally seeds
    /// a known ICPay config so webhook/config tests can drive the happy path.
    async fn build_state(
        publishable_key: Option<&str>,
        webhook_secret: Option<&str>,
    ) -> Arc<AppState> {
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        db::initialize_database(&pool).await;

        let passkey_service =
            PasskeyService::new(pool.clone(), "localhost", "http://localhost:58000")
                .expect("Failed to create PasskeyService");

        Arc::new(AppState {
            account_service: AccountService::new(pool.clone()),
            script_service: ScriptService::new(pool.clone()),
            review_service: ReviewService::new(pool.clone()),
            passkey_service,
            purchase_repo: PurchaseRepository::new(pool.clone()),
            payment_service: PaymentService::with_config(
                publishable_key.map(str::to_string),
                None,
                webhook_secret.map(str::to_string),
                pool.clone(),
            ),
            pool,
        })
    }

    /// Builds a `Route` wired with just the payment-related endpoints, sharing
    /// `state` via `.data(...)`.
    fn build_app(state: Arc<AppState>) -> impl poem::Endpoint {
        Route::new()
            .at("/api/v1/scripts/:id", get(get_script))
            .at("/api/v1/scripts/:id/download", post(download_script))
            .at("/api/v1/payments/icpay/config", get(payment_config))
            .at("/api/v1/payments/icpay/webhook", post(icpay_webhook))
            .with(Cors::new())
            .data(state)
    }

    fn hex_encode(bytes: &[u8]) -> String {
        const HEX: &[u8; 16] = b"0123456789abcdef";
        let mut out = String::with_capacity(bytes.len() * 2);
        for &b in bytes {
            out.push(HEX[(b >> 4) as usize] as char);
            out.push(HEX[(b & 0x0f) as usize] as char);
        }
        out
    }

    fn sign_webhook(secret: &str, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(body);
        hex_encode(&mac.finalize().into_bytes())
    }

    /// Extracts the response body as a `serde_json::Value` for assertion.
    /// (`TestJson`'s inner field is private; `deserialize` is the public seam.)
    async fn json_value(resp: poem::test::TestResponse) -> serde_json::Value {
        resp.json().await.value().deserialize::<serde_json::Value>()
    }

    // ========================================================================
    // get_script entitlement gate
    // ========================================================================

    #[tokio::test]
    async fn get_script_free_returns_bundle_and_purchased_true() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "free-1", 0.0, "print('free source')").await;
        let app = build_app(state);
        let client = TestClient::new(app);

        let resp = client.get("/api/v1/scripts/free-1").send().await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["success"], true);
        assert_eq!(json["data"]["bundle"], "print('free source')");
        assert_eq!(json["data"]["purchased"], true);
        assert_eq!(json["data"]["price"], 0.0);
    }

    #[tokio::test]
    async fn get_script_paid_no_account_hides_bundle() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "paid-1", 9.99, "print('paid source')").await;
        let client = TestClient::new(build_app(state));

        let resp = client.get("/api/v1/scripts/paid-1").send().await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["success"], true);
        assert!(
            json["data"]["bundle"].is_null(),
            "paid bundle MUST be null when no account_id is provided"
        );
        assert_eq!(json["data"]["purchased"], false);
        assert_eq!(json["data"]["price"], 9.99);
        assert!(
            !json["data"]["description"].is_null(),
            "metadata (description, price) must still be present for the Buy CTA"
        );
    }

    #[tokio::test]
    async fn get_script_paid_account_without_purchase_hides_bundle() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "paid-1", 9.99, "print('paid source')").await;
        let client = TestClient::new(build_app(state.clone()));

        let resp = client
            .get("/api/v1/scripts/paid-1?account_id=someone-else")
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert!(
            json["data"]["bundle"].is_null(),
            "paid bundle MUST be null without a purchase record"
        );
        assert_eq!(json["data"]["purchased"], false);
    }

    #[tokio::test]
    async fn get_script_paid_account_with_purchase_returns_bundle() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "paid-1", 9.99, "print('paid source')").await;
        // Seed a purchase record.
        let now = chrono::Utc::now().to_rfc3339();
        state
            .purchase_repo
            .create_or_ignore(&models::NewPurchase {
                id: uuid::Uuid::new_v4().to_string(),
                account_id: "buyer-1".to_string(),
                script_id: "paid-1".to_string(),
                icpay_intent_id: Some("intent-1".to_string()),
                icpay_transaction_id: Some("tx-1".to_string()),
                usd_amount: 9.99,
                currency: "USD".to_string(),
                status: "completed".to_string(),
                paid_at: now.clone(),
                created_at: now,
            })
            .await
            .unwrap();

        let client = TestClient::new(build_app(state));
        let resp = client
            .get("/api/v1/scripts/paid-1?account_id=buyer-1")
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(
            json["data"]["bundle"], "print('paid source')",
            "paid bundle MUST be present once a purchase record exists"
        );
        assert_eq!(json["data"]["purchased"], true);
    }

    #[tokio::test]
    async fn get_script_paid_owner_is_entitled_without_purchase() {
        let state = build_state(None, None).await;
        // Seed an account + a script it owns.
        let identity = TestIdentity::new([42u8; 32], "owner-acct");
        insert_identity(&state.pool, &identity).await;
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query(
            r#"INSERT INTO scripts (
                id, slug, owner_account_id, title, description, category, tags,
                bundle, author_principal, author_public_key, upload_signature,
                canister_ids, icon_url, screenshots, version, compatibility,
                price, is_public, downloads, rating, review_count,
                created_at, updated_at, deleted_at
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 1, 0, 0.0, 0, ?, ?, NULL)"#,
        )
        .bind("paid-owned")
        .bind("slug-paid-owned")
        .bind("owner-acct") // owner_account_id
        .bind("Title")
        .bind("desc")
        .bind("utility")
        .bind("owner source")
        .bind("1.0.0")
        .bind(19.99)
        .bind(&now)
        .bind(&now)
        .execute(&state.pool)
        .await
        .unwrap();

        let client = TestClient::new(build_app(state));
        let resp = client
            .get("/api/v1/scripts/paid-owned?account_id=owner-acct")
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(
            json["data"]["bundle"], "owner source",
            "script owner is always entitled, even without a purchase row"
        );
        assert_eq!(json["data"]["purchased"], true);
    }

    #[tokio::test]
    async fn get_script_unknown_id_returns_404() {
        let state = build_state(None, None).await;
        let client = TestClient::new(build_app(state));
        let resp = client.get("/api/v1/scripts/does-not-exist").send().await;
        resp.assert_status(StatusCode::NOT_FOUND);
    }

    // ========================================================================
    // POST /scripts/:id/download
    // ========================================================================

    #[tokio::test]
    async fn download_free_script_returns_bundle() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "free-1", 0.0, "free source").await;
        let identity = TestIdentity::new([1u8; 32], "acct-1");
        insert_identity(&state.pool, &identity).await;

        let timestamp = chrono::Utc::now().to_rfc3339();
        let nonce = uuid::Uuid::new_v4().to_string();
        let sig = identity.sign_download("free-1", &timestamp, &nonce);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/scripts/free-1/download")
            .body_json(&serde_json::json!({
                "public_key": identity.public_key_b64,
                "signature": sig,
                "timestamp": timestamp,
                "nonce": nonce,
            }))
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["success"], true);
        assert_eq!(json["data"]["bundle"], "free source");
        assert_eq!(json["data"]["purchased"], true);
    }

    #[tokio::test]
    async fn download_paid_with_purchase_returns_bundle() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
        let identity = TestIdentity::new([2u8; 32], "buyer-1");
        insert_identity(&state.pool, &identity).await;
        // Seed the entitlement.
        let now = chrono::Utc::now().to_rfc3339();
        state
            .purchase_repo
            .create_or_ignore(&models::NewPurchase {
                id: uuid::Uuid::new_v4().to_string(),
                account_id: "buyer-1".to_string(),
                script_id: "paid-1".to_string(),
                icpay_intent_id: None,
                icpay_transaction_id: None,
                usd_amount: 9.99,
                currency: "USD".to_string(),
                status: "completed".to_string(),
                paid_at: now.clone(),
                created_at: now,
            })
            .await
            .unwrap();

        let timestamp = chrono::Utc::now().to_rfc3339();
        let nonce = uuid::Uuid::new_v4().to_string();
        let sig = identity.sign_download("paid-1", &timestamp, &nonce);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/scripts/paid-1/download")
            .body_json(&serde_json::json!({
                "public_key": identity.public_key_b64,
                "signature": sig,
                "timestamp": timestamp,
                "nonce": nonce,
            }))
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["data"]["bundle"], "paid source");
        assert_eq!(json["data"]["purchased"], true);
    }

    #[tokio::test]
    async fn download_paid_without_purchase_returns_402() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
        let identity = TestIdentity::new([3u8; 32], "freeloader");
        insert_identity(&state.pool, &identity).await;

        let timestamp = chrono::Utc::now().to_rfc3339();
        let nonce = uuid::Uuid::new_v4().to_string();
        let sig = identity.sign_download("paid-1", &timestamp, &nonce);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/scripts/paid-1/download")
            .body_json(&serde_json::json!({
                "public_key": identity.public_key_b64,
                "signature": sig,
                "timestamp": timestamp,
                "nonce": nonce,
            }))
            .send()
            .await;
        resp.assert_status(StatusCode::PAYMENT_REQUIRED);
        let json = json_value(resp).await;
        assert_eq!(json["success"], false);
        assert_eq!(json["error"], "Purchase required");
        assert_eq!(json["data"]["price"], 9.99);
    }

    #[tokio::test]
    async fn download_with_bad_signature_returns_401() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "free-1", 0.0, "free").await;
        let identity = TestIdentity::new([4u8; 32], "acct-4");
        insert_identity(&state.pool, &identity).await;

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/scripts/free-1/download")
            .body_json(&serde_json::json!({
                "public_key": identity.public_key_b64,
                "signature": "0000000000000000000000000000000000000000000000000000000000000000",
                "timestamp": chrono::Utc::now().to_rfc3339(),
                "nonce": uuid::Uuid::new_v4().to_string(),
            }))
            .send()
            .await;
        resp.assert_status(StatusCode::UNAUTHORIZED);
        let json = json_value(resp).await;
        assert_eq!(json["error"], "Invalid signature");
    }

    #[tokio::test]
    async fn download_with_unknown_public_key_returns_401() {
        let state = build_state(None, None).await;
        insert_script(&state.pool, "free-1", 0.0, "free").await;
        // No account_public_keys row for this key.
        let identity = TestIdentity::new([5u8; 32], "ghost");

        let timestamp = chrono::Utc::now().to_rfc3339();
        let nonce = uuid::Uuid::new_v4().to_string();
        let sig = identity.sign_download("free-1", &timestamp, &nonce);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/scripts/free-1/download")
            .body_json(&serde_json::json!({
                "public_key": identity.public_key_b64,
                "signature": sig,
                "timestamp": timestamp,
                "nonce": nonce,
            }))
            .send()
            .await;
        resp.assert_status(StatusCode::UNAUTHORIZED);
        let json = json_value(resp).await;
        assert_eq!(json["error"], "Unknown public key");
    }

    #[tokio::test]
    async fn download_unknown_script_returns_404() {
        let state = build_state(None, None).await;
        let identity = TestIdentity::new([6u8; 32], "acct-6");
        insert_identity(&state.pool, &identity).await;

        let timestamp = chrono::Utc::now().to_rfc3339();
        let nonce = uuid::Uuid::new_v4().to_string();
        let sig = identity.sign_download("ghost-script", &timestamp, &nonce);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/scripts/ghost-script/download")
            .body_json(&serde_json::json!({
                "public_key": identity.public_key_b64,
                "signature": sig,
                "timestamp": timestamp,
                "nonce": nonce,
            }))
            .send()
            .await;
        resp.assert_status(StatusCode::NOT_FOUND);
    }

    // ========================================================================
    // GET /payments/icpay/config
    // ========================================================================

    #[tokio::test]
    async fn config_with_publishable_key_returns_200() {
        let state = build_state(Some("pk_test_abc"), Some("whsec_xyz")).await;
        let client = TestClient::new(build_app(state));
        let resp = client.get("/api/v1/payments/icpay/config").send().await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["success"], true);
        assert_eq!(json["data"]["publishableKey"], "pk_test_abc");
        assert_eq!(json["data"]["shortcode"], "ic_icp");
        assert_eq!(json["data"]["apiUrl"], "https://api.icpay.org");
    }

    #[tokio::test]
    async fn config_without_publishable_key_returns_503() {
        let state = build_state(None, Some("whsec_xyz")).await;
        let client = TestClient::new(build_app(state));
        let resp = client.get("/api/v1/payments/icpay/config").send().await;
        resp.assert_status(StatusCode::SERVICE_UNAVAILABLE);
        let json = json_value(resp).await;
        assert_eq!(json["success"], false);
        assert_eq!(json["error"], "ICPAY_PUBLISHABLE_KEY not configured");
    }

    // ========================================================================
    // POST /payments/icpay/webhook
    // ========================================================================

    fn completed_webhook_body(account: &str, script: &str) -> Vec<u8> {
        serde_json::json!({
            "id": "icpay-tx-1",
            "status": "completed",
            "usdAmount": 9.99,
            "metadata": {
                "accountId": account,
                "scriptId": script,
                "intentId": "intent-1"
            }
        })
        .to_string()
        .into_bytes()
    }

    #[tokio::test]
    async fn webhook_with_valid_hmac_records_purchase_and_returns_200() {
        let state = build_state(Some("pk"), Some("whsec_demo")).await;
        insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
        let body = completed_webhook_body("buyer-1", "paid-1");
        let sig = sign_webhook("whsec_demo", &body);

        let client = TestClient::new(build_app(state.clone()));
        let resp = client
            .post("/api/v1/payments/icpay/webhook")
            .header("X-Icpay-Signature", &sig)
            .body(body)
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["success"], true);
        assert_eq!(json["data"]["recorded"], true);

        // Entitlement now exists.
        assert!(
            state
                .purchase_repo
                .exists_for_account_and_script("buyer-1", "paid-1")
                .await
                .unwrap(),
            "purchase must be persisted after a valid webhook"
        );
    }

    #[tokio::test]
    async fn webhook_redelivery_is_idempotent() {
        let state = build_state(Some("pk"), Some("whsec_demo")).await;
        insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
        let body = completed_webhook_body("buyer-1", "paid-1");
        let sig = sign_webhook("whsec_demo", &body);

        let client = TestClient::new(build_app(state.clone()));
        let resp1 = client
            .post("/api/v1/payments/icpay/webhook")
            .header("X-Icpay-Signature", &sig)
            .body(body.clone())
            .send()
            .await;
        let json1 = json_value(resp1).await;
        assert_eq!(json1["data"]["recorded"], true, "first delivery inserts");

        let resp2 = client
            .post("/api/v1/payments/icpay/webhook")
            .header("X-Icpay-Signature", &sig)
            .body(body)
            .send()
            .await;
        resp2.assert_status(StatusCode::OK);
        let json2 = json_value(resp2).await;
        assert_eq!(
            json2["data"]["recorded"], false,
            "redelivery must be a no-op (recorded=false, no duplicate row)"
        );
    }

    #[tokio::test]
    async fn webhook_with_bad_hmac_returns_401() {
        let state = build_state(Some("pk"), Some("whsec_demo")).await;
        let body = completed_webhook_body("buyer-1", "paid-1");

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/payments/icpay/webhook")
            .header("X-Icpay-Signature", "deadbeef".repeat(8))
            .body(body)
            .send()
            .await;
        resp.assert_status(StatusCode::UNAUTHORIZED);
        let json = json_value(resp).await;
        assert!(
            json["error"].as_str().unwrap().contains("signature"),
            "got: {json}"
        );
    }

    #[tokio::test]
    async fn webhook_without_secret_returns_500() {
        // No webhook secret configured.
        let state = build_state(Some("pk"), None).await;
        let body = completed_webhook_body("buyer-1", "paid-1");
        let sig = sign_webhook("whsec_demo", &body);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/payments/icpay/webhook")
            .header("X-Icpay-Signature", &sig)
            .body(body)
            .send()
            .await;
        resp.assert_status(StatusCode::INTERNAL_SERVER_ERROR);
        let json = json_value(resp).await;
        assert_eq!(json["error"], "ICPAY_WEBHOOK_SECRET not configured");
    }

    #[tokio::test]
    async fn webhook_missing_signature_header_returns_401() {
        let state = build_state(Some("pk"), Some("whsec_demo")).await;
        let body = completed_webhook_body("buyer-1", "paid-1");

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/payments/icpay/webhook")
            .body(body)
            .send()
            .await;
        resp.assert_status(StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn webhook_accepts_icmpay_signature_header_spelling() {
        // Resilience: accept both X-Icpay-Signature and Icmpay-Signature.
        let state = build_state(Some("pk"), Some("whsec_demo")).await;
        insert_script(&state.pool, "paid-1", 9.99, "paid source").await;
        let body = completed_webhook_body("buyer-2", "paid-1");
        let sig = sign_webhook("whsec_demo", &body);

        let client = TestClient::new(build_app(state));
        let resp = client
            .post("/api/v1/payments/icpay/webhook")
            .header("Icmpay-Signature", &sig)
            .body(body)
            .send()
            .await;
        resp.assert_status(StatusCode::OK);
        let json = json_value(resp).await;
        assert_eq!(json["data"]["recorded"], true);
    }
}
