use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path, Query},
    IntoResponse, Response,
};

use crate::{
    models::{AppState, CreateReviewRequest, ReviewsQuery},
    responses::error_response,
};

#[handler]
pub async fn get_reviews(
    Path(script_id): Path<String>,
    Query(params): Query<ReviewsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let limit = params.limit.unwrap_or(20);
    let offset = params.offset.unwrap_or(0);

    match state
        .review_service
        .get_reviews(&script_id, limit, offset)
        .await
    {
        Ok((reviews, total)) => Json(serde_json::json!({
            "success": true,
            "data": {
                "reviews": reviews,
                "total": total,
                "hasMore": (offset + limit) < total
            }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get reviews for script {}: {}", script_id, e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get reviews")
        }
    }
}

#[handler]
pub async fn create_review(
    Path(script_id): Path<String>,
    Json(req): Json<CreateReviewRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.review_service.create_review(&script_id, req).await {
        Ok(review) => {
            tracing::info!(
                "Created review for script {} by user {}",
                script_id,
                review.user_id
            );
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": review
                })),
            )
                .into_response()
        }
        Err(e) => {
            tracing::warn!("Failed to create review: {}", e);
            // Variant decides status (NotFound / Conflict / BadRequest /
            // Internal) — single source of truth in the ReviewError impl.
            error_response(e.status(), e.message())
        }
    }
}
