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
};

// ============================================================================
// Passkey Authentication Handlers
// ============================================================================

#[derive(Debug, serde::Deserialize)]
struct PasskeyRegisterStartRequest {
    account_id: String,
    username: String,
}

#[handler]
pub async fn passkey_register_start(
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
    account_id: String,
}

#[handler]
pub async fn passkey_delete(
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
            // Variant decides status (NotFound for unknown passkey,
            // BadRequest for last-passkey guard, Internal for DB errors).
            error_response(e.status(), e.message())
        }
    }
}
