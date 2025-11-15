mod types;
mod utils;
mod routes;

use worker::*;
use utils::*;
use routes::{scripts, search, reviews, validation, stats};
use types::AppEnv;

#[event(fetch)]
async fn fetch(req: Request, env: worker::Env, _ctx: Context) -> Result<Response> {
    console_log!("Request received: {} {}", req.method(), req.path());

    // Convert worker Env to our AppEnv
    let app_env = AppEnv::from(env);

    // Handle CORS preflight requests
    if req.method() == Method::Options {
        return Ok(CorsHandler::handle());
    }

    let url = req.url()?;
    let path = url.path();

    // API Routes
    match path {
        // Scripts endpoints
        "/api/v1/scripts" if req.method() == Method::Get => {
            scripts::handle_scripts_request(req, &app_env).await
        }
        "/api/v1/scripts" if req.method() == Method::Post => {
            scripts::handle_create_script_request(req, &app_env).await
        }

        "/api/v1/scripts/search" => {
            search::handle_search_scripts_request(req, &app_env).await
        }

        "/api/v1/scripts/trending" => {
            search::handle_trending_scripts_request(req, &app_env).await
        }

        "/api/v1/scripts/featured" => {
            search::handle_featured_scripts_request(req, &app_env).await
        }

        "/api/v1/scripts/compatible" => {
            search::handle_compatible_scripts_request(req, &app_env).await
        }

        "/api/v1/marketplace-stats" => {
            stats::handle_marketplace_stats_request(req, &app_env).await
        }

        "/api/v1/update-script-stats" => {
            stats::handle_update_script_stats_request(req, &app_env).await
        }

        "/api/v1/scripts/validate" => {
            validation::handle_script_validation_request(req, &app_env).await
        }

        "/api/v1/scripts/count" => {
            scripts::handle_scripts_count_request(req, &app_env).await
        }

        // Health check
        "/api/v1/health" => {
            let health_response = serde_json::json!({
                "success": true,
                "message": "ICP Marketplace API (Rust) is running",
                "environment": app_env.environment,
                "timestamp": time::OffsetDateTime::now_utc().to_string()
            });
            Ok(JsonResponse::success(health_response, 200))
        }

        // Simple ping endpoint for debugging
        "/api/v1/ping" => {
            let ping_response = serde_json::json!({
                "success": true,
                "message": "pong",
                "timestamp": time::OffsetDateTime::now_utc().to_string()
            });
            Ok(JsonResponse::success(ping_response, 200))
        }

        // Handle dynamic routes
        path if path.starts_with("/api/v1/scripts/") => {
            let path_parts: Vec<&str> = path.split('/').collect();
            if path_parts.len() >= 5 {
                let id = path_parts[4];
                let action = path_parts.get(5).copied();

                if let Some(action) = action {
                    match action {
                        "reviews" => {
                            if req.method() == Method::Post {
                                reviews::handle_create_review_request(req, &app_env, id).await
                            } else {
                                reviews::handle_reviews_request(req, &app_env, id).await
                            }
                        }
                        "publish" => {
                            if req.method() == Method::Post {
                                scripts::handle_publish_script_request(req, &app_env, id).await
                            } else {
                                Ok(JsonResponse::error("Method not allowed", 405))
                            }
                        }
                        _ => {
                            if req.method() == Method::Get {
                                scripts::handle_get_script_request(req, &app_env, id).await
                            } else {
                                Ok(JsonResponse::error("Method not allowed", 405))
                            }
                        }
                    }
                } else if req.method() == Method::Get {
                    scripts::handle_get_script_request(req, &app_env, id).await
                } else if req.method() == Method::Put {
                    scripts::handle_update_script_request(req, &app_env, id).await
                } else if req.method() == Method::Delete {
                    scripts::handle_delete_script_request(req, &app_env, id).await
                } else {
                    Ok(JsonResponse::error("Method not allowed", 405))
                }
            } else {
                Ok(JsonResponse::error("Invalid script ID", 400))
            }
        }

        // Handle category routes
        path if path.starts_with("/api/v1/scripts/category/") => {
            let category = path.strip_prefix("/api/v1/scripts/category/").unwrap_or("");
            scripts::handle_scripts_by_category_request(req, &app_env, category).await
        }

        // Default 404
        _ => Ok(JsonResponse::error("Not Found", 404)),
    }
}

// Utility to configure panic hook for better error messages
#[cfg(feature = "panic_hook")]
fn set_panic_hook() {
    console_error_panic_hook::set_once();
}

#[cfg(not(feature = "panic_hook"))]
fn set_panic_hook() {
    // No panic hook
}