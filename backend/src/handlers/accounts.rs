use std::sync::Arc;

use poem::{
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
        Err(message) => {
            tracing::error!("Failed to get account by public key: {}", message);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, &message)
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
