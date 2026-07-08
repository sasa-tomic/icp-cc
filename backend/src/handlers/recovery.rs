use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path},
    IntoResponse, Response,
};

use crate::{models::AppState, responses::error_response};

#[derive(Debug, serde::Deserialize)]
struct RecoveryGenerateRequest {
    account_id: String,
}

#[handler]
pub async fn recovery_generate(
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
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[derive(Debug, serde::Deserialize)]
struct RecoveryVerifyRequest {
    account_id: String,
    code: String,
}

#[handler]
pub async fn recovery_verify(
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
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[handler]
pub async fn recovery_status(
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
        Err(e) => error_response(e.status(), e.message()),
    }
}
