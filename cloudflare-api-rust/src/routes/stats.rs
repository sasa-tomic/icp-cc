use crate::types::*;
use crate::utils::*;
use worker::{console_log, Request, Response, Result, Method};

pub async fn handle_marketplace_stats_request(_req: Request, env: &AppEnv) -> Result<Response> {
    let db = DatabaseService::new(env);
    let database = db.get_database();

    // Get marketplace statistics
    let total_scripts = match database.prepare("SELECT COUNT(*) as count FROM scripts WHERE is_public = 1")
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(result)) => result["count"].as_i64().unwrap_or(0) as i32,
        _ => 0,
    };

    let total_authors = match database.prepare("SELECT COUNT(DISTINCT author_id) as count FROM scripts WHERE is_public = 1")
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(result)) => result["count"].as_i64().unwrap_or(0) as i32,
        _ => 0,
    };

    let total_downloads = match database.prepare("SELECT SUM(downloads) as total FROM scripts WHERE is_public = 1")
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(result)) => result["total"].as_i64().unwrap_or(0) as i32,
        _ => 0,
    };

    // Get average rating and total reviews
    let rating_stats = match database.prepare("SELECT AVG(rating) as avg_rating, COUNT(*) as total_reviews FROM reviews")
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(result)) => (
            result["avg_rating"].as_f64().unwrap_or(0.0),
            result["total_reviews"].as_i64().unwrap_or(0) as i32
        ),
        _ => (0.0, 0),
    };

    let stats = serde_json::json!({
        "totalScripts": total_scripts,
        "totalAuthors": total_authors,
        "totalDownloads": total_downloads,
        "averageRating": rating_stats.0,
        "totalReviews": rating_stats.1,
    });

    Ok(JsonResponse::success(stats, 200))
}

pub async fn handle_update_script_stats_request(mut req: Request, env: &AppEnv) -> Result<Response> {
    if req.method() != Method::Post {
        return Ok(JsonResponse::error("Method not allowed", 405));
    }

    let db = DatabaseService::new(env);
    let database = db.get_database();

    // Parse request body
    let body = match req.json::<serde_json::Value>().await {
        Ok(data) => data,
        Err(_) => return Ok(JsonResponse::error("Invalid JSON body", 400)),
    };

    let script_id = match body.get("scriptId").and_then(|v| v.as_str()) {
        Some(id) => id,
        None => return Ok(JsonResponse::error("scriptId is required", 400)),
    };

    let increment_downloads = body.get("incrementDownloads").and_then(|v| v.as_i64()).unwrap_or(0);

    if increment_downloads > 0 {
        // Update download count
        match database.prepare("UPDATE scripts SET downloads = downloads + ?1 WHERE id = ?2")
            .bind(&[increment_downloads.into(), script_id.into()])?
            .run()
            .await
        {
            Ok(_) => {
                console_log!("Updated download count for script: {}", script_id);
            }
            Err(e) => {
                console_log!("Failed to update download count: {:?}", e);
                return Ok(JsonResponse::error_with_details("Failed to update stats", &e.to_string(), 500));
            }
        }
    }

    Ok(JsonResponse::success(serde_json::json!({
        "message": "Stats updated successfully"
    }), 200))
}