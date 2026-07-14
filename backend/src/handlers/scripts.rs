use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path, Query},
    IntoResponse, Response,
};

use crate::{
    auth,
    middleware,
    models::{
        AppState, CreateScriptRequest, DeleteScriptRequest, EntitlementRequest,
        ScriptDetailResponse, ScriptsQuery, SearchRequest, UpdateScriptRequest,
        scripts_to_list_json,
    },
    repositories::SignatureAuditParams,
    responses::error_response,
    startup_checks::verify_script_ownership,
};

/// Single source of truth for the signed-entitlement action name. The client
/// signs this exact string inside the canonical JSON payload and the server
/// verifies it — both sides MUST agree, so it is named once here (and mirrored
/// in the Dart `ScriptSignatureService.signEntitlement`).
const ENTITLEMENT_ACTION: &str = "entitlement";

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
                "scripts": scripts_to_list_json(&scripts),
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

/// `GET /api/v1/scripts/:id` — public script detail.
///
/// **Security (W7-2):** for a PAID script this ALWAYS returns
/// [`ScriptDetailResponse::locked`] — i.e. `bundle: null`. The paid source is
/// obtainable ONLY via the authenticated `POST /scripts/:id/download`, which
/// gates on a real Ed25519 signature + purchase record. Free scripts (price
/// <= 0) keep shipping the full bundle. The former `?account_id=<owner>`
/// query branch was an entitlement bypass: `account_id` is a *public*
/// identifier (leaked by `GET /accounts/:username` and
/// `ScriptDetailResponse.owner_account_id`), so anyone could spoof it and
/// receive the full paid bundle. It is now removed.
///
/// The `purchased` boolean is metadata-safe and stays in the response, but is
/// always `false` for paid scripts here (the locked view). The signed
/// `POST /scripts/:id/entitlement` endpoint is the sole source of truth for a
/// caller's purchase/ownership state — the frontend uses it to drive the
/// Buy/Download CTA.
#[handler]
pub async fn get_script(
    Path(script_id): Path<String>,
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

    // Free scripts (price <= 0) always ship the full bundle. Paid scripts are
    // ALWAYS locked here — the bundle is only released via the signed download
    // endpoint, which already gates correctly.
    let detail = if script.price <= 0.0 {
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

/// `POST /api/v1/scripts/:id/entitlement` — signed entitlement check.
///
/// Replaces the entitlement bypass closed in `get_script`. Lets the frontend
/// drive the Buy/Download CTA WITHOUT leaking the paid bundle: it returns only
/// `{purchased: bool, owns: bool}`. The caller proves their identity with an
/// Ed25519 (or secp256k1) signature over the canonical payload
/// `{action:"entitlement", id:<script_id>, nonce:<nonce>, ts:<timestamp>}`;
/// the server resolves the caller's `account_id` SERVER-SIDE from the verified
/// public key (never trusts a client-supplied account id). Mirrors the auth +
/// replay-prevention + signature-audit pattern proven on the signed download
/// endpoint (`handlers::payments::download_script`).
#[handler]
pub async fn entitlement_check(
    Path(script_id): Path<String>,
    Json(req): Json<EntitlementRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // 1. Resolve account_id from the public key FIRST (never trust a
    //    client-supplied identity). Unknown key → 401.
    let account_id = match state
        .script_service
        .account_repo
        .find_public_key_by_value(&req.author_public_key)
        .await
    {
        Ok(Some(key)) => key.account_id,
        Ok(None) => {
            tracing::warn!(
                "Entitlement rejected: public key not bound to any account (script={})",
                script_id
            );
            return error_response(StatusCode::UNAUTHORIZED, "Unknown public key");
        }
        Err(e) => {
            tracing::error!(
                "Failed to lookup public key for entitlement (script={}): {}",
                script_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to resolve account for entitlement",
            );
        }
    };

    // 2. Build the canonical payload and verify the signature. The payload is
    //    canonicalised by `verify_operation_signature` (keys sorted
    //    alphabetically) — the frontend `ScriptSignatureService.signEntitlement`
    //    builds the identical canonical bytes.
    let payload = serde_json::json!({
        "action": ENTITLEMENT_ACTION,
        "id": script_id,
        "nonce": req.nonce,
        "ts": req.timestamp,
    });
    if let Err(e) = auth::verify_operation_signature(
        Some(&req.signature),
        Some(&req.author_public_key),
        Some(&req.author_principal),
        &payload,
    ) {
        tracing::warn!(
            "Entitlement rejected: signature verification failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(StatusCode::UNAUTHORIZED, "Invalid signature");
    }

    // 3. Replay prevention (mirrors download_script step 2b): the signed
    //    `timestamp`+`nonce` MUST be freshness-checked and single-use so a
    //    captured signed request cannot be replayed.
    if let Err(e) =
        auth::validate_replay_prevention(&state.pool, req.timestamp, &req.nonce).await
    {
        let status = match e {
            auth::AuthError::InvalidFormat(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::UNAUTHORIZED,
        };
        tracing::warn!(
            "Entitlement rejected: replay prevention failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(status, "Replay prevention failed");
    }

    // 4. Load script. 404 if absent — entitlement is meaningless for a ghost.
    let script = match state.script_service.get_script(&script_id).await {
        Ok(Some(s)) => s,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to load script for entitlement {}: {}", script_id, e);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to load script for entitlement",
            );
        }
    };

    // 5. Compute entitlement. `owns` = caller is the script owner. `purchased`
    //    = owns OR free OR holds a purchase record. `account_id` is always
    //    server-derived (step 1), never client-supplied.
    let owns = script.owner_account_id.as_deref() == Some(account_id.as_str());
    let purchased = if script.price <= 0.0 || owns {
        true
    } else {
        match state
            .purchase_repo
            .exists_for_account_and_script(&account_id, &script_id)
            .await
        {
            Ok(p) => p,
            Err(e) => {
                tracing::error!(
                    "Failed to check purchase for entitlement (script={}, account={}): {}",
                    script_id,
                    account_id,
                    e
                );
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to verify purchase entitlement",
                );
            }
        }
    };

    // 6. Record the signature audit so the `(timestamp, nonce)` pair is
    //    single-use within the 10-minute window (the WRITE side of step 3).
    //    Fail-closed: if the audit cannot be recorded, the request is
    //    replayable, so we refuse to return the entitlement.
    let audit_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    let canonical_payload = auth::create_canonical_payload(&payload);
    if let Err(e) = state
        .script_service
        .account_repo
        .record_signature_audit(SignatureAuditParams {
            audit_id: &audit_id,
            account_id: Some(&account_id),
            action: ENTITLEMENT_ACTION,
            payload: &canonical_payload,
            signature: &req.signature,
            public_key: &req.author_public_key,
            timestamp: req.timestamp,
            nonce: &req.nonce,
            is_admin_action: false,
            now: &now,
        })
        .await
    {
        tracing::error!(
            "Failed to record entitlement audit — refusing to return entitlement \
             (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to record entitlement audit",
        );
    }

    Json(serde_json::json!({
        "success": true,
        "data": {
            "purchased": purchased,
            "owns": owns,
        }
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
                    "scripts": scripts_to_list_json(&result.scripts),
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

/// `GET /api/v1/scripts/categories` — distinct, content-derived categories
/// among public scripts. Fixes UXR-9: registered BEFORE `/scripts/:id` so the
/// literal path `categories` is no longer shadowed by the `:id` capture (which
/// previously returned the misleading "Script not found" for this route).
#[handler]
pub async fn get_script_categories(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.script_service.get_categories().await {
        Ok(categories) => Json(serde_json::json!({
            "success": true,
            "data": { "categories": categories }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get script categories: {}", e);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to get script categories",
            )
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
                "data": scripts_to_list_json(&scripts)
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
            "data": scripts_to_list_json(&scripts)
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
            "data": scripts_to_list_json(&scripts)
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
            "data": scripts_to_list_json(&scripts)
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
