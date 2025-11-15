use crate::types::*;
use crate::utils::*;
use worker::{console_log, Request, Response, Result, Method};

pub async fn handle_reviews_request(req: Request, env: &AppEnv, script_id: &str) -> Result<Response> {
    let db = DatabaseService::new(env);
    let database = db.get_database();

    // Parse query parameters for pagination
    let query_params = match req.query::<ReviewsQueryParams>() {
        Ok(params) => params,
        Err(_) => ReviewsQueryParams::default(),
    };
    let limit = query_params.limit.unwrap_or(20);
    let offset = query_params.offset.unwrap_or(0);

    // Get reviews for this script
    let reviews_query = format!(
        "SELECT * FROM reviews WHERE script_id = ?1 ORDER BY created_at DESC LIMIT {} OFFSET {}",
        limit, offset
    );

    let reviews = match database.prepare(&reviews_query)
        .bind(&[script_id.into()])?
        .all()
        .await
    {
        Ok(_results) => {
            let reviews: Vec<Review> = vec![]; // TODO: Implement proper review extraction from results
            reviews
        }
        Err(e) => {
            console_log!("Failed to fetch reviews: {:?}", e);
            return Ok(JsonResponse::error_with_details("Failed to fetch reviews", &e.to_string(), 500));
        }
    };

    // Get total count for pagination
    let total_reviews = match database.prepare("SELECT COUNT(*) as count FROM reviews WHERE script_id = ?1")
        .bind(&[script_id.into()])?
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(result)) => result["count"].as_i64().unwrap_or(0) as i32,
        _ => 0,
    };

    let response_data = serde_json::json!({
        "reviews": reviews,
        "total": total_reviews,
        "hasMore": (offset + limit) < total_reviews
    });

    Ok(JsonResponse::success(response_data, 200))
}

pub async fn handle_create_review_request(mut req: Request, env: &AppEnv, script_id: &str) -> Result<Response> {
    if req.method() != Method::Post {
        return Ok(JsonResponse::error("Method not allowed", 405));
    }

    // Parse request body
    let review_data = match req.json::<serde_json::Value>().await {
        Ok(data) => data,
        Err(_) => return Ok(JsonResponse::error("Invalid JSON body", 400)),
    };

    let rating = match review_data.get("rating").and_then(|v| v.as_i64()) {
        Some(rating) if rating >= 1 && rating <= 5 => rating as i32,
        Some(_) => return Ok(JsonResponse::error("Rating must be between 1 and 5", 400)),
        None => return Ok(JsonResponse::error("Rating is required", 400)),
    };

    let comment = review_data.get("comment").and_then(|v| v.as_str()).map(String::from);
    let user_id = review_data.get("userId").and_then(|v| v.as_str()).unwrap_or_default();

    if user_id.is_empty() {
        return Ok(JsonResponse::error("User ID is required", 400));
    }

    let db = DatabaseService::new(env);
    let database = db.get_database();

    // Check if script exists
    match database.prepare("SELECT id FROM scripts WHERE id = ?1")
        .bind(&[script_id.into()])?
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(_)) => {},
        Ok(None) => return Ok(JsonResponse::error("Script not found", 404)),
        Err(e) => {
            console_log!("Failed to check script existence: {:?}", e);
            return Ok(JsonResponse::error_with_details("Database error", &e.to_string(), 500));
        }
    }

    // Check if user already reviewed this script
    match database.prepare("SELECT id FROM reviews WHERE script_id = ?1 AND user_id = ?2")
        .bind(&[script_id.into(), user_id.into()])?
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(_)) => return Ok(JsonResponse::error("You have already reviewed this script", 409)),
        Ok(None) => {}, // Continue
        Err(e) => {
            console_log!("Failed to check existing review: {:?}", e);
            return Ok(JsonResponse::error_with_details("Database error", &e.to_string(), 500));
        }
    }

    // Generate review ID
    let review_id = format!("{}_{}", script_id, user_id);
    let timestamp = time::OffsetDateTime::now_utc();

    // Insert the review
    match database.prepare("INSERT INTO reviews (id, script_id, user_id, rating, comment, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)")
        .bind(&[
            review_id.clone().into(),
            script_id.into(),
            user_id.into(),
            rating.into(),
            comment.as_ref().map(|s| s.as_str()).unwrap_or("").into(),
            timestamp.to_string().into(),
            timestamp.to_string().into(),
        ])?
        .run()
        .await
    {
        Ok(_) => {
            console_log!("Created review for script: {} by user: {}", script_id, user_id);

            // Update script's average rating
            update_script_rating(&database, script_id).await?;

            let review = Review {
                id: review_id,
                script_id: script_id.to_string(),
                user_id: user_id.to_string(),
                rating,
                comment,
                created_at: timestamp,
                updated_at: timestamp,
            };

            Ok(JsonResponse::success(review, 201))
        }
        Err(e) => {
            console_log!("Failed to create review: {:?}", e);
            Ok(JsonResponse::error_with_details("Failed to create review", &e.to_string(), 500))
        }
    }
}

async fn update_script_rating(database: &worker::D1Database, script_id: &str) -> Result<()> {
    // Calculate new average rating
    match database.prepare("SELECT AVG(rating) as avg_rating, COUNT(*) as count FROM reviews WHERE script_id = ?1")
        .bind(&[script_id.into()])?
        .first::<serde_json::Value>(None)
        .await
    {
        Ok(Some(result)) => {
            let avg_rating = result["avg_rating"].as_f64().unwrap_or(0.0);
            let review_count = result["count"].as_i64().unwrap_or(0) as i32;

            // Update script with new rating
            match database.prepare("UPDATE scripts SET rating = ?1, review_count = ?2 WHERE id = ?3")
                .bind(&[avg_rating.into(), review_count.into(), script_id.into()])?
                .run()
                .await
            {
                Ok(_) => {
                    console_log!("Updated rating for script {}: {:.2} ({} reviews)", script_id, avg_rating, review_count);
                }
                Err(e) => {
                    console_log!("Failed to update script rating: {:?}", e);
                }
            }
        }
        _ => {
            console_log!("Failed to calculate new rating for script: {}", script_id);
        }
    }
    Ok(())
}