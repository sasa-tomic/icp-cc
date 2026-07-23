use std::sync::Arc;

use poem::{
    handler,
    http::StatusCode,
    web::{Data, Json, Path},
    IntoResponse, Response,
};

use crate::{
    auth,
    models::{AppState, DownloadRequest},
    repositories::SignatureAuditParams,
    responses::error_response,
};

/// Canonical signature payload for `POST /api/v1/scripts/:id/download`. The
/// client signs this exact string (no JSON, no canonicalisation) with the
/// Ed25519 private key whose public half appears in `DownloadRequest.public_key`.
/// Kept here (next to the handler) so the wire format is obvious from a single
/// place; the Dart `script_download_service` must build the identical string.
fn build_download_payload(script_id: &str, timestamp: &str, nonce: &str) -> String {
    format!("download:{script_id}:{timestamp}:{nonce}")
}

/// Authenticated bundle retrieval. `POST /api/v1/scripts/:id/download`.
///
/// All scripts are free — this endpoint exists for the download counter +
/// signed-audit trail (replay prevention). Verifies an Ed25519 signature over
/// `download:{script_id}:{timestamp}:{nonce}` with the public key in the body,
/// resolves the owning account via the public-keys table, records the
/// signature audit (single-use nonce), bumps the downloads counter, and
/// returns the bundle.
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

    // 2b. Replay prevention: the signed `timestamp`+`nonce` MUST be
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

    // 4. Record the signature audit so the `(timestamp, nonce)` pair is
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

    // 5. Bump downloads counter. Best-effort: a counter failure does NOT
    //    block the download — the entitlement decision is the
    //    security-relevant part and already succeeded.
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
        }
    }))
    .into_response()
}
