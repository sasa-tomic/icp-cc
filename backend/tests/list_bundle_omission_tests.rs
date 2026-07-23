//! IH-5 / UXR-3 contract: marketplace LIST endpoints MUST NOT ship the full
//! source `bundle` per item (browse only needs metadata), while `GET
//! /scripts/:id` STILL carries the bundle for a free script.
//!
//! Uses the real handlers over an in-memory SQLite `AppState` via Poem's
//! `TestClient` — no re-implemented SQL, no mocked serialization.

use icp_marketplace_api::db::initialize_database;
use icp_marketplace_api::handlers::{
    get_compatible_scripts, get_featured_scripts, get_script, get_scripts, get_scripts_by_category,
    get_trending_scripts, search_scripts,
};
use icp_marketplace_api::models::AppState;
use icp_marketplace_api::services::PasskeyService;
use poem::http::StatusCode;
use poem::test::TestClient;
use poem::{get, middleware::Cors, post, EndpointExt, Route};
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use std::sync::Arc;

/// Inserts a public script with explicit stats so it shows up in EVERY list
/// endpoint (featured needs `rating >= 4.5` and `downloads >= 10`; trending
/// orders by downloads; category/compatible/list/search all include public
/// rows).
async fn insert_script(
    pool: &SqlitePool,
    id: &str,
    price: f64,
    rating: f64,
    downloads: i32,
    bundle: &str,
) {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        r#"INSERT INTO scripts (
            id, slug, owner_account_id, title, description, category, tags,
            bundle, author_principal, author_public_key, upload_signature,
            canister_ids, icon_url, screenshots, version, compatibility,
            price, is_public, downloads, rating, review_count,
            created_at, updated_at, deleted_at
        ) VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 1, ?, ?, 1, ?, ?, NULL)"#,
    )
    .bind(id)
    .bind(format!("slug-{id}"))
    .bind(format!("Title {id}"))
    .bind("description")
    .bind("utility")
    .bind(bundle)
    .bind("1.0.0")
    .bind(price)
    .bind(downloads)
    .bind(rating)
    .bind(&now)
    .bind(&now)
    .execute(pool)
    .await
    .expect("failed to insert script");
}

async fn build_state() -> Arc<AppState> {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("failed to create in-memory sqlite pool");
    initialize_database(&pool).await;

    // A free script + a paid script, both featured-eligible.
    insert_script(&pool, "free-1", 0.0, 4.8, 100, "print('free source')").await;
    insert_script(&pool, "paid-1", 9.99, 4.7, 50, "print('paid source')").await;

    let passkey_service = PasskeyService::new(pool.clone(), "localhost", "http://localhost:58000")
        .expect("Failed to create PasskeyService");

    Arc::new(icp_marketplace_api::test_support::app_state_stub(
        pool,
        passkey_service,
        std::sync::Arc::new(icp_marketplace_api::rate_limit::SlidingWindowRateLimiter::new(
            5,
            15 * 60,
        )),
    ))
}

/// Wires every list endpoint + the detail endpoint, mirroring the route
/// ordering in `main.rs` (specific paths before `/scripts/:id`).
fn build_app(state: Arc<AppState>) -> impl poem::Endpoint {
    Route::new()
        .at("/api/v1/scripts", get(get_scripts))
        .at("/api/v1/scripts/search", post(search_scripts))
        .at("/api/v1/scripts/trending", get(get_trending_scripts))
        .at("/api/v1/scripts/featured", get(get_featured_scripts))
        .at("/api/v1/scripts/compatible", get(get_compatible_scripts))
        .at(
            "/api/v1/scripts/category/:category",
            get(get_scripts_by_category),
        )
        .at("/api/v1/scripts/:id", get(get_script))
        .with(Cors::new())
        .data(state)
}

async fn json_value(resp: poem::test::TestResponse) -> serde_json::Value {
    resp.json().await.value().deserialize::<serde_json::Value>()
}

/// Pulls the scripts array out of a list response, tolerating BOTH envelope
/// shapes: `/scripts` + `/scripts/search` wrap it under `data.scripts`, while
/// featured/trending/compatible/category put the array directly under `data`.
fn script_items(body: &serde_json::Value) -> Vec<&serde_json::Value> {
    let data = body
        .get("data")
        .expect("list response must carry a `data` envelope");
    let arr = data
        .get("scripts")
        .and_then(|v| v.as_array())
        .or_else(|| data.as_array())
        .expect("data.scripts (or data itself) must be the scripts array");
    assert!(!arr.is_empty(), "fixture scripts must appear in the list");
    arr.iter().collect()
}

/// Asserts every item in a browse list omits `bundle` but keeps metadata.
fn assert_no_bundle_anywhere(items: &[&serde_json::Value]) {
    for item in items {
        let obj = item.as_object().expect("each list item is a JSON object");
        assert!(
            !obj.contains_key("bundle"),
            "LIST endpoint must NOT ship the full `bundle` (IH-5); got keys: {:?}",
            obj.keys().collect::<Vec<_>>()
        );
        assert!(
            obj.contains_key("title") && obj.contains_key("price"),
            "browse metadata (title, price) must survive: {:?}",
            obj.keys().collect::<Vec<_>>()
        );
    }
}

#[tokio::test]
async fn get_scripts_list_omits_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts?limit=10").send().await;
    resp.assert_status(StatusCode::OK);
    let body = json_value(resp).await;
    let items = script_items(&body);
    assert_no_bundle_anywhere(&items);
}

#[tokio::test]
async fn get_featured_omits_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/featured").send().await;
    resp.assert_status(StatusCode::OK);
    let body = json_value(resp).await;
    let items = script_items(&body);
    assert_no_bundle_anywhere(&items);
}

#[tokio::test]
async fn get_trending_omits_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/trending").send().await;
    resp.assert_status(StatusCode::OK);
    let body = json_value(resp).await;
    let items = script_items(&body);
    assert_no_bundle_anywhere(&items);
}

#[tokio::test]
async fn get_compatible_omits_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/compatible").send().await;
    resp.assert_status(StatusCode::OK);
    let body = json_value(resp).await;
    let items = script_items(&body);
    assert_no_bundle_anywhere(&items);
}

#[tokio::test]
async fn get_scripts_by_category_omits_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/category/utility").send().await;
    resp.assert_status(StatusCode::OK);
    let body = json_value(resp).await;
    let items = script_items(&body);
    assert_no_bundle_anywhere(&items);
}

#[tokio::test]
async fn search_scripts_omits_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client
        .post("/api/v1/scripts/search")
        .body_json(&serde_json::json!({ "limit": 10 }))
        .send()
        .await;
    resp.assert_status(StatusCode::OK);
    let body = json_value(resp).await;
    let items = script_items(&body);
    assert_no_bundle_anywhere(&items);
}

/// Complementary check: the detail endpoint STILL ships the bundle (the run
/// flow depends on it). All scripts are free, so the bundle is always present.
#[tokio::test]
async fn get_script_detail_free_still_includes_bundle() {
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/free-1").send().await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);
    assert_eq!(
        json["data"]["bundle"], "print('free source')",
        "script detail MUST carry the full bundle (run flow)"
    );
}
