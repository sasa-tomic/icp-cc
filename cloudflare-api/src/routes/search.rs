use crate::types::*;
use crate::utils::*;
use worker::{console_log, Request, Response, Result};

pub async fn handle_search_scripts_request(req: Request, env: &AppEnv) -> Result<Response> {
    let db = DatabaseService::new(env);

    let query_params = match req.query::<SearchQueryParams>() {
        Ok(params) => params,
        Err(_) => SearchQueryParams::default(),
    };

    let search_params = SearchParams {
        query: query_params.query,
        category: query_params.category,
        canister_id: query_params.canister_id,
        min_rating: query_params.min_rating,
        max_price: query_params.max_price,
        sort_by: query_params.sort_by,
        order: query_params.order,
        limit: query_params.limit,
        offset: query_params.offset,
        is_public: Some(true),
    };

    match db.search_scripts(&search_params).await {
        Ok((scripts, total)) => {
            let response_data = serde_json::json!({
                "scripts": scripts,
                "total": total,
                "hasMore": (search_params.offset.unwrap_or(0) + search_params.limit.unwrap_or(20)) < total
            });
            Ok(JsonResponse::success(response_data, 200))
        }
        Err(e) => {
            console_log!("Failed to search scripts: {:?}", e);
            Ok(JsonResponse::error_with_details("Failed to search scripts", &e.to_string(), 500))
        }
    }
}

pub async fn handle_trending_scripts_request(_req: Request, env: &AppEnv) -> Result<Response> {
    let db = DatabaseService::new(env);

    let search_params = SearchParams {
        query: None,
        category: None,
        canister_id: None,
        min_rating: Some(4.0),
        max_price: None,
        sort_by: Some("downloads".to_string()),
        order: Some("desc".to_string()),
        limit: Some(20),
        offset: Some(0),
        is_public: Some(true),
    };

    match db.search_scripts(&search_params).await {
        Ok((scripts, _total)) => Ok(JsonResponse::success(scripts, 200)),
        Err(e) => {
            console_log!("Failed to get trending scripts: {:?}", e);
            Ok(JsonResponse::error_with_details("Failed to get trending scripts", &e.to_string(), 500))
        }
    }
}

pub async fn handle_featured_scripts_request(_req: Request, env: &AppEnv) -> Result<Response> {
    let db = DatabaseService::new(env);

    let search_params = SearchParams {
        query: None,
        category: None,
        canister_id: None,
        min_rating: Some(4.5),
        max_price: None,
        sort_by: Some("rating".to_string()),
        order: Some("desc".to_string()),
        limit: Some(10),
        offset: Some(0),
        is_public: Some(true),
    };

    match db.search_scripts(&search_params).await {
        Ok((scripts, _total)) => Ok(JsonResponse::success(scripts, 200)),
        Err(e) => {
            console_log!("Failed to get featured scripts: {:?}", e);
            Ok(JsonResponse::error_with_details("Failed to get featured scripts", &e.to_string(), 500))
        }
    }
}

pub async fn handle_compatible_scripts_request(req: Request, env: &AppEnv) -> Result<Response> {
    let db = DatabaseService::new(env);

    let query_params = match req.query::<CompatibleQueryParams>() {
        Ok(params) => params,
        Err(_) => return Ok(JsonResponse::error("canisterId parameter is required", 400)),
    };

    let canister_id = query_params.canister_id;

    let search_params = SearchParams {
        query: None,
        category: None,
        canister_id: Some(canister_id.to_string()),
        min_rating: None,
        max_price: None,
        sort_by: Some("rating".to_string()),
        order: Some("desc".to_string()),
        limit: Some(20),
        offset: Some(0),
        is_public: Some(true),
    };

    match db.search_scripts(&search_params).await {
        Ok((scripts, _total)) => Ok(JsonResponse::success(scripts, 200)),
        Err(e) => {
            console_log!("Failed to get compatible scripts: {:?}", e);
            Ok(JsonResponse::error_with_details("Failed to get compatible scripts", &e.to_string(), 500))
        }
    }
}