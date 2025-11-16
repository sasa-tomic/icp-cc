use poem::{http::StatusCode, IntoResponse, Response};
use serde_json::json;

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
