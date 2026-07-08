use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path},
    IntoResponse, Response,
};

use crate::{
    models::{
        AddPublicKeyRequest, AppState, RegisterAccountRequest, RemovePublicKeyRequest,
        UpdateAccountRequest,
    },
    responses::error_response,
    services::error::AccountError,
};

// Account profiles Endpoints

#[handler]
pub async fn register_account(
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
        Err(e) => {
            tracing::warn!("Failed to register account: {}", e);
            account_error_response(e)
        }
    }
}

#[handler]
pub async fn get_account(
    Path(username): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
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
        Err(e) => {
            tracing::error!("Failed to get account: {}", e);
            account_error_response(e)
        }
    }
}

#[handler]
pub async fn get_account_by_public_key(
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
        Err(e) => {
            tracing::error!("Failed to get account by public key: {}", e);
            // All failures here are internal (DB) — the typed variant decides.
            account_error_response(e)
        }
    }
}

#[handler]
pub async fn update_account(
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
        Err(e) => {
            tracing::warn!("Failed to update account: {}", e);
            account_error_response(e)
        }
    }
}

#[handler]
pub async fn add_account_key(
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
        Err(e) => {
            tracing::warn!("Failed to add public key: {}", e);
            account_error_response(e)
        }
    }
}

#[handler]
pub async fn remove_account_key(
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
        Err(e) => {
            tracing::warn!("Failed to remove public key: {}", e);
            account_error_response(e)
        }
    }
}

/// Renders an [`AccountError`] into the canonical wire-shape error response.
/// The variant decides the HTTP status (single source of truth:
/// [`AccountError`]'s `ResponseError::status`] impl); the message round-trips
/// verbatim into the JSON body.
fn account_error_response(e: AccountError) -> Response {
    error_response(e.status(), e.message())
}
