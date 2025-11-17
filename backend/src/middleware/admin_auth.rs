use poem::{http::StatusCode, Endpoint, IntoResponse, Middleware, Request, Response, Result};
use std::env;

/// Admin authentication middleware
/// Validates admin bearer token from Authorization header
pub struct AdminAuth;

impl<E: Endpoint> Middleware<E> for AdminAuth {
    type Output = AdminAuthEndpoint<E>;

    fn transform(&self, ep: E) -> Self::Output {
        AdminAuthEndpoint { ep }
    }
}

pub struct AdminAuthEndpoint<E> {
    ep: E,
}

impl<E: Endpoint> Endpoint for AdminAuthEndpoint<E> {
    type Output = Response;

    async fn call(&self, req: Request) -> Result<Self::Output> {
        // Get admin token from environment
        let admin_token = env::var("ADMIN_TOKEN").unwrap_or_else(|_| {
            tracing::warn!("ADMIN_TOKEN environment variable not set, using default");
            "change-me-in-production".to_string()
        });

        // Get Authorization header
        let auth_header = req
            .headers()
            .get("authorization")
            .and_then(|v| v.to_str().ok());

        match auth_header {
            Some(header) => {
                // Check for Bearer token format
                if let Some(token) = header.strip_prefix("Bearer ") {
                    if token == admin_token {
                        // Token is valid, proceed
                        let resp = self.ep.call(req).await?;
                        Ok(resp.into_response())
                    } else {
                        // Invalid token
                        tracing::warn!("Admin authentication failed: invalid token");
                        Ok(Response::builder().status(StatusCode::UNAUTHORIZED).body(
                            serde_json::json!({
                                "success": false,
                                "error": "Invalid admin credentials"
                            })
                            .to_string(),
                        ))
                    }
                } else {
                    // Invalid format
                    tracing::warn!("Admin authentication failed: invalid header format");
                    Ok(Response::builder().status(StatusCode::UNAUTHORIZED).body(
                        serde_json::json!({
                            "success": false,
                            "error": "Invalid authorization header format. Use: Bearer <token>"
                        })
                        .to_string(),
                    ))
                }
            }
            None => {
                // Missing header
                tracing::warn!("Admin authentication failed: missing authorization header");
                Ok(Response::builder().status(StatusCode::UNAUTHORIZED).body(
                    serde_json::json!({
                        "success": false,
                        "error": "Admin authentication required"
                    })
                    .to_string(),
                ))
            }
        }
    }
}
