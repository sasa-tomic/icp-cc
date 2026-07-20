//! IH-11 / UXR-9: `GET /api/v1/scripts/categories` MUST return the distinct,
//! content-derived categories — NOT the misleading "Script not found" it used
//! to return when the literal path was shadowed by `/scripts/:id`.
//!
//! Proves:
//! 1. The route resolves to the categories handler (not `get_script` with
//!    id="categories") — the routing fix (registered BEFORE `/scripts/:id`).
//! 2. The returned categories are the DISTINCT, public, non-empty set, ordered
//!    alphabetically (single source: the actual scripts, not a hardcoded list).
//! 3. Private / empty categories are excluded.
//!
//! Uses the real handlers over an in-memory SQLite `AppState` via Poem's
//! `TestClient` — no re-implemented SQL.

use icp_marketplace_api::db::initialize_database;
use icp_marketplace_api::handlers::{get_script, get_script_categories};
use icp_marketplace_api::models::AppState;
use icp_marketplace_api::services::PasskeyService;
use poem::http::StatusCode;
use poem::test::TestClient;
use poem::{get, middleware::Cors, EndpointExt, Route};
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use std::sync::Arc;

/// Inserts a script with an explicit category + public flag.
async fn insert_script(pool: &SqlitePool, id: &str, category: &str, is_public: bool) {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        r#"INSERT INTO scripts (
            id, slug, owner_account_id, title, description, category, tags,
            bundle, author_principal, author_public_key, upload_signature,
            canister_ids, icon_url, screenshots, version, compatibility,
            price, is_public, downloads, rating, review_count,
            created_at, updated_at, deleted_at
        ) VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, ?, 0, 0.0, 0, ?, ?, NULL)"#,
    )
    .bind(id)
    .bind(format!("slug-{id}"))
    .bind(format!("Title {id}"))
    .bind("description")
    .bind(category)
    .bind("bundle")
    .bind("1.0.0")
    .bind(0.0)
    .bind(is_public)
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

    // Public scripts across 3 distinct categories (with a duplicate).
    insert_script(&pool, "pub-util-a", "Utilities", true).await;
    insert_script(&pool, "pub-util-b", "Utilities", true).await; // duplicate category
    insert_script(&pool, "pub-game", "Gaming", true).await;
    insert_script(&pool, "pub-finance", "Finance", true).await;
    // A private script whose category MUST NOT leak into the public list.
    insert_script(&pool, "priv-secret", "Secret", false).await;
    // A public script with an EMPTY category — excluded as noise.
    insert_script(&pool, "pub-empty", "", true).await;

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

/// Mirrors the route ordering in `main.rs`: `categories` BEFORE `/scripts/:id`
/// so the literal path is not shadowed by the `:id` capture.
fn build_app(state: Arc<AppState>) -> impl poem::Endpoint {
    Route::new()
        .at("/api/v1/scripts/categories", get(get_script_categories))
        .at("/api/v1/scripts/:id", get(get_script))
        .with(Cors::new())
        .data(state)
}

async fn json_value(resp: poem::test::TestResponse) -> serde_json::Value {
    resp.json().await.value().deserialize::<serde_json::Value>()
}

#[tokio::test]
async fn categories_returns_distinct_public_categories_not_script_not_found() {
    // The headline UXR-9 regression: before the fix this route matched
    // `/scripts/:id` and returned {"error":"Script not found"}.
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/categories").send().await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert_eq!(json["success"], true);

    let cats: Vec<String> = json["data"]["categories"]
        .as_array()
        .expect("data.categories is an array")
        .iter()
        .map(|v| v.as_str().expect("category is a string").to_string())
        .collect();

    // Distinct + public + non-empty, alphabetical.
    assert_eq!(
        cats,
        vec!["Finance", "Gaming", "Utilities"],
        "categories must be the distinct public non-empty set, alphabetical"
    );
    assert!(
        !cats.contains(&"Secret".to_string()),
        "private-script category must NOT appear"
    );
    assert!(
        !cats.iter().any(|c| c.is_empty()),
        "empty category must NOT appear"
    );
}

#[tokio::test]
async fn categories_route_is_not_shadowed_by_script_id_capture() {
    // Defensive: confirm `/scripts/categories` does NOT hit the `:id` handler
    // (which would 404 with "Script not found"). The body must carry a
    // `data.categories` array, not an `error` field.
    let client = TestClient::new(build_app(build_state().await));
    let resp = client.get("/api/v1/scripts/categories").send().await;
    resp.assert_status(StatusCode::OK);
    let json = json_value(resp).await;
    assert!(
        json.get("error").is_none(),
        "must not return 'Script not found' (shadowed route); got: {json}"
    );
    assert!(
        json["data"]["categories"].is_array(),
        "must return the categories array; got: {json}"
    );
}
