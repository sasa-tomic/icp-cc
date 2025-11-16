use poem::{http::StatusCode, Response};

use crate::auth::verify_operation_signature;
use crate::models::{CreateScriptRequest, DeleteScriptRequest, UpdateScriptRequest};
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
pub fn build_upload_payload(req: &CreateScriptRequest) -> Result<serde_json::Value, Box<Response>> {
    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    let mut payload = serde_json::json!({
        "action": "upload",
        "title": &req.title,
        "description": &req.description,
        "category": &req.category,
        "lua_source": &req.lua_source,
        "version": req.version.as_deref().unwrap_or("1.0.0"),
        "author_principal": author_principal,
    });

    // Add optional fields
    if let Some(ref timestamp) = req.timestamp {
        payload["timestamp"] = serde_json::Value::String(timestamp.clone());
    }
    if let Some(ref tags) = req.tags {
        let mut sorted_tags = tags.clone();
        sorted_tags.sort();
        payload["tags"] = serde_json::json!(sorted_tags);
    }
    if let Some(ref compatibility) = req.compatibility {
        payload["compatibility"] = serde_json::Value::String(compatibility.clone());
    }

    Ok(payload)
}

/// Builds the canonical payload for script deletion signature verification
pub fn build_deletion_payload(
    req: &DeleteScriptRequest,
    script_id: &str,
) -> Result<serde_json::Value, Box<Response>> {
    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    let mut payload = serde_json::json!({
        "action": "delete",
        "script_id": script_id,
        "author_principal": author_principal,
    });

    if let Some(ref timestamp) = req.timestamp {
        payload["timestamp"] = serde_json::Value::String(timestamp.clone());
    }

    Ok(payload)
}

pub fn build_canonical_update_payload(
    req: &UpdateScriptRequest,
    script_id: &str,
) -> Result<serde_json::Value, Box<Response>> {
    if let Some(body_script_id) = &req.script_id {
        if body_script_id != script_id {
            return Err(Box::new(error_response(
                StatusCode::UNAUTHORIZED,
                "Signed script_id does not match request path",
            )));
        }
    }

    let action = req.action.as_deref().unwrap_or("update");
    if action != "update" {
        return Err(Box::new(error_response(
            StatusCode::BAD_REQUEST,
            "Invalid action for script update signature verification",
        )));
    }

    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    let mut payload = serde_json::Map::new();
    payload.insert(
        "action".to_string(),
        serde_json::Value::String("update".to_string()),
    );
    payload.insert(
        "script_id".to_string(),
        serde_json::Value::String(script_id.to_string()),
    );
    payload.insert(
        "author_principal".to_string(),
        serde_json::Value::String(author_principal.clone()),
    );

    if let Some(timestamp) = &req.timestamp {
        payload.insert(
            "timestamp".to_string(),
            serde_json::Value::String(timestamp.clone()),
        );
    }

    let insert_optional_string =
        |key: &str,
         value: &Option<String>,
         map: &mut serde_json::Map<String, serde_json::Value>| {
            if let Some(content) = value {
                map.insert(key.to_string(), serde_json::Value::String(content.clone()));
            }
        };

    insert_optional_string("title", &req.title, &mut payload);
    insert_optional_string("description", &req.description, &mut payload);
    insert_optional_string("category", &req.category, &mut payload);
    insert_optional_string("lua_source", &req.lua_source, &mut payload);
    insert_optional_string("version", &req.version, &mut payload);

    if let Some(tags) = &req.tags {
        let mut sorted_tags = tags.clone();
        sorted_tags.sort();
        let tag_values = sorted_tags
            .into_iter()
            .map(serde_json::Value::String)
            .collect::<Vec<_>>();
        payload.insert("tags".to_string(), serde_json::Value::Array(tag_values));
    }

    if let Some(price) = req.price {
        let number = serde_json::Number::from_f64(price).ok_or_else(|| {
            Box::new(error_response(
                StatusCode::BAD_REQUEST,
                "Invalid price value for signature verification",
            ))
        })?;
        payload.insert("price".to_string(), serde_json::Value::Number(number));
    }

    if let Some(is_public) = req.is_public {
        payload.insert("is_public".to_string(), serde_json::Value::Bool(is_public));
    }

    Ok(serde_json::Value::Object(payload))
}

/// Verifies script update signature (used in tests)
#[cfg(test)]
pub fn verify_script_update_signature(
    req: &UpdateScriptRequest,
    script_id: &str,
) -> Result<(), Box<Response>> {
    verify_request_auth(req, "Script update", || {
        build_canonical_update_payload(req, script_id)
    })
}

/// Builds the canonical payload for script publish signature verification
pub fn build_publish_payload(
    req: &UpdateScriptRequest,
    script_id: &str,
) -> Result<serde_json::Value, Box<Response>> {
    let author_principal = req.author_principal.as_ref().ok_or_else(|| {
        Box::new(error_response(
            StatusCode::UNAUTHORIZED,
            "Missing author_principal for signature verification",
        ))
    })?;

    let mut payload = serde_json::json!({
        "action": "update",
        "script_id": script_id,
        "is_public": true,
        "author_principal": author_principal,
    });

    if let Some(ref timestamp) = req.timestamp {
        payload["timestamp"] = serde_json::Value::String(timestamp.clone());
    }

    Ok(payload)
}
