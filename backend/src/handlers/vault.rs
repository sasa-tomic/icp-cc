use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json},
    IntoResponse, Response,
};

use crate::{
    models::AppState,
    responses::error_response,
    signature_gate::{verify_signed_account_request, SignedAuthFields},
};

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
// ## W7-12 — signature-gated (closes W7-003 IDOR)
//
// Every vault route is now signature-gated. The caller proves ownership of an
// account keypair (Ed25519 over `{action, account_id, nonce, ts}`); the server
// resolves `account_id` SERVER-SIDE from the verified public key and operates
// on THAT account — never the request body's value. This closes the
// overwrite-anyone's-vault / read-anyone's-ciphertext exploit (account_id was a
// public identifier trusted verbatim).
//
// ### Field-name note
//
// The request struct carries TWO nonces:
//   - `nonce`  — the replay-prevention UUID (single-use, signed). Part of the
//                auth fields shared by every gated route.
//   - `blob_nonce` — the AES-GCM 12-byte nonce embedded inside the opaque blob.
//                Renamed on the WIRE (was `nonce`) to avoid clashing with the
//                replay nonce. The DB column stays `nonce` (unchanged).
//
// ### Shapes
//
// POST /api/v1/vault          (create)  → 201
// PUT  /api/v1/vault          (update)  → 200
// POST /api/v1/vault/get      (read)    → 200 / 404
//   Request body:
//     {
//       "signature":         String,   // Ed25519 over the canonical payload
//       "author_public_key": String,   // base64 — resolves account_id server-side
//       "author_principal":  String,   // IC principal
//       "timestamp":         i64,      // unix seconds (±5 min window)
//       "nonce":             String,   // replay-prevention UUID (single-use)
//       "encrypted_data":    String,   // base64 of the AES-256-GCM ciphertext
//       "salt":              String,   // base64 of the Argon2id salt (16 bytes)
//       "blob_nonce":        String    // base64 of the AES-GCM nonce (12 bytes)
//     }
//   Success: { "success": true }  (+ "data" blob for get)

/// Single source of truth for the signed vault action names. The frontend
/// `PasskeyService` mirrors these EXACT strings inside the canonical payload.
const VAULT_CREATE_ACTION: &str = "vault:create";
const VAULT_UPDATE_ACTION: &str = "vault:update";
const VAULT_GET_ACTION: &str = "vault:get";

/// Base64-encoded opaque vault blob + the auth fields. See the wire-contract
/// doc above. Used for POST (create) and PUT (update).
#[derive(Debug, serde::Deserialize)]
struct VaultBlobRequest {
    // --- auth fields (resolve account_id server-side) ---
    signature: String,
    author_public_key: String,
    author_principal: String,
    timestamp: i64,
    nonce: String,
    // --- opaque blob (zero-knowledge; server stores verbatim) ---
    encrypted_data: String, // base64
    salt: String,           // base64
    blob_nonce: String,     // base64 (AES-GCM nonce — renamed from `nonce`)
}

/// Decodes a base64 field from a [`VaultBlobRequest`]. Returns the decoded
/// bytes or a human-readable error string that the caller surfaces as a 400.
fn decode_blob_field(field: &'static str, encoded: &str) -> Result<Vec<u8>, String> {
    base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        .map_err(|e| format!("Invalid base64 for '{}': {}", field, e))
}

/// Decoded opaque-blob fields (base64 → bytes).
struct DecodedBlob {
    encrypted_data: Vec<u8>,
    salt: Vec<u8>,
    nonce: Vec<u8>,
}

/// Extracts + validates the base64 blob fields, or returns a `(status,
/// message)` pair the caller renders.
fn decode_blob_fields(req: &VaultBlobRequest) -> Result<DecodedBlob, (StatusCode, String)> {
    let encrypted_data =
        decode_blob_field("encrypted_data", &req.encrypted_data).map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    let salt = decode_blob_field("salt", &req.salt).map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    let nonce =
        decode_blob_field("blob_nonce", &req.blob_nonce).map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    Ok(DecodedBlob {
        encrypted_data,
        salt,
        nonce,
    })
}

/// Runs the signature gate for a vault route and returns the resolved
/// account_id or the rejection response. The payload binds the resolved
/// account_id so a non-owner signature cannot target another account's vault.
fn vault_auth_fields<'a>(req: &'a VaultBlobRequest) -> SignedAuthFields<'a> {
    SignedAuthFields {
        signature: &req.signature,
        author_public_key: &req.author_public_key,
        author_principal: &req.author_principal,
        timestamp: req.timestamp,
        nonce: &req.nonce,
    }
}

#[handler]
pub async fn vault_create(
    Json(req): Json<VaultBlobRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let blob = match decode_blob_fields(&req) {
        Ok(v) => v,
        Err((status, msg)) => return error_response(status, &msg),
    };

    let account_repo = &state.script_service.account_repo;
    let account_id =
        match verify_signed_account_request(account_repo, &state.pool, VAULT_CREATE_ACTION, &vault_auth_fields(&req), |resolved| {
            serde_json::json!({
                "action": VAULT_CREATE_ACTION,
                "account_id": resolved,
                "nonce": req.nonce,
                "ts": req.timestamp,
            })
        })
        .await
        {
            Ok(id) => id,
            Err(r) => return error_response(r.status, r.message),
        };

    match state
        .passkey_service
        .create_vault(&account_id, &blob.encrypted_data, &blob.salt, &blob.nonce)
        .await
    {
        Ok(()) => (
            StatusCode::CREATED,
            Json(serde_json::json!({ "success": true })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(
                account_id = %account_id,
                "vault create failed: {}",
                e
            );
            error_response(e.status(), e.message())
        }
    }
}

/// `POST /api/v1/vault/get` — signature-gated read (W7-12).
///
/// Converted from `GET /vault?account_id=` (which trusted the query param) to a
/// signed POST: signing a GET cleanly is awkward (base64 signatures do not
/// belong in URL query params), and the read is called at login when the
/// keypair IS available. The vault blob is ciphertext-only (zero-knowledge),
/// so a read leaks nothing usable — but defense-in-depth + uniformity with the
/// other vault routes justify the gate.
#[derive(Debug, serde::Deserialize)]
struct VaultGetRequest {
    signature: String,
    author_public_key: String,
    author_principal: String,
    timestamp: i64,
    nonce: String,
}

#[handler]
pub async fn vault_get(
    Json(req): Json<VaultGetRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let account_repo = &state.script_service.account_repo;
    let account_id =
        match verify_signed_account_request(account_repo, &state.pool, VAULT_GET_ACTION, &SignedAuthFields {
            signature: &req.signature,
            author_public_key: &req.author_public_key,
            author_principal: &req.author_principal,
            timestamp: req.timestamp,
            nonce: &req.nonce,
        }, |resolved| {
            serde_json::json!({
                "action": VAULT_GET_ACTION,
                "account_id": resolved,
                "nonce": req.nonce,
                "ts": req.timestamp,
            })
        })
        .await
        {
            Ok(id) => id,
            Err(r) => return error_response(r.status, r.message),
        };

    match state.passkey_service.get_vault(&account_id).await {
        Ok(Some(vault)) => Json(serde_json::json!({
            "success": true,
            "data": vault
        }))
        .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Vault not found"),
        Err(e) => {
            tracing::error!(
                account_id = %account_id,
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
    let blob = match decode_blob_fields(&req) {
        Ok(v) => v,
        Err((status, msg)) => return error_response(status, &msg),
    };

    let account_repo = &state.script_service.account_repo;
    let account_id =
        match verify_signed_account_request(account_repo, &state.pool, VAULT_UPDATE_ACTION, &vault_auth_fields(&req), |resolved| {
            serde_json::json!({
                "action": VAULT_UPDATE_ACTION,
                "account_id": resolved,
                "nonce": req.nonce,
                "ts": req.timestamp,
            })
        })
        .await
        {
            Ok(id) => id,
            Err(r) => return error_response(r.status, r.message),
        };

    match state
        .passkey_service
        .update_vault(&account_id, &blob.encrypted_data, &blob.salt, &blob.nonce)
        .await
    {
        Ok(()) => Json(serde_json::json!({ "success": true })).into_response(),
        Err(e) => {
            tracing::error!(
                account_id = %account_id,
                "vault update failed: {}",
                e
            );
            error_response(e.status(), e.message())
        }
    }
}
