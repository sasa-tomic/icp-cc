use poem::{http::StatusCode, Response};

use crate::auth::verify_operation_signature;
use crate::responses::error_response;

/// Trait for requests that contain authentication information
pub trait AuthenticatedRequest {
    fn signature(&self) -> Option<&str>;
    fn author_principal(&self) -> Option<&str>;
    fn author_public_key(&self) -> Option<&str>;
}

/// Validates and verifies authentication for a request
///
/// This combines all authentication checks:
/// 1. Validates signature field exists
/// 2. Validates credentials are provided
/// 3. Verifies cryptographic signature against payload
pub fn verify_request_auth<F>(
    req: &dyn AuthenticatedRequest,
    operation: &str,
    build_payload: F,
) -> Result<(), Box<Response>>
where
    F: FnOnce() -> Result<serde_json::Value, Box<Response>>,
{
    // 1. Validate signature exists
    if req.signature().is_none() {
        tracing::warn!("{} rejected: missing signature", operation);
        return Err(Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            &format!("{} requires authentication signature", operation),
        )));
    }

    // 2. Validate credentials
    if req.author_principal().is_none() {
        tracing::warn!("{} rejected: missing principal", operation);
        return Err(Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for authentication",
        )));
    }

    // 3. Build payload and verify cryptographic signature
    let payload = build_payload()?;
    verify_operation_signature(
        req.signature(),
        req.author_public_key(),
        req.author_principal(),
        &payload,
    )
    .map_err(|e| {
        tracing::warn!("{} rejected: {}", operation, e);
        Box::new(error_response(StatusCode::UNAUTHORIZED, &e.to_string()))
    })
}
