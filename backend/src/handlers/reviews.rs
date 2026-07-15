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
    signature_gate::{verify_signed_account_request, SignedAuthFields},
};

/// Single source of truth for the signed review action name. The frontend
/// mirrors this EXACT string inside the canonical payload.
const REVIEW_CREATE_ACTION: &str = "review:create";

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

/// `POST /api/v1/scripts/:id/reviews` — signature-gated (W7-15).
///
/// The author (`user_id`) is resolved SERVER-SIDE from the verified public key
/// — NEVER trusted from the request body. This closes the W7-006 exploit where
/// anyone could post a review as any user (and 1★/5★-bomb any script, corrupting
/// the rating-driven featured/trending ordering). The signature binds
/// `{action:"review:create", script_id, rating, nonce, ts}` so neither the
/// target script nor the rating can be tampered with after signing.
#[derive(Debug, serde::Deserialize)]
struct CreateReviewWireRequest {
    // --- auth fields (resolve user_id server-side) ---
    signature: String,
    author_public_key: String,
    author_principal: String,
    timestamp: i64,
    nonce: String,
    // --- review content ---
    rating: i32,
    comment: Option<String>,
}

#[handler]
pub async fn create_review(
    Path(script_id): Path<String>,
    Json(req): Json<CreateReviewWireRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let account_repo = &state.script_service.account_repo;
    let user_id = match verify_signed_account_request(
        account_repo,
        &state.pool,
        REVIEW_CREATE_ACTION,
        &SignedAuthFields {
            signature: &req.signature,
            author_public_key: &req.author_public_key,
            author_principal: &req.author_principal,
            timestamp: req.timestamp,
            nonce: &req.nonce,
        },
        |resolved| {
            serde_json::json!({
                "action": REVIEW_CREATE_ACTION,
                "script_id": script_id,
                "rating": req.rating,
                "account_id": resolved,
                "nonce": req.nonce,
                "ts": req.timestamp,
            })
        },
    )
    .await
    {
        Ok(id) => id,
        Err(r) => return error_response(r.status, r.message),
    };

    // Build the service request with the SERVER-RESOLVED user_id (never the
    // client-supplied value).
    let review_req = CreateReviewRequest {
        user_id,
        rating: req.rating,
        comment: req.comment,
    };

    match state.review_service.create_review(&script_id, review_req).await {
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
