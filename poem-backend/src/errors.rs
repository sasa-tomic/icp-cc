use poem::{http::StatusCode, IntoResponse, Response};
use serde_json::json;

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Authentication failed: {0}")]
    Unauthorized(String),

    #[error("Validation failed: {0}")]
    Validation(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Internal server error: {0}")]
    Internal(String),
}

impl ApiError {
    pub fn status_code(&self) -> StatusCode {
        match self {
            ApiError::Database(_) => StatusCode::INTERNAL_SERVER_ERROR,
            ApiError::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            ApiError::Validation(_) | ApiError::BadRequest(_) => StatusCode::BAD_REQUEST,
            ApiError::NotFound(_) => StatusCode::NOT_FOUND,
            ApiError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    pub fn unauthorized(msg: impl Into<String>) -> Self {
        ApiError::Unauthorized(msg.into())
    }

    pub fn validation(msg: impl Into<String>) -> Self {
        ApiError::Validation(msg.into())
    }

    pub fn not_found(msg: impl Into<String>) -> Self {
        ApiError::NotFound(msg.into())
    }

    pub fn bad_request(msg: impl Into<String>) -> Self {
        ApiError::BadRequest(msg.into())
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        ApiError::Internal(msg.into())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = self.status_code();
        (
            status,
            poem::web::Json(json!({
                "success": false,
                "error": self.to_string()
            })),
        )
            .into_response()
    }
}
