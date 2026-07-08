use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Query},
    IntoResponse, Response,
};

use crate::{models::AppState, responses::error_response};

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
pub async fn vault_create(
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
            // Variant decides status (Conflict for duplicate, Internal for DB
            // errors). TD-2: DB errors were 400 under the old fixed-status
            // handler; now correctly 500.
            error_response(e.status(), e.message())
        }
    }
}

#[derive(Debug, serde::Deserialize)]
struct VaultGetQuery {
    account_id: String,
}

#[handler]
pub async fn vault_get(
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
            error_response(e.status(), e.message())
        }
    }
}

#[handler]
pub async fn vault_update(
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
            tracing::error!(
                account_id = %req.account_id,
                "vault update failed: {}",
                e
            );
            // Variant decides status (NotFound for missing vault, Internal for
            // DB errors). TD-2: DB errors were 400 under the old
            // `.contains("not found") → else → 400` heuristic; now correctly
            // 500.
            error_response(e.status(), e.message())
        }
    }
}
