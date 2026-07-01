use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use icp_marketplace_api::auth::create_canonical_payload;
use icp_marketplace_api::middleware::auth::verify_script_update_signature;
use icp_marketplace_api::models::UpdateScriptRequest;

fn sign_test_payload(signing_key: &SigningKey, canonical_json: &str) -> (String, String) {
    let signature = signing_key.sign(canonical_json.as_bytes());
    let signature_b64 = B64.encode(signature.to_bytes());
    let public_key_b64 = B64.encode(signing_key.verifying_key().as_bytes());
    (signature_b64, public_key_b64)
}

#[test]
fn dart_generated_update_signature_verifies() {
    let secret_key_bytes = [11u8; 32];
    let signing_key = SigningKey::from_bytes(&secret_key_bytes);

    let canonical_payload = serde_json::json!({
        "action": "update",
        "script_id": "41935708-8561-4424-a42f-cba44e26785a",
        "timestamp": "2025-11-06T13:36:31.766449Z",
        "author_principal": "yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
        "title": "Updated Title",
        "description": "Test script for unit testing",
        "category": "Testing",
        "bundle": "function init(arg)\n  return { message = \"Hello from test script!\" }, {}\nend\n\nfunction view(state)\n  return { type = \"text\", text = state.message }\nend\n\nfunction update(msg, state)\n  if msg.type == \"test\" then\n    state.message = \"Updated!\"\n  end\n  return state, {}\nend",
        "version": "2.0.0",
        "price": 0.0,
        "is_public": true,
        "tags": ["test", "unit"]
    });

    let canonical_json = create_canonical_payload(&canonical_payload);
    let (signature_b64, public_key_b64) = sign_test_payload(&signing_key, &canonical_json);

    let mut request_payload = canonical_payload
        .as_object()
        .expect("canonical payload must be an object")
        .clone();
    request_payload.insert(
        "author_public_key".to_string(),
        serde_json::Value::String(public_key_b64),
    );
    request_payload.insert(
        "signature".to_string(),
        serde_json::Value::String(signature_b64),
    );

    let req: UpdateScriptRequest =
        serde_json::from_value(serde_json::Value::Object(request_payload))
            .expect("valid canonical update request");

    assert!(
        verify_script_update_signature(&req, "41935708-8561-4424-a42f-cba44e26785a").is_ok(),
        "Expected canonical payload signature to verify successfully"
    );
}

#[test]
fn verify_update_signature_allows_extra_fields_without_affecting_signature() {
    let secret_key_bytes = [7u8; 32];
    let signing_key = SigningKey::from_bytes(&secret_key_bytes);

    let canonical_payload = serde_json::json!({
        "action": "update",
        "script_id": "script-123",
        "timestamp": "2024-01-01T00:00:00Z",
        "author_principal": "principal-1",
        "title": "Title",
        "description": "Desc",
        "category": "Utility",
        "bundle": "-- body",
        "tags": ["alpha", "beta"],
        "version": "1.0.0",
        "price": 1.5,
        "is_public": true
    });

    let canonical_json = create_canonical_payload(&canonical_payload);
    let (signature_b64, public_key_b64) = sign_test_payload(&signing_key, &canonical_json);

    let mut request_payload = canonical_payload
        .as_object()
        .expect("canonical payload must be an object")
        .clone();
    request_payload.insert(
        "author_public_key".to_string(),
        serde_json::Value::String(public_key_b64),
    );
    request_payload.insert(
        "signature".to_string(),
        serde_json::Value::String(signature_b64),
    );
    request_payload.insert(
        "extra_field".to_string(),
        serde_json::Value::String("should-be-ignored".to_string()),
    );

    let request: UpdateScriptRequest =
        serde_json::from_value(serde_json::Value::Object(request_payload))
            .expect("valid update request json");

    assert!(
        verify_script_update_signature(&request, "script-123").is_ok(),
        "extra fields outside canonical payload must not affect signature verification"
    );
}

#[test]
fn verify_update_signature_rejects_tampered_payload() {
    let tampered_json = r#"{
            "action":"update",
            "script_id":"existing-script",
            "timestamp":"2025-11-06T14:22:44.069472Z",
            "author_principal":"yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
            "title":"Tampered Title",
            "description":"Updated description",
            "category":"Utility",
            "bundle":"-- updated",
            "tags":["modified","updated"],
            "version":"2.0.0",
            "price":1.0,
            "is_public":true,
            "author_public_key":"HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=",
            "signature":"c0HBe9ELBP1/pQiFOrnPEbUq9mYt+MSAr23YknlIg2+3ErC/DB/9LDq5F/FxCudj+COY8l/VNASZspj6h7zPBA=="
        }"#;

    let request: UpdateScriptRequest =
        serde_json::from_str(tampered_json).expect("valid tampered request json");

    assert!(
        verify_script_update_signature(&request, "existing-script").is_err(),
        "tampering payload must invalidate signature verification"
    );
}

#[test]
fn verify_update_signature_ignores_author_public_key_field() {
    let secret_key_bytes = [7u8; 32];
    let signing_key = SigningKey::from_bytes(&secret_key_bytes);

    let canonical_payload = serde_json::json!({
        "action": "update",
        "script_id": "script-123",
        "timestamp": "2024-01-01T00:00:00Z",
        "author_principal": "principal-1",
        "title": "Title",
        "description": "Desc",
        "category": "Utility",
        "bundle": "-- body",
        "tags": ["alpha", "beta"],
        "version": "1.0.0",
        "price": 1.5,
        "is_public": true
    });

    let canonical_json = create_canonical_payload(&canonical_payload);
    let (signature_b64, public_key_b64) = sign_test_payload(&signing_key, &canonical_json);

    let mut request_payload = canonical_payload
        .as_object()
        .expect("canonical payload must be an object")
        .clone();
    request_payload.insert(
        "author_public_key".to_string(),
        serde_json::Value::String(public_key_b64),
    );
    request_payload.insert(
        "signature".to_string(),
        serde_json::Value::String(signature_b64),
    );

    let request: UpdateScriptRequest =
        serde_json::from_value(serde_json::Value::Object(request_payload))
            .expect("valid update request json");

    assert!(
        verify_script_update_signature(&request, "script-123").is_ok(),
        "author_public_key should be ignored by signature verification logic"
    );
}

#[test]
fn verify_update_signature_accepts_fixture_payload() {
    let secret_key_bytes = [11u8; 32];
    let signing_key = SigningKey::from_bytes(&secret_key_bytes);

    let canonical_payload = serde_json::json!({
        "action": "update",
        "script_id": "93e91d19-ce61-4497-821e-4d32c03c6cc2",
        "timestamp": "2025-11-06T16:11:26.756452Z",
        "author_principal": "yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae",
        "title": "Updated Title",
        "description": "Updated description",
        "category": "Utility",
        "bundle": "-- Updated source",
        "tags": ["modified", "updated"],
        "version": "2.0.0",
        "price": 1.0,
        "is_public": true
    });

    let canonical_json = create_canonical_payload(&canonical_payload);
    let (signature_b64, public_key_b64) = sign_test_payload(&signing_key, &canonical_json);

    let mut request_payload = canonical_payload
        .as_object()
        .expect("canonical payload must be an object")
        .clone();
    request_payload.insert(
        "author_public_key".to_string(),
        serde_json::Value::String(public_key_b64),
    );
    request_payload.insert(
        "signature".to_string(),
        serde_json::Value::String(signature_b64),
    );

    let request: UpdateScriptRequest =
        serde_json::from_value(serde_json::Value::Object(request_payload))
            .expect("valid fixture request json");

    assert!(
        verify_script_update_signature(&request, "93e91d19-ce61-4497-821e-4d32c03c6cc2").is_ok(),
        "fixture payload signature should verify successfully"
    );
}
