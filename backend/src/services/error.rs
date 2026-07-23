//! Typed service error enums (TD-2).
//!
//! Replaces the prior `Result<_, String>` contract between services and
//! handlers, where handlers decided the HTTP status by **substring-matching
//! the service's English error string** (e.g. `if msg.contains("not found")`).
//! That heuristic silently degraded the status code whenever a message was
//! reworded, capitalised differently, or translated. The robust technique is
//! a typed error enum: the service emits a variant, the handler reads the
//! variant — the message can change freely without affecting the status.
//!
//! ## Single source of truth
//!
//! The variant → `StatusCode` mapping lives in **exactly one place**: the
//! [`poem::error::ResponseError::status`] impl on each enum. Nowhere else in
//! the codebase maps a service error to a status. Handlers either call
//! `err.status()` / `err.as_response()` or pattern-match on the variant.
//!
//! ## Wire-shape preservation
//!
//! Each variant carries the human-readable message verbatim — the JSON
//! response body (`{"success":false,"error":"<message>"}`) is byte-identical
//! to the prior string-based responses for every code path that did not
//! change status. The few paths whose status changed (made *more* correct)
//! are flagged in the TD-2 commit message and the plan's report.
//!
//! ## Per-domain enums
//!
//! Distinct types per service (`AccountError` vs `ScriptError` vs ...) keep
//! the type system honest: an account handler can never accidentally catch a
//! script error. The variants overlap (most need `NotFound`, `BadRequest`,
//! `Internal`, …) so a macro generates the boilerplate. Each enum only
//! declares the variants its service actually emits.

use poem::{error::ResponseError, http::StatusCode, web::Json, IntoResponse, Response};
use serde_json::json;

/// Builds the canonical wire-shape error response:
/// `{"success":false,"error":"<message>"}` with the given status. This is the
/// SINGLE place that constructs the JSON error body — every service error
/// flows through it via [`ResponseError::as_response`].
fn error_response(status: StatusCode, message: &str) -> Response {
    (status, Json(json!({ "success": false, "error": message }))).into_response()
}

/// Defines a typed service error enum.
///
/// Each variant carries a `String` message (the human-readable text that
/// round-trips into the JSON response body unchanged) and maps to exactly one
/// `StatusCode`. Generates:
/// - the enum itself (with `#[error("{0}")]` so `Display` returns the message),
/// - a `.message()` accessor,
/// - a `ResponseError` impl whose `as_response` produces the canonical
///   `{"success":false,"error":"…"}` body (byte-identical to the legacy
///   `responses::error_response` shape).
macro_rules! service_error {
    (
        $(#[$meta:meta])*
        $name:ident {
            $($variant:ident => $status:ident),+ $(,)?
        }
    ) => {
        $(#[$meta])*
        #[derive(Debug, thiserror::Error)]
        pub enum $name {
            $(
                /// Human-readable message; preserved verbatim in the JSON
                /// response body. Wrap inner-cause text at the construction
                /// site if you need to preserve a legacy message format.
                #[error("{0}")]
                $variant(String),
            )+
        }

        impl $name {
            /// The human-readable message carried by this error. Round-trips
            /// into the `error` field of the JSON response body unchanged.
            pub fn message(&self) -> &str {
                match self {
                    $( $name::$variant(m) => m, )+
                }
            }
        }

        impl ResponseError for $name {
            /// The single source of truth for variant → HTTP status.
            fn status(&self) -> StatusCode {
                match self {
                    $( $name::$variant(_) => StatusCode::$status, )+
                }
            }

            /// Renders the canonical `{"success":false,"error":"<message>"}`
            /// body with the variant's status. This overrides poem's default
            /// plain-text error body so the wire shape matches the legacy
            /// `responses::error_response` exactly.
            fn as_response(&self) -> Response
            where
                Self: std::error::Error + Send + Sync + 'static,
            {
                error_response(self.status(), self.message())
            }
        }
    };
}

service_error! {
    /// Errors emitted by [`super::AccountService`] (account/profile/key
    /// operations, including the admin key-management paths). Each variant
    /// maps to exactly one HTTP status.
    AccountError {
        NotFound => NOT_FOUND,
        Conflict => CONFLICT,
        BadRequest => BAD_REQUEST,
        Unauthorized => UNAUTHORIZED,
        Internal => INTERNAL_SERVER_ERROR,
    }
}

service_error! {
    /// Errors emitted by [`super::ScriptService`] for the handful of methods
    /// whose errors a handler maps to a status (notably `create_script`).
    ScriptError {
        NotFound => NOT_FOUND,
        Forbidden => FORBIDDEN,
        Conflict => CONFLICT,
        BadRequest => BAD_REQUEST,
        Unauthorized => UNAUTHORIZED,
        Internal => INTERNAL_SERVER_ERROR,
    }
}

service_error! {
    /// Errors emitted by [`super::ReviewService`] for `create_review`.
    ReviewError {
        NotFound => NOT_FOUND,
        Conflict => CONFLICT,
        BadRequest => BAD_REQUEST,
        Internal => INTERNAL_SERVER_ERROR,
    }
}

service_error! {
    /// Errors emitted by [`super::PasskeyService`] (passkey registration /
    /// authentication, vault opaque-blob store, recovery codes). The vault
    /// and passkey-delete paths are status-mapped at the handler; the other
    /// paths had fixed handler statuses that the variants now reproduce.
    PasskeyError {
        NotFound => NOT_FOUND,
        Conflict => CONFLICT,
        BadRequest => BAD_REQUEST,
        Unauthorized => UNAUTHORIZED,
        Internal => INTERNAL_SERVER_ERROR,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `ResponseError::as_response` is the single source of truth for the
    /// wire body. Asserting on the status + the JSON shape together proves
    /// variant → status AND that the message round-trips verbatim.
    async fn assert_wire(
        err: impl ResponseError + std::error::Error + Send + Sync + 'static,
        expected_status: StatusCode,
        expected_msg: &str,
    ) {
        assert_eq!(err.status(), expected_status, "variant → status mismatch");
        let resp = err.as_response();
        assert_eq!(resp.status(), expected_status);
        let body = resp
            .into_body()
            .into_json::<serde_json::Value>()
            .await
            .unwrap();
        assert_eq!(
            body["success"],
            serde_json::Value::Bool(false),
            "success flag"
        );
        assert_eq!(body["error"], expected_msg, "error message round-trip");
    }

    // ---- AccountError: every variant → its status + message round-trip ----

    #[tokio::test]
    async fn account_not_found_maps_404() {
        assert_wire(
            AccountError::NotFound("Account not found".into()),
            StatusCode::NOT_FOUND,
            "Account not found",
        )
        .await;
    }

    #[tokio::test]
    async fn account_conflict_maps_409() {
        assert_wire(
            AccountError::Conflict("Username 'x' already exists".into()),
            StatusCode::CONFLICT,
            "Username 'x' already exists",
        )
        .await;
    }

    #[tokio::test]
    async fn account_bad_request_maps_400() {
        assert_wire(
            AccountError::BadRequest("Invalid username: too short".into()),
            StatusCode::BAD_REQUEST,
            "Invalid username: too short",
        )
        .await;
    }

    #[tokio::test]
    async fn account_unauthorized_maps_401() {
        assert_wire(
            AccountError::Unauthorized("Signature verification failed: …".into()),
            StatusCode::UNAUTHORIZED,
            "Signature verification failed: …",
        )
        .await;
    }

    #[tokio::test]
    async fn account_internal_maps_500() {
        assert_wire(
            AccountError::Internal("Database error: …".into()),
            StatusCode::INTERNAL_SERVER_ERROR,
            "Database error: …",
        )
        .await;
    }

    // ---- ScriptError ----

    #[tokio::test]
    async fn script_forbidden_maps_403() {
        assert_wire(
            ScriptError::Forbidden("Slug 'x' is owned by another account".into()),
            StatusCode::FORBIDDEN,
            "Slug 'x' is owned by another account",
        )
        .await;
    }

    #[tokio::test]
    async fn script_internal_maps_500() {
        assert_wire(
            ScriptError::Internal("Failed to create script: …".into()),
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to create script: …",
        )
        .await;
    }

    // ---- ReviewError: covers the three distinct create_review failure
    // statuses (404 / 409 / 400) the handler used to substring-match. ----

    #[tokio::test]
    async fn review_not_found_maps_404() {
        assert_wire(
            ReviewError::NotFound("Script not found".into()),
            StatusCode::NOT_FOUND,
            "Script not found",
        )
        .await;
    }

    #[tokio::test]
    async fn review_conflict_maps_409() {
        assert_wire(
            ReviewError::Conflict("User has already reviewed this script".into()),
            StatusCode::CONFLICT,
            "User has already reviewed this script",
        )
        .await;
    }

    #[tokio::test]
    async fn review_bad_request_maps_400() {
        assert_wire(
            ReviewError::BadRequest("Rating must be between 1 and 5".into()),
            StatusCode::BAD_REQUEST,
            "Rating must be between 1 and 5",
        )
        .await;
    }

    // ---- PasskeyError: vault + passkey-delete paths. ----

    #[tokio::test]
    async fn passkey_not_found_maps_404() {
        assert_wire(
            PasskeyError::NotFound("Vault not found".into()),
            StatusCode::NOT_FOUND,
            "Vault not found",
        )
        .await;
    }

    #[tokio::test]
    async fn passkey_bad_request_maps_400() {
        assert_wire(
            PasskeyError::BadRequest("Cannot delete last passkey".into()),
            StatusCode::BAD_REQUEST,
            "Cannot delete last passkey",
        )
        .await;
    }

    #[tokio::test]
    async fn passkey_unauthorized_maps_401() {
        assert_wire(
            PasskeyError::Unauthorized("WebAuthn verification failed".into()),
            StatusCode::UNAUTHORIZED,
            "WebAuthn verification failed",
        )
        .await;
    }

    /// The `.message()` accessor returns the inner text byte-for-byte (no
    /// prefix, no formatting) — handlers log it and it round-trips into JSON.
    #[test]
    fn message_accessor_returns_inner_text_verbatim() {
        let err = AccountError::Conflict("max keys reached".to_string());
        assert_eq!(err.message(), "max keys reached");
        assert_eq!(err.to_string(), "max keys reached");
    }

    /// The variant decides the status — even if two variants happen to carry
    /// the same message text, their statuses differ. This is the core
    /// invariant the typed enum enforces over the old string heuristic.
    #[test]
    fn same_message_different_variant_yields_different_status() {
        let msg = "x";
        assert_ne!(
            AccountError::NotFound(msg.into()).status(),
            AccountError::Conflict(msg.into()).status(),
        );
        assert_ne!(
            AccountError::BadRequest(msg.into()).status(),
            AccountError::Unauthorized(msg.into()).status(),
        );
    }
}
