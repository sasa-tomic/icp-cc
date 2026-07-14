use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path},
    IntoResponse, Response,
};

use crate::{
    models::AppState,
    responses::error_response,
    services::{PasskeyAuthenticationFinish, PasskeyRegistrationFinish},
    signature_gate::{verify_signed_account_request, SignedAuthFields},
};

// ============================================================================
// Passkey Authentication Handlers
// ============================================================================
//
// ## W7-13 — signature-gated enrolment / deletion (closes W7-004)
//
// `register/start` and `delete` now require the caller to prove ownership of an
// account keypair BEFORE enrolling a new credential or removing one. The server
// resolves `account_id` SERVER-SIDE from the verified public key and binds the
// operation to THAT account — never the request body's value. This closes the
// account-takeover exploit where anyone could enrol their OWN authenticator on
// ANY account (then authenticate as the victim) or delete a victim's passkey.
//
// `register/finish` needs no separate signature: it completes a challenge whose
// `account_id` was already bound to the proven owner at the (now-gated) start.
// `authenticate/start` + `authenticate/finish` STAY OPEN — passkey auth IS the
// login mechanism; you cannot require prior auth to authenticate. The `finish`
// already proves passkey possession.

/// Single source of truth for the signed passkey action names. The frontend
/// `PasskeyService` mirrors these EXACT strings inside the canonical payload.
const PASSKEY_REGISTER_ACTION: &str = "passkey:register";
const PASSKEY_DELETE_ACTION: &str = "passkey:delete";

#[derive(Debug, serde::Deserialize)]
struct PasskeyRegisterStartRequest {
    // account_id is resolved SERVER-SIDE from the signature (never trusted
    // from the body); serde ignores any client-supplied value.
    username: String,
    // --- auth fields (resolve account_id server-side) ---
    signature: String,
    author_public_key: String,
    author_principal: String,
    timestamp: i64,
    nonce: String,
}

#[handler]
pub async fn passkey_register_start(
    Json(req): Json<PasskeyRegisterStartRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let account_repo = &state.script_service.account_repo;
    let account_id = match verify_signed_account_request(
        account_repo,
        &state.pool,
        PASSKEY_REGISTER_ACTION,
        &SignedAuthFields {
            signature: &req.signature,
            author_public_key: &req.author_public_key,
            author_principal: &req.author_principal,
            timestamp: req.timestamp,
            nonce: &req.nonce,
        },
        |resolved| {
            serde_json::json!({
                "action": PASSKEY_REGISTER_ACTION,
                "account_id": resolved,
                "nonce": req.nonce,
                "ts": req.timestamp,
            })
        },
    )
    .await
    {
        Ok(id) => id,
        Err(r) => return error_response(r.status, r.message),
    };

    match state
        .passkey_service
        .start_registration(&account_id, &req.username)
        .await
    {
        Ok(result) => Json(serde_json::json!({
            "success": true,
            "data": result
        }))
        .into_response(),
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[handler]
pub async fn passkey_register_finish(
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
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[derive(Debug, serde::Deserialize)]
struct PasskeyAuthStartRequest {
    account_id: String,
}

#[handler]
pub async fn passkey_authenticate_start(
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
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[handler]
pub async fn passkey_authenticate_finish(
    Json(req): Json<PasskeyAuthenticationFinish>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.passkey_service.finish_authentication(req).await {
        Ok(account_id) => Json(serde_json::json!({
            "success": true,
            "data": { "account_id": account_id }
        }))
        .into_response(),
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[handler]
pub async fn passkey_list(
    Path(account_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.passkey_service.list_passkeys(&account_id).await {
        Ok(passkeys) => Json(serde_json::json!({
            "success": true,
            "data": passkeys
        }))
        .into_response(),
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[derive(Debug, serde::Deserialize)]
struct PasskeyDeleteRequest {
    // account_id is resolved SERVER-SIDE from the signature (never trusted
    // from the body); serde ignores any client-supplied value.
    // --- auth fields (resolve account_id server-side) ---
    signature: String,
    author_public_key: String,
    author_principal: String,
    timestamp: i64,
    nonce: String,
}

#[handler]
pub async fn passkey_delete(
    Path(passkey_id): Path<String>,
    Json(req): Json<PasskeyDeleteRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let account_repo = &state.script_service.account_repo;
    let account_id = match verify_signed_account_request(
        account_repo,
        &state.pool,
        PASSKEY_DELETE_ACTION,
        &SignedAuthFields {
            signature: &req.signature,
            author_public_key: &req.author_public_key,
            author_principal: &req.author_principal,
            timestamp: req.timestamp,
            nonce: &req.nonce,
        },
        |resolved| {
            serde_json::json!({
                "action": PASSKEY_DELETE_ACTION,
                "passkey_id": passkey_id,
                "account_id": resolved,
                "nonce": req.nonce,
                "ts": req.timestamp,
            })
        },
    )
    .await
    {
        Ok(id) => id,
        Err(r) => return error_response(r.status, r.message),
    };

    match state
        .passkey_service
        .delete_passkey(&passkey_id, &account_id)
        .await
    {
        Ok(()) => Json(serde_json::json!({
            "success": true
        }))
        .into_response(),
        Err(e) => {
            // Variant decides status (NotFound for unknown passkey,
            // BadRequest for last-passkey guard, Internal for DB errors).
            error_response(e.status(), e.message())
        }
    }
}
