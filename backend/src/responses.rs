use poem::{http::StatusCode, IntoResponse, Response};
use serde::Serialize;
use serde_json::json;

#[derive(Debug, Serialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl<T: Serialize> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn error(error: impl Into<String>) -> ApiResponse<()> {
        ApiResponse {
            success: false,
            data: None,
            error: Some(error.into()),
        }
    }
}

impl<T: Serialize + Send> IntoResponse for ApiResponse<T> {
    fn into_response(self) -> Response {
        poem::web::Json(json!(self)).into_response()
    }
}

pub fn success_response<T: Serialize + Send>(data: T) -> Response {
    ApiResponse::ok(data).into_response()
}

pub fn error_response(status: StatusCode, error: &str) -> Response {
    (
        status,
        poem::web::Json(json!({
            "success": false,
            "error": error
        })),
    )
        .into_response()
}
