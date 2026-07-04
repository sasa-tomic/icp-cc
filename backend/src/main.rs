use icp_marketplace_api::{
    cleanup, db, middleware,
    models::{self, *},
    responses::error_response,
    services::{
        AccountService, PasskeyAuthenticationFinish, PasskeyRegistrationFinish, PasskeyService,
        ReviewService, ScriptService,
    },
};
use poem::{
    delete, get, handler,
    http::StatusCode,
    listener::TcpListener,
    middleware::Cors,
    post,
    web::{Data, Json, Path, Query},
    EndpointExt, IntoResponse, Response, Route, Server,
};
use sqlx::sqlite::SqlitePool;
use std::{env, io::ErrorKind, net::TcpListener as StdTcpListener, sync::Arc, time::Duration};
use tokio_util::sync::CancellationToken;

fn is_development() -> bool {
    env::var("ENVIRONMENT").unwrap_or_default() == "development"
}

fn is_localhost_webauthn_rp(rp_id: &str, rp_origin: &str) -> bool {
    let rp_is_local = matches!(rp_id, "localhost" | "127.0.0.1");
    let origin_is_local_http = rp_origin.starts_with("http://")
        && (rp_origin.contains("localhost") || rp_origin.contains("127.0.0.1"));
    rp_is_local || origin_is_local_http
}

fn warn_if_broken_prod_passkey_rp(environment: &str, rp_id: &str, rp_origin: &str) -> bool {
    if environment == "development" || !is_localhost_webauthn_rp(rp_id, rp_origin) {
        return false;
    }
    let rule = "=".repeat(72);
    let msg = format!(
        "\n{rule}\n\
         [!!] PRODUCTION PASSKEY MISCONFIGURATION — PASSKEYS WILL BE BROKEN [!!]\n\
         {rule}\n\
         WEBAUTHN_RP_ID resolves to a localhost address in a non-development\n\
         environment. Passkeys will be registered/authenticated against\n\
         localhost and silently fail for the public hostname.\n\
         \n\
         Fix: set WEBAUTHN_RP_ID to the public host (e.g. icp-mp.kalaj.org)\n\
         and WEBAUTHN_RP_ORIGIN to its https origin\n\
         (e.g. https://icp-mp.kalaj.org).\n\
         \n\
         ENVIRONMENT       = {environment}\n\
         WEBAUTHN_RP_ID    = {rp_id}\n\
         WEBAUTHN_RP_ORIGIN = {rp_origin}\n\
         {rule}"
    );
    eprintln!("{msg}");
    tracing::error!("{msg}");
    true
}

#[cfg(test)]
mod webauthn_rp_tests {
    use super::*;

    #[test]
    fn localhost_rp_id_is_detected() {
        assert!(is_localhost_webauthn_rp(
            "localhost",
            "https://icp-mp.kalaj.org"
        ));
        assert!(is_localhost_webauthn_rp(
            "127.0.0.1",
            "https://icp-mp.kalaj.org"
        ));
    }

    #[test]
    fn http_localhost_origin_is_detected() {
        assert!(is_localhost_webauthn_rp(
            "icp-mp.kalaj.org",
            "http://localhost:58000"
        ));
        assert!(is_localhost_webauthn_rp(
            "icp-mp.kalaj.org",
            "http://127.0.0.1:58000"
        ));
    }

    #[test]
    fn public_host_is_not_detected() {
        assert!(!is_localhost_webauthn_rp(
            "icp-mp.kalaj.org",
            "https://icp-mp.kalaj.org"
        ));
    }

    #[test]
    fn warning_fires_for_production_localhost_only() {
        assert!(warn_if_broken_prod_passkey_rp(
            "production",
            "localhost",
            "http://localhost:58000"
        ));
        assert!(!warn_if_broken_prod_passkey_rp(
            "development",
            "localhost",
            "http://localhost:58000"
        ));
        assert!(!warn_if_broken_prod_passkey_rp(
            "production",
            "icp-mp.kalaj.org",
            "https://icp-mp.kalaj.org"
        ));
    }
}

fn is_insecure_admin_token(admin_token: &str) -> bool {
    admin_token.is_empty() || admin_token == "change-me-in-production"
}

fn warn_if_insecure_prod_admin_token(environment: &str, admin_token: &str) -> bool {
    if environment == "development" || !is_insecure_admin_token(admin_token) {
        return false;
    }
    let rule = "=".repeat(72);
    let msg = format!(
        "\n{rule}\n\
         [!!] PRODUCTION ADMIN TOKEN MISCONFIGURATION — ADMIN ROUTES ARE EXPOSED [!!]\n\
         {rule}\n\
         ADMIN_TOKEN is unset or still the public default value\n\
         (\"change-me-in-production\") in a non-development environment. The\n\
         admin routes (/api/v1/admin/*) are guarded by a publicly-known token\n\
         and are effectively unprotected.\n\
         \n\
         Fix: set ADMIN_TOKEN to a strong, secret, operator-chosen value\n\
         before deploying.\n\
         \n\
         ENVIRONMENT = {environment}\n\
         ADMIN_TOKEN = {admin_token}\n\
         {rule}"
    );
    eprintln!("{msg}");
    tracing::error!("{msg}");
    true
}

#[cfg(test)]
mod admin_token_tests {
    use super::*;

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

    let passkey_service = PasskeyService::new(pool.clone(), &rp_id, &rp_origin)
        .expect("Failed to create PasskeyService");

    let state = Arc::new(AppState {
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        passkey_service,
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
    //   GET    /api/v1/scripts/:id/reviews            -> get_reviews
    //   POST   /api/v1/scripts/:id/reviews            -> create_review
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
    // ========================================================================
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
