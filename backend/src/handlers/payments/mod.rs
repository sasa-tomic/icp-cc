use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path},
    IntoResponse, Request, Response,
};

use crate::{
    auth,
    handlers::PURCHASE_ACTION,
    models::{AppState, DownloadRequest, EntitlementRequest},
    repositories::SignatureAuditParams,
    responses::error_response,
    services::{PaymentError, PurchaseStatus},
};

// ============================================================================
// Provider-agnostic payment integration + paid-script entitlement gate
// ============================================================================

/// Canonical signature payload for `POST /api/v1/scripts/:id/download`. The
/// client signs this exact string (no JSON, no canonicalisation) with the
/// Ed25519 private key whose public half appears in `DownloadRequest.public_key`.
/// Kept here (next to the handler) so the wire format is obvious from a single
/// place; the Dart `script_download_service` must build the identical string.
fn build_download_payload(script_id: &str, timestamp: &str, nonce: &str) -> String {
    format!("download:{script_id}:{timestamp}:{nonce}")
}

/// Authenticated paid-bundle retrieval. `POST /api/v1/scripts/:id/download`.
///
/// The ONLY endpoint that returns the paid bundle. Verifies an Ed25519
/// signature over `download:{script_id}:{timestamp}:{nonce}` with the public
/// key in the body, resolves the owning account via the public-keys table,
/// then gates on a purchase record (or script ownership / free-tier). Free
/// scripts also flow through here so the client has one download path.
#[handler]
pub async fn download_script(
    Path(script_id): Path<String>,
    Json(req): Json<DownloadRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // 1. Resolve account_id from public_key FIRST. Unknown key → 401 (do not
    //    even attempt signature verify against an unbound key).
    let account_id = match state
        .script_service
        .account_repo
        .find_public_key_by_value(&req.public_key)
        .await
    {
        Ok(Some(key)) => key.account_id,
        Ok(None) => {
            tracing::warn!(
                "Download rejected: public key not bound to any account (script={})",
                script_id
            );
            return error_response(StatusCode::UNAUTHORIZED, "Unknown public key");
        }
        Err(e) => {
            tracing::error!(
                "Failed to lookup public key for download (script={}): {}",
                script_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to resolve account for download",
            );
        }
    };

    // 2. Verify Ed25519 signature over the canonical payload.
    let payload = build_download_payload(&script_id, &req.timestamp, &req.nonce);
    if let Err(e) =
        auth::verify_ed25519_signature(&req.signature, payload.as_bytes(), &req.public_key)
    {
        tracing::warn!(
            "Download rejected: signature verification failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(StatusCode::UNAUTHORIZED, "Invalid signature");
    }

    // 2b. Replay prevention (W7-5): the signed `timestamp`+`nonce` MUST be
    //     freshness-checked and single-use, exactly like every account
    //     mutation in `account_service`. A captured signed download is
    //     otherwise replayable verbatim. Mirrors the account_service pattern:
    //     InvalidFormat (bad/out-of-range timestamp) → 400, InvalidSignature
    //     (replayed nonce) → 401.
    let timestamp_unix = match chrono::DateTime::parse_from_rfc3339(&req.timestamp) {
        Ok(dt) => dt.timestamp(),
        Err(e) => {
            tracing::warn!(
                "Download rejected: unparseable timestamp (script={}, account={}): {}",
                script_id,
                account_id,
                e
            );
            return error_response(StatusCode::BAD_REQUEST, "Invalid timestamp format");
        }
    };
    if let Err(e) = auth::validate_replay_prevention(&state.pool, timestamp_unix, &req.nonce).await
    {
        let status = match e {
            auth::AuthError::InvalidFormat(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::UNAUTHORIZED,
        };
        tracing::warn!(
            "Download rejected: replay prevention failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(status, "Replay prevention failed");
    }

    // 3. Load script.
    let script = match state.script_service.get_script(&script_id).await {
        Ok(Some(s)) => s,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to load script for download {}: {}", script_id, e);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to load script for download",
            );
        }
    };

    // 4. Entitlement: free → yes; paid → owner OR purchase record. The owner
    //    and free cases both short-circuit to "entitled" without hitting the
    //    purchases table (clippy recognises this as the same branch body).
    let entitled =
        if script.price <= 0.0 || script.owner_account_id.as_deref() == Some(account_id.as_str()) {
            true
        } else {
            match state
                .purchase_repo
                .exists_for_account_and_script(&account_id, &script_id)
                .await
            {
                Ok(purchased) => purchased,
                Err(e) => {
                    tracing::error!(
                        "Failed to check purchase for download (script={}, account={}): {}",
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

    if !entitled {
        return (
            StatusCode::PAYMENT_REQUIRED,
            Json(serde_json::json!({
                "success": false,
                "error": "Purchase required",
                "data": { "price": script.price }
            })),
        )
            .into_response();
    }

    // 5. Record the signature audit so the `(timestamp, nonce)` pair is
    //    single-use within the 10-minute window — this is the WRITE side of
    //    replay prevention (step 2b was the CHECK side). Security-relevant:
    //    if we cannot record the nonce, we MUST NOT hand over the bundle,
    //    because that request would then be replayable. (Unlike the counter
    //    bump below, this is not best-effort.) Mirrors account_service.
    //
    //    W7-011: the DB UNIQUE constraint on `signature_audit.nonce` closes
    //    the TOCTOU window between the CHECK (step 2b) and this WRITE. A
    //    unique-violation = a concurrent download won the race with the same
    //    nonce → replay → 401 (do NOT release the bundle).
    let audit_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    match auth::classify_audit_write(
        state
            .script_service
            .account_repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account_id),
                action: "download_script",
                payload: &payload,
                signature: &req.signature,
                public_key: &req.public_key,
                timestamp: timestamp_unix,
                nonce: &req.nonce,
                is_admin_action: false,
                now: &now,
            })
            .await,
    ) {
        Ok(auth::AuditOutcome::Ok) => {}
        Ok(auth::AuditOutcome::Replay) => {
            tracing::warn!(
                "Download rejected: nonce UNIQUE constraint fired — concurrent replay \
                 (script={}, account={})",
                script_id,
                account_id
            );
            return error_response(StatusCode::UNAUTHORIZED, "Replay prevention failed");
        }
        Err(e) => {
            tracing::error!(
                "Failed to record download audit — refusing to release bundle (script={}, account={}): {}",
                script_id,
                account_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to record download audit",
            );
        }
    }

    // 6. Bump downloads counter. Best-effort: a counter failure does NOT
    //    block the download — the entitlement decision is the
    //    security-relevant part and already succeeded. (This is the SOLE
    //    write site of the downloads counter — the former unauthenticated
    //    `POST /update-script-stats` endpoint was removed as dead code in
    //    W7-16.)
    if let Err(e) = state.script_service.increment_downloads(&script_id).await {
        tracing::warn!(
            "Download succeeded but failed to bump downloads counter for {}: {}",
            script_id,
            e
        );
    }

    Json(serde_json::json!({
        "success": true,
        "data": {
            "bundle": script.bundle,
            "purchased": true
        }
    }))
    .into_response()
}

// ============================================================================
// Provider-agnostic payment endpoints (Phase K)
// ============================================================================

/// Shared implementation called by both [`payment_config`] and
/// [`payment_config_legacy`]. A plain `async fn` (no `#[handler]`) so the
/// generated handler wrappers can invoke it directly — poem's `#[handler]`
/// macro creates a struct, not a callable plain fn, so we factor the body
/// out.
async fn payment_config_impl(state: &Arc<AppState>) -> Response {
    match state.payment_provider.client_config() {
        Some(cfg) => Json(serde_json::json!({
            "success": true,
            "data": cfg
        }))
        .into_response(),
        None => {
            // Provider exposes no client config (stub, none, or icpay without
            // publishable key). 503 with a GENERIC external message — this
            // endpoint is called by the frontend over an unauthenticated
            // channel, so internal config variable names MUST NOT be echoed
            // back. Detail stays in the server log only.
            tracing::info!(
                "Payment config requested but provider '{}' exposes no client config",
                state.payment_provider.name()
            );
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "Payment provider not configured",
            )
        }
    }
}

/// Provider-agnostic public client config. `GET /api/v1/payments/config`.
///
/// Replaces the ICPay-specific `GET /api/v1/payments/icpay/config` for new
/// clients. Dispatches via [`PaymentProvider::client_config`] so the wire
/// shape is identical regardless of provider (stub → 503; icpay → publishable
/// key + shortcode + apiUrl; none → 503).
///
/// The legacy ICPay route stays mounted (via [`payment_config_legacy`]) when
/// `PAYMENT_PROVIDER=icpay` so existing clients continue to work during the
/// transition.
#[handler]
pub async fn payment_config(Data(state): Data<&Arc<AppState>>) -> Response {
    payment_config_impl(&state).await
}

/// Legacy alias for [`payment_config`] at the ICPay-specific route
/// `GET /api/v1/payments/icpay/config`. Mounted ONLY when
/// `PAYMENT_PROVIDER=icpay` (see `main.rs`) so the route exists precisely
/// when the frontend's old ICPay client SDK expects it. Behaviour is
/// identical to [`payment_config`] — the same `client_config()` call,
/// regardless of the route path.
#[handler]
pub async fn payment_config_legacy(Data(state): Data<&Arc<AppState>>) -> Response {
    payment_config_impl(&state).await
}

/// Provider-agnostic purchase flow. `POST /api/v1/scripts/:id/purchase`.
///
/// The signed canonical payload is
/// `{action:"purchase", id:<script_id>, nonce:<nonce>, ts:<timestamp>}`
/// (mirrors the entitlement endpoint — same `EntitlementRequest` body shape,
/// different action string). The server resolves `account_id` from the
/// verified public key (never trusts client input), loads the script price,
/// and dispatches to [`PaymentProvider::initiate_purchase`].
///
/// Provider outcomes:
/// - **stub**: returns `200 {"success":true,"data":{"intent":{...},
///   "purchased":true}}` — the entitlement row is written immediately.
/// - **icpay**: returns `200 {"success":true,"data":{"intent":{...},
///   "purchased":false,"checkoutUrl":null}}` — the frontend still drives the
///   hosted checkout via its client SDK; the backend records the entitlement
///   when the webhook lands.
/// - **none** (or unrecognised): returns `503` with body
///   `{"error":"payments_disabled","provider":"none"}` (per AGENTS.md "fail
///   fast"; note this is NOT the canonical `{"success":false,...}` shape).
///
/// Public contract: the response shape MUST NOT change after landing.
#[handler]
pub async fn purchase_script(
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
                "Purchase rejected: public key not bound to any account (script={})",
                script_id
            );
            return error_response(StatusCode::UNAUTHORIZED, "Unknown public key");
        }
        Err(e) => {
            tracing::error!(
                "Failed to lookup public key for purchase (script={}): {}",
                script_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to resolve account for purchase",
            );
        }
    };

    // 2. Build the canonical payload and verify the signature. Same shape as
    //    the entitlement endpoint — only the `action` field differs
    //    ("purchase" vs "entitlement"). The frontend
    //    `ScriptSignatureService.signPurchase` builds the identical canonical
    //    bytes.
    let payload = serde_json::json!({
        "action": PURCHASE_ACTION,
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
            "Purchase rejected: signature verification failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(StatusCode::UNAUTHORIZED, "Invalid signature");
    }

    // 3. Replay prevention — same pattern as entitlement / download: the
    //    signed `(timestamp, nonce)` pair MUST be freshness-checked and
    //    single-use so a captured signed purchase cannot be replayed.
    if let Err(e) = auth::validate_replay_prevention(&state.pool, req.timestamp, &req.nonce).await {
        let status = match e {
            auth::AuthError::InvalidFormat(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::UNAUTHORIZED,
        };
        tracing::warn!(
            "Purchase rejected: replay prevention failed (script={}, account={}): {}",
            script_id,
            account_id,
            e
        );
        return error_response(status, "Replay prevention failed");
    }

    // 4. Load script — needed for the price. 404 if absent.
    let script = match state.script_service.get_script(&script_id).await {
        Ok(Some(s)) => s,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Script not found"),
        Err(e) => {
            tracing::error!("Failed to load script for purchase {}: {}", script_id, e);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to load script for purchase",
            );
        }
    };

    // 5. Free scripts do not need to flow through the provider — short-circuit
    //    to "already entitled" so the stub / icpay / none distinction only
    //    applies to actual paid purchases. (`purchased:true` regardless of
    //    provider; no row insert needed because the download gate already
    //    treats price<=0 as entitled.)
    if script.price <= 0.0 {
        // Still record the audit so the nonce is single-use.
        if let Err(resp) = record_purchase_audit(state, &account_id, &script_id, &req, &payload).await {
            return resp;
        }
        return Json(serde_json::json!({
            "success": true,
            "data": {
                "intent": {
                    "id": "free",
                    "status": "completed",
                    "checkoutUrl": null,
                    "provider": state.payment_provider.name(),
                    "usdAmount": 0.0,
                },
                "purchased": true,
            }
        }))
        .into_response();
    }

    // 6. Dispatch to the provider. PaymentError::PaymentsDisabled maps to
    //    503 with the explicit `payments_disabled` body (NOT the canonical
    //    {"success":false,...} shape — the task spec is explicit). Other
    //    PaymentError variants map through their default `as_response()`.
    let intent = match state
        .payment_provider
        .initiate_purchase(&script_id, &account_id, script.price)
        .await
    {
        Ok(intent) => intent,
        Err(PaymentError::PaymentsDisabled(_)) => {
            tracing::warn!(
                "Purchase rejected: payments disabled (provider={}, script={}, account={})",
                state.payment_provider.name(),
                script_id,
                account_id
            );
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(serde_json::json!({
                    "error": "payments_disabled",
                    "provider": state.payment_provider.name(),
                })),
            )
                .into_response();
        }
        Err(e) => {
            tracing::warn!(
                "Purchase failed (provider={}, script={}, account={}): {}",
                state.payment_provider.name(),
                script_id,
                account_id,
                e
            );
            return error_response(e.status(), e.message());
        }
    };

    // 7. Record the signature audit so the `(timestamp, nonce)` pair is
    //    single-use (mirrors entitlement / download). Fail-closed: if the
    //    audit cannot be recorded, the purchase is replayable, so we refuse.
    if let Err(resp) = record_purchase_audit(state, &account_id, &script_id, &req, &payload).await {
        return resp;
    }

    // 8. Surface the intent. `purchased` is `true` when the entitlement is
    //    already granted (stub Completed); `false` when the caller must wait
    //    for an external round-trip (icpay Pending — frontend opens
    //    checkoutUrl if present, else falls back to its client SDK).
    let purchased = intent.status == PurchaseStatus::Completed;
    Json(serde_json::json!({
        "success": true,
        "data": {
            "intent": intent,
            "purchased": purchased,
        }
    }))
    .into_response()
}

/// Shared audit-write helper for the purchase endpoint. Returns `Err(resp)`
/// when the audit fails — the caller returns the response immediately
/// (fail-closed). The canonical payload is canonicalised by
/// `auth::create_canonical_payload` before storage (matches the entitlement
/// endpoint's pattern).
async fn record_purchase_audit(
    state: &Arc<AppState>,
    account_id: &str,
    script_id: &str,
    req: &EntitlementRequest,
    payload: &serde_json::Value,
) -> Result<(), Response> {
    let audit_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    let canonical_payload = auth::create_canonical_payload(payload);
    match auth::classify_audit_write(
        state
            .script_service
            .account_repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(account_id),
                action: PURCHASE_ACTION,
                payload: &canonical_payload,
                signature: &req.signature,
                public_key: &req.author_public_key,
                timestamp: req.timestamp,
                nonce: &req.nonce,
                is_admin_action: false,
                now: &now,
            })
            .await,
    ) {
        Ok(auth::AuditOutcome::Ok) => Ok(()),
        Ok(auth::AuditOutcome::Replay) => {
            tracing::warn!(
                "Purchase rejected: nonce UNIQUE constraint fired — concurrent replay \
                 (script={}, account={})",
                script_id,
                account_id
            );
            Err(error_response(
                StatusCode::UNAUTHORIZED,
                "Replay prevention failed",
            ))
        }
        Err(e) => {
            tracing::error!(
                "Failed to record purchase audit — refusing to complete purchase \
                 (script={}, account={}): {}",
                script_id,
                account_id,
                e
            );
            Err(error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to record purchase audit",
            ))
        }
    }
}

// ============================================================================
// ICPay-specific webhook — mounted ONLY when PAYMENT_PROVIDER=icpay
// ============================================================================

/// ICPay webhook receiver. `POST /api/v1/payments/icpay/webhook`.
///
/// UNAUTHENTICATED — ICPay calls this. Verifies an HMAC-SHA256 over the RAW
/// request body (the exact bytes the sender produced) with the shared
/// `ICPAY_WEBHOOK_SECRET`, then idempotently records the purchase. Both
/// `X-Icpay-Signature` and `Icmpay-Signature` header spellings are accepted
/// (the exact header name is an assumption pending live ICPay docs — see the
/// note in `icpay_payment_provider::verify_webhook`).
///
/// Mounted conditionally in `main.rs` only when `PAYMENT_PROVIDER=icpay`.
/// When the route is hit but the typed ICPay handle is absent (defence in
/// depth — should not happen because the route is unmounted otherwise),
/// returns 503.
#[handler]
pub async fn icpay_webhook(
    req: &Request,
    body: Vec<u8>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let icpay = match &state.icpay_provider {
        Some(p) => p.clone(),
        None => {
            tracing::error!(
                "ICPay webhook received but provider is '{}' (not icpay); the route should be \
                 unmounted — this is a routing misconfiguration.",
                state.payment_provider.name()
            );
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "Payment provider not configured",
            );
        }
    };

    // LOUD misconfig: refuse to verify when the secret is unset. Return 503
    // (service unavailable — "not configured"), consistent with the config
    // endpoint, and a GENERIC external message — the webhook is called by an
    // untrusted external caller (ICPay), so the internal config variable name
    // must NOT be echoed back. The precise reason stays in the log only.
    if !icpay.has_webhook_secret() {
        tracing::error!("ICPay webhook received but ICPAY_WEBHOOK_SECRET is not configured");
        return error_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "Payment provider not configured",
        );
    }

    // Signature header — accept both documented spellings.
    let sig_header = req
        .header("x-icpay-signature")
        .or_else(|| req.header("icmpay-signature"));
    let sig_header = match sig_header {
        Some(h) => h,
        None => {
            tracing::warn!("ICPay webhook rejected: missing signature header");
            return error_response(StatusCode::UNAUTHORIZED, "Missing X-Icpay-Signature header");
        }
    };

    // RAW body bytes — the HMAC was computed over the exact bytes the sender
    // produced, so we use the `Vec<u8>` extractor (NOT `Json`, which would
    // re-serialise and invalidate the signature).
    let event = match icpay.verify_webhook(&body, sig_header) {
        Ok(event) => event,
        Err(e) => {
            if matches!(e, PaymentError::Unauthorized(_)) {
                tracing::warn!("ICPay webhook rejected: bad signature");
            } else {
                tracing::warn!("ICPay webhook rejected: {}", e);
            }
            return error_response(e.status(), e.message());
        }
    };

    tracing::info!(
        "ICPay webhook received: script_id={:?}, account_id={:?}, status={:?}",
        event.metadata.script_id,
        event.metadata.account_id,
        event.status
    );

    let recorded = match icpay.record_purchase_from_webhook(&event).await {
        Ok(recorded) => recorded,
        Err(e) => {
            tracing::error!(
                "ICPay webhook failed to record purchase (script={:?}, account={:?}): {}",
                event.metadata.script_id,
                event.metadata.account_id,
                e
            );
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to record purchase",
            );
        }
    };

    Json(serde_json::json!({
        "success": true,
        "data": { "recorded": recorded }
    }))
    .into_response()
}

// ============================================================================
// Provider-agnostic payment integration — handler-level integration tests
// ============================================================================
//
// These tests exercise the REAL `#[handler]` functions end-to-end via poem's
// `TestClient`, including HTTP status codes and JSON bodies. They cover the
// HIGH-severity fix (paid bundle MUST NOT leak via the public `get_script`),
// the authenticated download / purchase / entitlement endpoints, the generic
// payment config endpoint, and the ICPay webhook (provider-conditional).
// Cryptography is real (a generated Ed25519 keypair signs the payloads); no
// mocking of crypto, per AGENTS.md.

#[cfg(test)]
mod payment_http_tests;
