use crate::types::*;
use crate::utils::*;
use worker::{console_log, Date, Request, Response, Result};

pub async fn handle_scripts_request(req: Request, env: &AppEnv) -> Result<Response> {
    let url = req.url()?;
    let db = DatabaseService::new(env);

    match req.method() {
        Method::Get => {
            let limit = url.search_params().get("limit")
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(20);
            let offset = url.search_params().get("offset")
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(0);
            let is_public = url.search_params().get("public")
                .and_then(|s| s.parse::<bool>().ok())
                .unwrap_or(true);

            let search_params = SearchParams {
                query: None,
                category: None,
                canister_id: None,
                min_rating: None,
                max_price: None,
                sort_by: Some("created_at".to_string()),
                order: Some("desc".to_string()),
                limit: Some(limit),
                offset: Some(offset),
                is_public: Some(is_public),
            };

            match db.search_scripts(&search_params).await {
                Ok((scripts, total)) => {
                    let response_data = serde_json::json!({
                        "scripts": scripts,
                        "total": total,
                        "has_more": offset + limit < total
                    });
                    Ok(JsonResponse::success(response_data, 200))
                }
                Err(e) => {
                    console_log!("Failed to get scripts: {:?}", e);
                    Ok(JsonResponse::error_with_details("Failed to get scripts", &e.to_string(), 500))
                }
            }
        }
        _ => Ok(JsonResponse::error("Method not allowed", 405)),
    }
}

pub async fn handle_create_script_request(req: Request, env: &AppEnv) -> Result<Response> {
    let db = DatabaseService::new(env);

    // Parse request body
    let body = req.json::<CreateScriptRequest>().await?;

    // Validate required fields
    if body.title.is_empty() || body.description.is_empty() || body.category.is_empty()
        || body.lua_source.is_empty() || body.author_name.is_empty() {
        return Ok(JsonResponse::error(
            "Missing required fields: title, description, category, lua_source, author_name",
            400,
        ));
    }

    let now = time::OffsetDateTime::now_utc();
    let version = body.version.as_deref().unwrap_or("1.0.0");

    // Generate unique script ID
    let script_id = DatabaseService::generate_script_id(
        &body.title,
        &body.description,
        &body.category,
        &body.lua_source,
        &body.author_name,
        version,
        &body.timestamp.to_string(),
    ).await?;

    // Create signature payload
    let signature_payload = SignaturePayload {
        action: "upload".to_string(),
        script_id: Some(script_id.clone()),
        title: Some(body.title.clone()),
        description: Some(body.description.clone()),
        category: Some(body.category.clone()),
        lua_source: Some(body.lua_source.clone()),
        version: Some(version.to_string()),
        tags: body.tags.clone(),
        compatibility: body.compatibility.clone(),
        author_principal: body.author_principal.clone(),
        timestamp: body.timestamp,
    };

    // Verify signature
    match SignatureEnforcement::enforce_signature_verification(
        env,
        &body.signature,
        &signature_payload,
        &body.author_public_key,
    ).await {
        Ok(true) => {
            // Signature is valid, proceed with script creation
            let database = db.get_database();

            // Convert tags and other fields to JSON strings
            let tags_json = serde_json::to_string(&body.tags.unwrap_or_default()).unwrap_or_default();
            let canister_ids_json = serde_json::to_string(&body.canister_ids.unwrap_or_default()).unwrap_or_default();
            let screenshots_json = serde_json::to_string(&body.screenshots.unwrap_or_default()).unwrap_or_default();

            let query = r#"
                INSERT INTO scripts (
                    id, title, description, category, tags, lua_source, author_name, author_id,
                    author_principal, author_public_key, upload_signature, canister_ids, icon_url,
                    screenshots, version, compatibility, price, is_public, downloads, rating,
                    review_count, created_at, updated_at
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23)
            "#;

            match database.prepare(query)
                .bind(&[
                    script_id.clone().into(),
                    body.title.clone().into(),
                    body.description.clone().into(),
                    body.category.clone().into(),
                    tags_json.into(),
                    body.lua_source.clone().into(),
                    body.author_name.clone().into(),
                    "anonymous".into(), // Would come from authentication in real app
                    body.author_principal.clone().into(),
                    body.author_public_key.clone().into(),
                    body.signature.clone().into(),
                    canister_ids_json.into(),
                    body.icon_url.unwrap_or_default().into(),
                    screenshots_json.into(),
                    version.to_string().into(),
                    body.compatibility.unwrap_or_default().into(),
                    body.price.unwrap_or(0.0).into(),
                    body.is_public.unwrap_or(true).into(),
                    0.into(), // downloads
                    0.into(), // rating
                    0.into(), // review_count
                    now.to_string().into(),
                    now.to_string().into(),
                ])
                .run()
                .await
            {
                Ok(_) => {
                    console_log!("Script created successfully: scriptId={}, title={}, isPublic={}",
                                script_id, body.title, body.is_public.unwrap_or(true));

                    // Fetch the created script with details
                    match db.get_script_with_details(&script_id, true).await {
                        Ok(Some(script)) => Ok(JsonResponse::success(script, 201)),
                        Ok(None) => Ok(JsonResponse::error("Failed to retrieve created script", 500)),
                        Err(e) => Ok(JsonResponse::error_with_details("Failed to retrieve created script", &e.to_string(), 500)),
                    }
                }
                Err(e) => {
                    console_log!("Failed to create script: {:?}", e);
                    Ok(JsonResponse::error_with_details("Failed to create script", &e.to_string(), 500))
                }
            }
        }
        Ok(false) | Err(_) => {
            Ok(SignatureEnforcement::create_signature_error_response())
        }
    }
}

pub async fn handle_get_script_request(req: Request, env: &Env, script_id: &str) -> Result<Response> {
    if script_id.is_empty() {
        return Ok(JsonResponse::error("Script ID is required", 400));
    }

    let db = DatabaseService::new(env);
    let url = req.url()?;
    let include_private = url.search_params().get("includePrivate")
        .and_then(|s| s.parse::<bool>().ok())
        .unwrap_or(false);

    match db.get_script_with_details(script_id, include_private).await {
        Ok(Some(script)) => Ok(JsonResponse::success(script, 200)),
        Ok(None) => Ok(JsonResponse::error("Script not found", 404)),
        Err(e) => Ok(JsonResponse::error_with_details("Failed to get script", &e.to_string(), 500)),
    }
}

pub async fn handle_update_script_request(req: Request, env: &Env, script_id: &str) -> Result<Response> {
    if script_id.is_empty() {
        return Ok(JsonResponse::error("Script ID is required", 400));
    }

    let db = DatabaseService::new(env);
    let database = db.get_database();
    let update_data = req.json::<UpdateScriptRequest>().await?;

    // Get the existing script to verify ownership
    match database.prepare("SELECT author_principal, author_public_key FROM scripts WHERE id = ?1")
        .bind(&[script_id.into()])
        .first::<serde_json::Value>()
        .await
    {
        Ok(Some(existing_script)) => {
            let existing_principal = existing_script["author_principal"]
                .as_str()
                .ok_or_else(|| worker::Error::JsError("No author principal found".to_string()))?;
            let existing_public_key = existing_script["author_public_key"]
                .as_str()
                .ok_or_else(|| worker::Error::JsError("No public key found".to_string()))?;

            // Verify that the author_principal matches the existing script's author
            if update_data.author_principal != existing_principal {
                return Ok(JsonResponse::error("Author principal does not match script author", 403));
            }

            // Create signature payload for update
            let signature_payload = SignaturePayload {
                action: "update".to_string(),
                script_id: Some(script_id.to_string()),
                title: update_data.title.clone(),
                description: update_data.description.clone(),
                category: update_data.category.clone(),
                lua_source: update_data.lua_source.clone(),
                version: update_data.version.clone(),
                tags: update_data.tags.clone(),
                compatibility: update_data.compatibility.clone(),
                author_principal: update_data.author_principal.clone(),
                timestamp: update_data.timestamp,
            };

            // Verify signature
            match SignatureEnforcement::enforce_signature_verification(
                env,
                &update_data.signature,
                &signature_payload,
                existing_public_key,
            ).await {
                Ok(true) => {
                    // Build dynamic update query
                    let mut update_fields = Vec::new();
                    let mut bindings = Vec::new();

                    if let Some(title) = &update_data.title {
                        update_fields.push("title = ?");
                        bindings.push(title.clone().into());
                    }
                    if let Some(description) = &update_data.description {
                        update_fields.push("description = ?");
                        bindings.push(description.clone().into());
                    }
                    if let Some(category) = &update_data.category {
                        update_fields.push("category = ?");
                        bindings.push(category.clone().into());
                    }
                    if let Some(lua_source) = &update_data.lua_source {
                        update_fields.push("lua_source = ?");
                        bindings.push(lua_source.clone().into());
                    }
                    if let Some(version) = &update_data.version {
                        update_fields.push("version = ?");
                        bindings.push(version.clone().into());
                    }
                    if let Some(compatibility) = &update_data.compatibility {
                        update_fields.push("compatibility = ?");
                        bindings.push(compatibility.clone().into());
                    }
                    if let Some(price) = update_data.price {
                        update_fields.push("price = ?");
                        bindings.push(price.into());
                    }
                    if let Some(is_public) = update_data.is_public {
                        update_fields.push("is_public = ?");
                        bindings.push((is_public as i32).into());
                    }

                    // Handle JSON fields
                    if let Some(tags) = &update_data.tags {
                        update_fields.push("tags = ?");
                        bindings.push(serde_json::to_string(tags).unwrap_or_default().into());
                    }
                    if let Some(canister_ids) = &update_data.canister_ids {
                        update_fields.push("canister_ids = ?");
                        bindings.push(serde_json::to_string(canister_ids).unwrap_or_default().into());
                    }
                    if let Some(screenshots) = &update_data.screenshots {
                        update_fields.push("screenshots = ?");
                        bindings.push(serde_json::to_string(screenshots).unwrap_or_default().into());
                    }

                    // Add timestamp and script ID
                    let now = time::OffsetDateTime::now_utc();
                    update_fields.push("updated_at = ?");
                    bindings.push(now.to_string().into());
                    bindings.push(script_id.into());

                    let update_query = format!("UPDATE scripts SET {} WHERE id = ?", update_fields.join(", "));

                    match database.prepare(&update_query)
                        .bind(&bindings)
                        .run()
                        .await
                    {
                        Ok(_) => {
                            // Fetch the updated script
                            match db.get_script_with_details(script_id, true).await {
                                Ok(Some(script)) => Ok(JsonResponse::success(script, 200)),
                                Ok(None) => Ok(JsonResponse::error("Script not found after update", 404)),
                                Err(e) => Ok(JsonResponse::error_with_details("Failed to retrieve updated script", &e.to_string(), 500)),
                            }
                        }
                        Err(e) => {
                            console_log!("Failed to update script: {:?}", e);
                            Ok(JsonResponse::error_with_details("Failed to update script", &e.to_string(), 500))
                        }
                    }
                }
                Ok(false) | Err(_) => {
                    Ok(SignatureEnforcement::create_signature_error_response())
                }
            }
        }
        Ok(None) => Ok(JsonResponse::error("Script not found", 404)),
        Err(e) => Ok(JsonResponse::error_with_details("Failed to get existing script", &e.to_string(), 500)),
    }
}

pub async fn handle_delete_script_request(req: Request, env: &Env, script_id: &str) -> Result<Response> {
    if script_id.is_empty() {
        return Ok(JsonResponse::error("Script ID is required", 400));
    }

    let db = DatabaseService::new(env);
    let database = db.get_database();
    let delete_data = req.json::<DeleteScriptRequest>().await?;

    // Get the existing script to verify ownership
    match database.prepare("SELECT author_principal, author_public_key FROM scripts WHERE id = ?1")
        .bind(&[script_id.into()])
        .first::<serde_json::Value>()
        .await
    {
        Ok(Some(existing_script)) => {
            let existing_principal = existing_script["author_principal"]
                .as_str()
                .ok_or_else(|| worker::Error::JsError("No author principal found".to_string()))?;
            let existing_public_key = existing_script["author_public_key"]
                .as_str()
                .ok_or_else(|| worker::Error::JsError("No public key found".to_string()))?;

            // Verify that the author_principal matches the existing script's author
            if delete_data.author_principal != existing_principal {
                return Ok(JsonResponse::error("Author principal does not match script author", 403));
            }

            // Create signature payload for delete
            let signature_payload = SignaturePayload {
                action: "delete".to_string(),
                script_id: Some(script_id.to_string()),
                title: None,
                description: None,
                category: None,
                lua_source: None,
                version: None,
                tags: None,
                compatibility: None,
                author_principal: delete_data.author_principal.clone(),
                timestamp: delete_data.timestamp,
            };

            // Verify signature
            match SignatureEnforcement::enforce_signature_verification(
                env,
                &delete_data.signature,
                &signature_payload,
                existing_public_key,
            ).await {
                Ok(true) => {
                    match database.prepare("DELETE FROM scripts WHERE id = ?1")
                        .bind(&[script_id.into()])
                        .run()
                        .await
                    {
                        Ok(result) => {
                            if result.meta().changes.unwrap_or(0) > 0 {
                                Ok(JsonResponse::success(serde_json::json!({
                                    "message": "Script deleted successfully"
                                }), 200))
                            } else {
                                Ok(JsonResponse::error("Script not found", 404))
                            }
                        }
                        Err(e) => {
                            console_log!("Failed to delete script: {:?}", e);
                            Ok(JsonResponse::error_with_details("Failed to delete script", &e.to_string(), 500))
                        }
                    }
                }
                Ok(false) | Err(_) => {
                    Ok(SignatureEnforcement::create_signature_error_response())
                }
            }
        }
        Ok(None) => Ok(JsonResponse::error("Script not found", 404)),
        Err(e) => Ok(JsonResponse::error_with_details("Failed to get existing script", &e.to_string(), 500)),
    }
}

pub async fn handle_publish_script_request(req: Request, env: &Env, script_id: &str) -> Result<Response> {
    if req.method() != Method::Post {
        return Ok(JsonResponse::error("Method not allowed", 405));
    }

    if script_id.is_empty() {
        return Ok(JsonResponse::error("Script ID is required", 400));
    }

    let db = DatabaseService::new(env);
    let database = db.get_database();

    // Check if script exists
    match database.prepare("SELECT id FROM scripts WHERE id = ?1")
        .bind(&[script_id.into()])
        .first::<serde_json::Value>()
        .await
    {
        Ok(Some(_)) => {
            let now = time::OffsetDateTime::now_utc();

            match database.prepare("UPDATE scripts SET is_public = 1, updated_at = ?1 WHERE id = ?2")
                .bind(&[now.to_string().into(), script_id.into()])
                .run()
                .await
            {
                Ok(result) => {
                    if result.meta().changes.unwrap_or(0) > 0 {
                        // Fetch the updated script
                        match db.get_script_with_details(script_id, true).await {
                            Ok(Some(script)) => Ok(JsonResponse::success(script, 200)),
                            Ok(None) => Ok(JsonResponse::error("Script not found after publishing", 404)),
                            Err(e) => Ok(JsonResponse::error_with_details("Failed to retrieve published script", &e.to_string(), 500)),
                        }
                    } else {
                        Ok(JsonResponse::error("Failed to publish script", 500))
                    }
                }
                Err(e) => {
                    console_log!("Failed to publish script: {:?}", e);
                    Ok(JsonResponse::error_with_details("Failed to publish script", &e.to_string(), 500))
                }
            }
        }
        Ok(None) => Ok(JsonResponse::error("Script not found", 404)),
        Err(e) => Ok(JsonResponse::error_with_details("Failed to check script existence", &e.to_string(), 500)),
    }
}

pub async fn handle_scripts_by_category_request(req: Request, env: &Env, category: &str) -> Result<Response> {
    if req.method() != Method::Get {
        return Ok(JsonResponse::error("Method not allowed", 405));
    }

    let db = DatabaseService::new(env);
    let url = req.url()?;

    let limit = url.search_params().get("limit")
        .and_then(|s| s.parse::<i32>().ok())
        .unwrap_or(20);
    let offset = url.search_params().get("offset")
        .and_then(|s| s.parse::<i32>().ok())
        .unwrap_or(0);
    let sort_by = url.search_params().get("sort_by")
        .unwrap_or("rating")
        .to_string();
    let sort_order = url.search_params().get("sort_order")
        .unwrap_or("desc")
        .to_string();

    let search_params = SearchParams {
        query: None,
        category: Some(category.to_string()),
        canister_id: None,
        min_rating: None,
        max_price: None,
        sort_by: Some(sort_by),
        order: Some(sort_order),
        limit: Some(limit),
        offset: Some(offset),
        is_public: Some(true),
    };

    match db.search_scripts(&search_params).await {
        Ok((scripts, _total)) => Ok(JsonResponse::success(scripts, 200)),
        Err(e) => Ok(JsonResponse::error_with_details("Failed to get scripts by category", &e.to_string(), 500)),
    }
}

pub async fn handle_scripts_count_request(_req: Request, env: &Env) -> Result<Response> {
    let db = DatabaseService::new(env);
    let database = db.get_database();

    match database.prepare("SELECT COUNT(*) as count FROM scripts")
        .first::<serde_json::Value>()
        .await
    {
        Ok(Some(result)) => {
            let count = result["count"].as_i64().unwrap_or(0) as i32;
            Ok(JsonResponse::success(serde_json::json!({ "count": count }), 200))
        }
        Ok(None) => Ok(JsonResponse::success(serde_json::json!({ "count": 0 }), 200)),
        Err(e) => Ok(JsonResponse::error_with_details("Failed to get scripts count", &e.to_string(), 500)),
    }
}