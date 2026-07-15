use std::sync::Arc;

use poem::{
    error::ResponseError,
    handler,
    http::StatusCode,
    web::{Data, Json, Path, RealIp},
    IntoResponse, Response,
};

use crate::{
    models::AppState,
    responses::error_response,
    signature_gate::{verify_signed_account_request, SignedAuthFields},
};

// ============================================================================
// Recovery-code handlers
// ============================================================================
//
// ## W7-14 — generate is signature-gated; verify stays open but rate-limited
//
// `POST /recovery/generate` mints+returns PLAINTEXT recovery codes. It is now
// signature-gated: the caller proves ownership of an account keypair and the
// server resolves account_id SERVER-SIDE (never the request body). This closes
// the exploit where anyone could mint fresh codes for ANY account (wiping the
// victim's real codes → lockout) and receive the plaintext (W7-005).
//
// `POST /recovery/verify` STAYS OPEN — a locked-out user has no keypair by
// definition (that's WHY they need recovery). BUT it is now rate-limited per
// (account_id, source IP): after 5 failed codes in 15 minutes → 429. The codes
// are Argon2id-hashed (each guess is expensive); this adds the missing
// per-caller brute-force throttle (W7-007).

/// Single source of truth for the signed recovery-generate action name. The
/// frontend `PasskeyService` mirrors this EXACT string.
const RECOVERY_GENERATE_ACTION: &str = "recovery:generate";

#[derive(Debug, serde::Deserialize)]
struct RecoveryGenerateRequest {
    // account_id is resolved SERVER-SIDE from the signature (never trusted
    // from the body); serde ignores any client-supplied value.
    // --- auth fields ---
    signature: String,
    author_public_key: String,
    author_principal: String,
    timestamp: i64,
    nonce: String,
}

#[handler]
pub async fn recovery_generate(
    Json(req): Json<RecoveryGenerateRequest>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let account_repo = &state.script_service.account_repo;
    let account_id = match verify_signed_account_request(
        account_repo,
        &state.pool,
        RECOVERY_GENERATE_ACTION,
        &SignedAuthFields {
            signature: &req.signature,
            author_public_key: &req.author_public_key,
            author_principal: &req.author_principal,
            timestamp: req.timestamp,
            nonce: &req.nonce,
        },
        |resolved| {
            serde_json::json!({
                "action": RECOVERY_GENERATE_ACTION,
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

    match state
        .passkey_service
        .generate_recovery_codes_for_account(&account_id)
        .await
    {
        Ok(result) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "success": true,
                "data": result
            })),
        )
            .into_response(),
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[derive(Debug, serde::Deserialize)]
struct RecoveryVerifyRequest {
    account_id: String,
    code: String,
}

#[handler]
pub async fn recovery_verify(
    Json(req): Json<RecoveryVerifyRequest>,
    Data(state): Data<&Arc<AppState>>,
    RealIp(ip): RealIp,
) -> Response {
    // W7-14: per-(account_id, IP) brute-force throttle. A locked-out user has
    // no keypair, so this endpoint cannot require a signature — but the
    // Argon2id-hashed codes plus this rate-limit bound the online oracle.
    let ip_str = ip
        .map(|addr| addr.to_string())
        .unwrap_or_else(|| "unknown".to_string());
    let key = format!("{}:{}", req.account_id, ip_str);
    if !state.recovery_rate_limiter.is_allowed(&key) {
        tracing::warn!(
            account_id = %req.account_id,
            ip = %ip_str,
            "Recovery verify rate-limited (too many failed attempts)"
        );
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "Too many failed recovery attempts. Try again later.",
        );
    }

    match state
        .passkey_service
        .verify_recovery_code_for_account(&req.account_id, &req.code)
        .await
    {
        Ok(true) => {
            // A success clears the failure history so the user isn't left near
            // the limit after eventually typing the right code.
            state.recovery_rate_limiter.reset(&key);
            Json(serde_json::json!({
                "success": true,
                "data": { "valid": true }
            }))
            .into_response()
        }
        Ok(false) => {
            state.recovery_rate_limiter.record_failure(&key);
            Json(serde_json::json!({
                "success": true,
                "data": { "valid": false }
            }))
            .into_response()
        }
        Err(e) => error_response(e.status(), e.message()),
    }
}

#[handler]
pub async fn recovery_status(
    Path(account_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    // Low-sensitivity (returns only a count). Left open — an attacker learning
    // how many codes remain is minor info, and this is a GET keyed by a public
    // account id.
    match state
        .passkey_service
        .get_recovery_code_status(&account_id)
        .await
    {
        Ok(remaining) => Json(serde_json::json!({
            "success": true,
            "data": { "remaining_codes": remaining }
        }))
        .into_response(),
        Err(e) => error_response(e.status(), e.message()),
    }
}
