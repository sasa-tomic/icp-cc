//! Shared signature-gate for account-scoped routes (Wave-7 Phase 2, W7-12..15).
//!
//! Every state-changing route that previously trusted a client-supplied
//! `account_id`/`user_id` now flows through [`verify_signed_account_request`]:
//! resolve the caller's `account_id` SERVER-SIDE from the verified public key,
//! verify an Ed25519 (or secp256k1) signature over a canonical payload, enforce
//! replay prevention, and record the audit (fail-closed). This is the exact
//! pattern proven by `entitlement_check` (W7-2, commit `22e96a6b`), factored out
//! so the vault / passkey / recovery / review gates can never drift from it.
//!
//! ## Why this is the single source of truth
//!
//! `account_id` is a PUBLIC identifier (leaked by `GET /accounts/:username` and
//! `ScriptDetailResponse.owner_account_id`). Trusting it for authorization is
//! an IDOR. The gate instead derives `account_id` from a key the caller proves
//! they own, then binds that resolved id INTO the signed payload — so an
//! attacker who signs a payload naming the victim's `account_id` (with their
//! own key) is rejected: the backend reconstructs the payload with the
//! attacker's resolved `account_id`, and the signature does not verify.

use poem::http::StatusCode;
use sqlx::SqlitePool;

use crate::{
    auth::{self, AuthError},
    repositories::{AccountRepository, SignatureAuditParams},
};

/// The signature + identity fields every signed request carries. Mirrors the
/// [`crate::models::EntitlementRequest`] shape (snake_case on the wire):
/// `{signature, author_public_key, author_principal, timestamp, nonce}`.
pub struct SignedAuthFields<'a> {
    pub signature: &'a str,
    pub author_public_key: &'a str,
    pub author_principal: &'a str,
    /// Unix seconds. Must be within the replay-prevention window (±5 min).
    pub timestamp: i64,
    /// Single-use UUID generated fresh per request by the frontend.
    pub nonce: &'a str,
}

/// A rejection from the signature gate. Handlers convert this into an
/// [`crate::responses::error_response`] verbatim. The detailed failure reason
/// is logged (never leaked to the caller — uniform "Invalid signature" etc.
/// avoids an oracle).
#[derive(Debug)]
pub struct AuthGateRejection {
    pub status: StatusCode,
    pub message: &'static str,
}

/// Verifies a signed account-scoped request and resolves the caller's
/// `account_id` SERVER-SIDE (never trusts a client-supplied identity).
///
/// Steps (mirrors `entitlement_check`):
/// 1. Resolve `account_id` from `find_public_key_by_value` (unknown key → 401).
/// 2. Build the canonical payload via `build_payload(&resolved_account_id)` and
///    verify the Ed25519/secp256k1 signature over it (mismatch → 401).
/// 3. `validate_replay_prevention` — timestamp window + single-use nonce.
/// 4. `record_signature_audit` — fail-closed (an unrecorded request is
///    replayable, so we refuse to proceed).
///
/// `build_payload` receives the resolved `account_id` and returns the canonical
/// JSON the caller signed. Including the resolved `account_id` inside the
/// payload is what binds authorship (see the module-level doc).
pub async fn verify_signed_account_request(
    account_repo: &AccountRepository,
    pool: &SqlitePool,
    action: &'static str,
    auth_fields: &SignedAuthFields<'_>,
    build_payload: impl FnOnce(&str) -> serde_json::Value,
) -> Result<String, AuthGateRejection> {
    // 1. Resolve account_id from the public key (never trust the body).
    let account_id = match account_repo
        .find_public_key_by_value(auth_fields.author_public_key)
        .await
    {
        Ok(Some(key)) => key.account_id,
        Ok(None) => {
            tracing::warn!(
                action,
                "Signature gate: public key not bound to any account"
            );
            return Err(AuthGateRejection {
                status: StatusCode::UNAUTHORIZED,
                message: "Unknown public key",
            });
        }
        Err(e) => {
            tracing::error!(action, "Signature gate: key lookup failed: {e}");
            return Err(AuthGateRejection {
                status: StatusCode::INTERNAL_SERVER_ERROR,
                message: "Failed to resolve account",
            });
        }
    };

    // 2. Build + verify the canonical signature.
    let payload = build_payload(&account_id);
    if let Err(e) = auth::verify_operation_signature(
        Some(auth_fields.signature),
        Some(auth_fields.author_public_key),
        Some(auth_fields.author_principal),
        &payload,
    ) {
        tracing::warn!(
            action,
            account_id = %account_id,
            "Signature gate: verification failed: {e}"
        );
        return Err(AuthGateRejection {
            status: StatusCode::UNAUTHORIZED,
            message: "Invalid signature",
        });
    }

    // 3. Replay prevention (timestamp window + single-use nonce).
    if let Err(e) =
        auth::validate_replay_prevention(pool, auth_fields.timestamp, auth_fields.nonce).await
    {
        let status = match e {
            AuthError::InvalidFormat(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::UNAUTHORIZED,
        };
        tracing::warn!(
            action,
            account_id = %account_id,
            "Signature gate: replay prevention failed: {e}"
        );
        return Err(AuthGateRejection {
            status,
            message: "Replay prevention failed",
        });
    }

    // 4. Record the audit (fail-closed: a replayable request is refused).
    //    W7-011: the DB UNIQUE constraint on `signature_audit.nonce` is the
    //    race-proof source of truth. A unique-violation means a concurrent
    //    request with the same nonce won the TOCTOU race past step 3's
    //    SELECT-COUNT — classify it as a replay (401), not a server fault.
    let audit_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    let canonical_payload = auth::create_canonical_payload(&payload);
    match auth::classify_audit_write(
        account_repo
            .record_signature_audit(SignatureAuditParams {
                audit_id: &audit_id,
                account_id: Some(&account_id),
                action,
                payload: &canonical_payload,
                signature: auth_fields.signature,
                public_key: auth_fields.author_public_key,
                timestamp: auth_fields.timestamp,
                nonce: auth_fields.nonce,
                is_admin_action: false,
                now: &now,
            })
            .await,
    ) {
        Ok(auth::AuditOutcome::Ok) => {}
        Ok(auth::AuditOutcome::Replay) => {
            tracing::warn!(
                action,
                account_id = %account_id,
                "Signature gate: nonce UNIQUE constraint fired (concurrent replay)"
            );
            return Err(AuthGateRejection {
                status: StatusCode::UNAUTHORIZED,
                message: "Replay prevention failed",
            });
        }
        Err(e) => {
            tracing::error!(
                action,
                account_id = %account_id,
                "Signature gate: audit record failed: {e}"
            );
            return Err(AuthGateRejection {
                status: StatusCode::INTERNAL_SERVER_ERROR,
                message: "Failed to record signature audit",
            });
        }
    }

    Ok(account_id)
}
