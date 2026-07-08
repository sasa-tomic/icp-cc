use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path, Query},
    IntoResponse, Response,
};

use crate::{
    middleware,
    models::{
        AppState, CreateScriptRequest, DeleteScriptRequest, ScriptDetailQuery,
        ScriptDetailResponse, ScriptsQuery, SearchRequest, UpdateScriptRequest, UpdateStatsRequest,
    },
    responses::error_response,
    startup_checks::verify_script_ownership,
};

#[handler]
pub async fn get_scripts(
    Query(params): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let limit = params.limit.unwrap_or(20);
    let offset = params.offset.unwrap_or(0);
    let include_private = params.include_private.unwrap_or(false);

    match state
        .script_service
        .get_scripts(limit, offset, params.category, include_private)
        .await
    {
        Ok((scripts, total)) => Json(serde_json::json!({
            "success": true,
            "data": {
                "scripts": scripts,
                "total": total,
                "hasMore": (offset + limit) < total as i32
            }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get scripts: {}", e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get scripts")
        }
    }
}

#[handler]
pub async fn get_script(
    Path(script_id): Path<String>,
    Query(query): Query<ScriptDetailQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let script = match state.script_service.get_script(&script_id).await {
        Ok(Some(script)) => script,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to get script {}: {}", script_id, e);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get script");
        }
    };

    // Entitlement gate. Free scripts (price <= 0) always ship the full bundle.
    // Paid scripts ship the bundle ONLY when the caller owns the script OR has
    // a purchase record; otherwise `bundle` is dropped (rendered as `null`) and
    // `purchased: false` so the UI can render a Buy CTA. This is the security
    // fix for the HIGH-severity leak where the public endpoint used to return
    // the full paid bundle to anyone.
    let entitled = if script.price <= 0.0 {
        true
    } else if let Some(account_id) = query.account_id.as_deref() {
        // Owner of the script is always entitled to their own bundle.
        if script.owner_account_id.as_deref() == Some(account_id) {
            true
        } else {
            match state
                .purchase_repo
                .exists_for_account_and_script(account_id, &script_id)
                .await
            {
                Ok(purchased) => purchased,
                Err(e) => {
                    tracing::error!(
                        "Failed to check purchase entitlement for account={} script={}: {}",
                        account_id,
                        script_id,
                        e
                    );
                    return error_response(
                        StatusCode::INTERNAL_SERVER_ERROR,
                        "Failed to verify purchase entitlement",
                    );
                }
            }
        }
    } else {
        false
    };

    let detail = if entitled {
        ScriptDetailResponse::entitled(script)
    } else {
        ScriptDetailResponse::locked(script)
    };

    Json(serde_json::json!({
        "success": true,
        "data": detail
    }))
    .into_response()
}

/// Lightweight browse-time preview (UX-6). Returns a CAPPED excerpt of the
/// source plus browse-relevant metadata instead of the full bundle, so the
/// Script Details dialog stops downloading the whole script just to show 50
/// lines. For paid scripts the cap is smaller and the full source is NEVER
/// sent. Public (no auth) — same reachability as `get_script` / `get_scripts`.
#[handler]
pub async fn get_script_preview(
    Path(script_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state.script_service.get_script_preview(&script_id).await {
        Ok(Some(preview)) => Json(serde_json::json!({
            "success": true,
            "data": preview
        }))
        .into_response(),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to get script preview {}: {}", script_id, e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get script preview",
            )
        }
    }
}

#[handler]
pub async fn get_scripts_count(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_scripts_count().await {
        Ok(count) => Json(serde_json::json!({
            "success": true,
            "data": { "count": count }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get count: {}", e);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to get count")
        }
    }
}

#[handler]
pub async fn get_marketplace_stats(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_marketplace_stats().await {
        Ok((scripts_count, total_downloads, avg_rating)) => Json(serde_json::json!({
            "success": true,
            "data": {
                "totalScripts": scripts_count,
                "totalDownloads": total_downloads,
                "averageRating": avg_rating,
                "timestamp": chrono::Utc::now().to_rfc3339()
            }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get marketplace stats: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get marketplace stats",
            )
        }
    }
}

#[handler]
pub async fn create_script(
    Json(req): Json<CreateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script creation", || {
        middleware::auth::build_upload_payload(&req)
    }) {
        return *response;
    }

    // Create script via service
    match state.script_service.create_script(req).await {
        Ok(script) => {
            tracing::info!(
                "Created script: {} (slug: {}, public: {})",
                script.id,
                script.slug,
                script.is_public
            );
            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": {
                        "id": script.id,
                        "slug": script.slug,
                        "title": script.title,
                        "created_at": script.created_at
                    }
                })),
            )
                .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to create script: {}", e);
            // Variant decides status (single source of truth): Forbidden for
            // slug-ownership disputes, Internal for everything else.
            error_response(e.status(), e.message())
        }
    }
}

#[handler]
pub async fn update_script(
    Path(script_id): Path<String>,
    Json(req): Json<UpdateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script update", || {
        middleware::auth::build_canonical_update_payload(&req, &script_id)
    }) {
        return *response;
    }

    // Check script ownership
    if let Err(response) = verify_script_ownership(state, &script_id, &req.author_public_key).await
    {
        return response;
    }

    // Update script via service
    match state.script_service.update_script(&script_id, req).await {
        Ok(script) => {
            tracing::info!(
                "Updated script: {} (version: {})",
                script.id,
                script.version
            );
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": script.id,
                    "updated_at": script.updated_at
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to update script {}: {}", script_id, e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                &format!("Failed to update script: {}", e),
            )
        }
    }
}

#[handler]
pub async fn delete_script(
    Path(script_id): Path<String>,
    Json(req): Json<DeleteScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script deletion", || {
        middleware::auth::build_deletion_payload(&req, &script_id)
    }) {
        return *response;
    }

    // Check script ownership
    if let Err(response) = verify_script_ownership(state, &script_id, &req.author_public_key).await
    {
        return response;
    }

    // Check if script exists
    match state.script_service.check_script_exists(&script_id).await {
        Ok(true) => {
            // Delete script via service (soft delete)
            match state.script_service.delete_script(&script_id).await {
                Ok(()) => {
                    tracing::info!("Soft deleted script: {}", script_id);
                    Json(serde_json::json!({
                        "success": true,
                        "message": "Script deleted successfully"
                    }))
                    .into_response()
                }
                Err(e) => {
                    tracing::error!("Failed to delete script {}: {}", script_id, e);
                    error_response(
                        StatusCode::INTERNAL_SERVER_ERROR,
                        &format!("Failed to delete script: {}", e),
                    )
                }
            }
        }
        Ok(false) => {
            tracing::warn!("Script deletion failed: {} not found", script_id);
            error_response(StatusCode::NOT_FOUND, "Script not found")
        }
        Err(e) => {
            tracing::error!("Failed to check script existence: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to check script existence",
            )
        }
    }
}

#[handler]
pub async fn search_scripts(
    Json(request): Json<SearchRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    tracing::info!(
        "Search request: query={:?}, category={:?}, limit={:?}, offset={:?}",
        request.query,
        request.category,
        request.limit,
        request.offset
    );

    match state.script_service.search_scripts(&request).await {
        Ok(result) => {
            let has_more = result.offset + (result.scripts.len() as i64) < result.total;

            tracing::info!(
                "Search returned {} scripts (offset={}, limit={}, total={})",
                result.scripts.len(),
                result.offset,
                result.limit,
                result.total
            );

            Json(serde_json::json!({
                "success": true,
                "data": {
                    "scripts": result.scripts,
                    "total": result.total,
                    "hasMore": has_more,
                    "offset": result.offset,
                    "limit": result.limit
                }
            }))
            .into_response()
        }
        Err((status, message)) => {
            tracing::error!("Search failed with status {}: {}", status, message);
            error_response(status, &message)
        }
    }
}

#[handler]
pub async fn get_scripts_by_category(
    Path(category): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match state
        .script_service
        .get_scripts_by_category(&category, 100)
        .await
    {
        Ok(scripts) => {
            tracing::debug!("Category '{}' has {} scripts", category, scripts.len());
            Json(serde_json::json!({
                "success": true,
                "data": scripts
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to get scripts by category: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get scripts by category",
            )
        }
    }
}

#[handler]
pub async fn publish_script(
    Path(script_id): Path<String>,
    Json(req): Json<UpdateScriptRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Verify authentication
    if let Err(response) = middleware::verify_request_auth(&req, "Script publish", || {
        middleware::auth::build_publish_payload(&req, &script_id)
    }) {
        return *response;
    }

    // Publish script via service
    match state.script_service.publish_script(&script_id).await {
        Ok(script) => {
            tracing::info!(
                "Published script: {} (is_public: {})",
                script.id,
                script.is_public
            );
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "id": script.id,
                    "updated_at": script.updated_at
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to publish script {}: {}", script_id, e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                &format!("Failed to publish script: {}", e),
            )
        }
    }
}

#[handler]
pub async fn get_trending_scripts(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_trending(20).await {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get trending scripts: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get trending scripts",
            )
        }
    }
}

#[handler]
pub async fn get_featured_scripts(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_featured(4.5, 10, 10).await {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get featured scripts: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get featured scripts",
            )
        }
    }
}

#[handler]
pub async fn get_compatible_scripts(
    Query(_params): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // For now, return all compatible scripts
    match state.script_service.get_compatible("all", 20).await {
        Ok(scripts) => Json(serde_json::json!({
            "success": true,
            "data": scripts
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get compatible scripts: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get compatible scripts",
            )
        }
    }
}

#[handler]
pub async fn update_script_stats(
    Json(req): Json<UpdateStatsRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    if let Some(increment) = req.increment_downloads {
        if increment > 0 {
            match state
                .script_service
                .increment_downloads(&req.script_id)
                .await
            {
                Ok(_) => {
                    tracing::info!("Updated download count for script: {}", req.script_id);
                    Json(serde_json::json!({
                        "success": true,
                        "message": "Stats updated successfully"
                    }))
                    .into_response()
                }
                Err(e) => {
                    tracing::error!("Failed to update stats for script {}: {}", req.script_id, e);
                    error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to update stats")
                }
            }
        } else {
            Json(serde_json::json!({
                "success": true,
                "message": "No stats to update"
            }))
            .into_response()
        }
    } else {
        Json(serde_json::json!({
            "success": true,
            "message": "No stats to update"
        }))
        .into_response()
    }
}
