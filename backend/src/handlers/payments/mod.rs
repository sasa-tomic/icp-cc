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
    models::{AppState, DownloadRequest},
    responses::error_response,
};

// ============================================================================
// ICPay payment integration + paid-script entitlement gate
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
    if let Err(e) =
        auth::validate_replay_prevention(&state.pool, timestamp_unix, &req.nonce).await
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
    let audit_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    if let Err(e) = state
        .script_service
        .account_repo
        .record_signature_audit(crate::repositories::SignatureAuditParams {
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
        .await
    {
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

    // 6. Bump downloads counter (mirrors `update_script_stats`). Best-effort:
    //    a counter failure does NOT block the download — the entitlement
    //    decision is the security-relevant part and already succeeded.
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

/// Public ICPay client config. `GET /api/v1/payments/icpay/config`.
///
/// Returns the browser-safe publishable key + token shortcode + API URL. The
/// secret key never leaves the server. 503 (LOUD) when the publishable key is
/// unset so the client can distinguish "payments not configured" from a
/// transient error.
#[handler]
pub async fn payment_config(Data(state): Data<&Arc<AppState>>) -> Response {
    match state.payment_service.get_publishable_config() {
        Some(cfg) => Json(serde_json::json!({
            "success": true,
            "data": cfg
        }))
        .into_response(),
        None => error_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "ICPAY_PUBLISHABLE_KEY not configured",
        ),
    }
}

/// ICPay webhook receiver. `POST /api/v1/payments/icpay/webhook`.
///
/// UNAUTHENTICATED — ICPay calls this. Verifies an HMAC-SHA256 over the RAW
/// request body (the exact bytes the sender produced) with the shared
/// `ICPAY_WEBHOOK_SECRET`, then idempotently records the purchase. Both
/// `X-Icpay-Signature` and `Icmpay-Signature` header spellings are accepted
/// (the exact header name is an assumption pending live ICPay docs — see the
/// note in `payment_service::verify_webhook`).
#[handler]
pub async fn icpay_webhook(
    req: &Request,
    body: Vec<u8>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // LOUD misconfig: refuse to verify when the secret is unset. Return 503
    // (service unavailable — "not configured"), consistent with the config
    // endpoint, and a GENERIC external message — the webhook is called by an
    // untrusted external caller (ICPay), so the internal config variable name
    // must NOT be echoed back. The precise reason stays in the log only.
    if !state.payment_service.has_webhook_secret() {
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
    let event = match state.payment_service.verify_webhook(&body, sig_header) {
        Ok(event) => event,
        Err(e) => {
            // Variant decides status (single source of truth): Unauthorized
            // for signature mismatch, BadRequest for malformed JSON, Internal
            // for misconfig (replaces the old `.contains("signature")`).
            if matches!(e, crate::services::PaymentError::Unauthorized(_)) {
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

    let recorded = match state
        .payment_service
        .record_purchase_from_webhook(&event)
        .await
    {
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
// ICPay payment integration — handler-level integration tests
// ============================================================================
//
// These tests exercise the REAL `#[handler]` functions end-to-end via poem's
// `TestClient`, including HTTP status codes and JSON bodies. They cover the
// HIGH-severity fix (paid bundle MUST NOT leak via the public `get_script`)
// and the authenticated download / webhook / config endpoints. Cryptography
// is real (a generated Ed25519 keypair signs the download payload); no
// mocking of crypto, per AGENTS.md.

#[cfg(test)]
mod payment_http_tests;
