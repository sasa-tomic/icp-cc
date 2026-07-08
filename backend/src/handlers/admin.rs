use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path},
    IntoResponse, Response,
};

use crate::{
    models::{self, AppState},
    responses::error_response,
    services::error::AccountError,
    startup_checks::is_development,
};

// Admin Account Operations

#[handler]
pub async fn admin_disable_key(
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
        Err(e) => {
            tracing::warn!("Admin failed to disable key: {}", e);
            account_error_response(e)
        }
    }
}

#[handler]
pub async fn admin_add_recovery_key(
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
        Err(e) => {
            tracing::warn!("Admin failed to add recovery key: {}", e);
            account_error_response(e)
        }
    }
}

/// Renders an [`AccountError`] for admin handlers. Same single source of
/// truth for variant → status as the user-facing account handlers.
fn account_error_response(e: AccountError) -> Response {
    error_response(e.status(), e.message())
}

#[handler]
pub async fn reset_database(Data(state): Data<&Arc<AppState>>) -> Response {
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

#[cfg(test)]
mod admin_token_tests {
    use crate::startup_checks::{is_insecure_admin_token, warn_if_insecure_prod_admin_token};

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
