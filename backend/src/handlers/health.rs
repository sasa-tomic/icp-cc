use poem::{handler, web::Json};

use crate::startup_checks::Environment;

/// Builds the canonical payload for script upload signature verification
#[handler]
pub async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "ICP Marketplace API is running",
        // W7-014: single source of truth for the env label.
        "environment": Environment::current().as_str(),
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
