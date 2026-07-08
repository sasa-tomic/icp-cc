use std::env;

use poem::{handler, web::Json};

/// Builds the canonical payload for script upload signature verification
#[handler]
pub async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "ICP Marketplace API is running",
        "environment": env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

#[handler]
pub async fn ping() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "pong",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}
