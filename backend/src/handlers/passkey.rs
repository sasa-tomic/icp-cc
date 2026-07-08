use std::sync::Arc;

use poem::{
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
        Err(e) => error_response(StatusCode::BAD_REQUEST, &e),
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
        Err(e) => error_response(StatusCode::BAD_REQUEST, &e),
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
        Err(e) => error_response(StatusCode::BAD_REQUEST, &e),
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
        Err(e) => error_response(StatusCode::UNAUTHORIZED, &e),
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
        Err(e) => error_response(StatusCode::INTERNAL_SERVER_ERROR, &e),
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
