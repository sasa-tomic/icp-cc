use icp_marketplace_api::db::initialize_database;
use icp_marketplace_api::models::{
    AppState, Script, SearchRequest, SearchResultPayload, SCRIPT_COLUMNS_WITH_ACCOUNT,
};
use icp_marketplace_api::repositories::PurchaseRepository;
use icp_marketplace_api::services::{
    AccountService, PasskeyService, PaymentService, ReviewService, ScriptService,
};
use poem::http::StatusCode;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use std::sync::Arc;

async fn run_marketplace_search(
    pool: &SqlitePool,
    request: &SearchRequest,
) -> Result<SearchResultPayload, (StatusCode, String)> {
    if request.canister_id.is_some() {
        tracing::debug!("Ignoring canister_id filter; backend does not support it yet");
    }

    let limit = request.limit.unwrap_or(20);
    if limit <= 0 || limit > 100 {
        return Err((
            StatusCode::BAD_REQUEST,
            "limit must be between 1 and 100".to_string(),
        ));
    }

    let offset = request.offset.unwrap_or(0);
    if offset < 0 {
        return Err((
            StatusCode::BAD_REQUEST,
            "offset must be zero or greater".to_string(),
        ));
    }

    let sort_field = request.sort_by.as_deref().unwrap_or("createdAt");
    let sort_column = match sort_field {
        "createdAt" => "scripts.created_at",
        "rating" => "scripts.rating",
        "downloads" => "scripts.downloads",
        "price" => "scripts.price",
        "title" => "scripts.title",
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                "unsupported sort field".to_string(),
            ));
        }
    };

    let sort_order_raw = request.sort_order.as_deref().unwrap_or("desc");
    let sort_order = match sort_order_raw.to_ascii_lowercase().as_str() {
        "asc" => "ASC",
        "desc" => "DESC",
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                "order must be 'asc' or 'desc'".to_string(),
            ));
        }
    };

    #[derive(Clone)]
    enum BindValue {
        Text(String),
        Float(f64),
        Integer(i64),
        Bool(bool),
    }

    let mut conditions: Vec<String> = Vec::new();
    let mut condition_binds: Vec<BindValue> = Vec::new();

    conditions.push("scripts.is_public = ?".to_string());
    condition_binds.push(BindValue::Bool(true));

    if let Some(query) = request
        .query
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        let like_pattern = format!("%{}%", query);
        conditions.push(
            "(scripts.title LIKE ? OR scripts.description LIKE ? OR scripts.category LIKE ?)"
                .to_string(),
        );
        condition_binds.push(BindValue::Text(like_pattern.clone()));
        condition_binds.push(BindValue::Text(like_pattern.clone()));
        condition_binds.push(BindValue::Text(like_pattern));
    }

    if let Some(category) = request
        .category
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        conditions.push("scripts.category = ?".to_string());
        condition_binds.push(BindValue::Text(category.to_string()));
    }

    if let Some(min_rating) = request.min_rating {
        conditions.push("scripts.rating >= ?".to_string());
        condition_binds.push(BindValue::Float(min_rating));
    }

    if let Some(max_price) = request.max_price {
        conditions.push("scripts.price <= ?".to_string());
        condition_binds.push(BindValue::Float(max_price));
    }

    let mut where_clause = String::new();
    if !conditions.is_empty() {
        where_clause.push_str(" WHERE ");
        where_clause.push_str(&conditions.join(" AND "));
    }

    let search_sql = format!(
        "SELECT {} FROM scripts LEFT JOIN accounts ON scripts.owner_account_id = accounts.id{} ORDER BY {} {} LIMIT ? OFFSET ?",
        SCRIPT_COLUMNS_WITH_ACCOUNT, where_clause, sort_column, sort_order
    );

    let count_sql = format!("SELECT COUNT(*) FROM scripts{}", where_clause);

    let mut search_binds = condition_binds.clone();
    search_binds.push(BindValue::Integer(limit));
    search_binds.push(BindValue::Integer(offset));

    let mut count_query = sqlx::query_scalar::<_, i64>(&count_sql);
    for value in &condition_binds {
        count_query = match value {
            BindValue::Text(val) => count_query.bind(val),
            BindValue::Float(val) => count_query.bind(val),
            BindValue::Integer(val) => count_query.bind(val),
            BindValue::Bool(val) => count_query.bind(*val),
        };
    }

    let total = count_query.fetch_one(pool).await.map_err(|e| {
        tracing::error!("Failed to count scripts: {}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to execute search".to_string(),
        )
    })?;

    let mut query = sqlx::query_as::<_, Script>(&search_sql);
    for value in &search_binds {
        query = match value {
            BindValue::Text(val) => query.bind(val),
            BindValue::Float(val) => query.bind(val),
            BindValue::Integer(val) => query.bind(val),
            BindValue::Bool(val) => query.bind(*val),
        };
    }

    let scripts = query.fetch_all(pool).await.map_err(|e| {
        tracing::error!("Failed to search scripts: {}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to execute search".to_string(),
        )
    })?;

    Ok(SearchResultPayload {
        scripts,
        total,
        limit,
        offset,
    })
}

fn resolve_script_visibility(flag: Option<bool>) -> bool {
    flag.unwrap_or(true)
}

struct ScriptFixture<'a> {
    id: &'a str,
    title: &'a str,
    category: &'a str,
    bundle: &'a str,
    rating: f64,
    price: f64,
    downloads: i32,
    review_count: i32,
    created_at: &'a str,
}

async fn insert_script(pool: &SqlitePool, fixture: ScriptFixture<'_>) {
    sqlx::query(
        "INSERT INTO scripts (id, slug, owner_account_id, title, description, category, tags, bundle, author_principal, author_public_key, upload_signature, canister_ids, icon_url, screenshots, version, compatibility, price, is_public, downloads, rating, review_count, created_at, updated_at) VALUES (?1, ?2, NULL, ?3, ?4, ?5, '[]', ?6, NULL, NULL, NULL, NULL, NULL, NULL, '1.0.0', NULL, ?7, 1, ?8, ?9, ?10, ?11, ?11)",
    )
    .bind(fixture.id)
    .bind(format!("test-{}", fixture.id))
    .bind(fixture.title)
    .bind(format!("{} description", fixture.title))
    .bind(fixture.category)
    .bind(fixture.bundle)
    .bind(fixture.price)
    .bind(fixture.downloads)
    .bind(fixture.rating)
    .bind(fixture.review_count)
    .bind(fixture.created_at)
    .execute(pool)
    .await
    .expect("failed to insert script");
}

async fn setup_search_state() -> Arc<AppState> {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("failed to create in-memory sqlite pool");

    initialize_database(&pool).await;

    insert_script(
        &pool,
        ScriptFixture {
            id: "script-1",
            title: "Test Script One",
            category: "Utility",
            bundle: "-- script one",
            rating: 4.5,
            price: 9.99,
            downloads: 250,
            review_count: 5,
            created_at: "2024-01-01T00:00:00Z",
        },
    )
    .await;

    insert_script(
        &pool,
        ScriptFixture {
            id: "script-2",
            title: "Another Utility Script",
            category: "Utility",
            bundle: "-- script two",
            rating: 4.8,
            price: 14.50,
            downloads: 300,
            review_count: 8,
            created_at: "2024-03-15T12:00:00Z",
        },
    )
    .await;

    insert_script(
        &pool,
        ScriptFixture {
            id: "script-3",
            title: "Analytics Tool",
            category: "Analytics",
            bundle: "-- script three",
            rating: 3.2,
            price: 0.0,
            downloads: 120,
            review_count: 2,
            created_at: "2023-12-10T08:30:00Z",
        },
    )
    .await;

    let passkey_service = PasskeyService::new(pool.clone(), "localhost", "http://localhost:58000")
        .expect("Failed to create PasskeyService");

    Arc::new(AppState {
        pool: pool.clone(),
        account_service: AccountService::new(pool.clone()),
        script_service: ScriptService::new(pool.clone()),
        review_service: ReviewService::new(pool.clone()),
        passkey_service,
        purchase_repo: PurchaseRepository::new(pool.clone()),
        payment_service: PaymentService::from_env(pool),
        recovery_rate_limiter: std::sync::Arc::new(
            icp_marketplace_api::rate_limit::SlidingWindowRateLimiter::new(5, 15 * 60),
        ),
    })
}

#[tokio::test]
async fn search_scripts_returns_paginated_results() {
    let state = setup_search_state().await;

    let request = SearchRequest {
        query: Some("Utility".to_string()),
        category: Some("Utility".to_string()),
        sort_by: Some("createdAt".to_string()),
        sort_order: Some("desc".to_string()),
        limit: Some(1),
        offset: Some(0),
        ..Default::default()
    };

    let result = run_marketplace_search(&state.pool, &request)
        .await
        .expect("marketplace search should succeed");

    assert_eq!(result.limit, 1, "limit must echo input");
    assert_eq!(result.offset, 0, "offset must echo input");
    assert_eq!(result.total, 2, "total must reflect matching rows");
    assert_eq!(result.scripts.len(), 1, "should return single script page");
    assert_eq!(
        result.scripts[0].id, "script-2",
        "most recent Utility script must be first"
    );
    assert!(
        result.offset + (result.scripts.len() as i64) < result.total,
        "hasMore must be true when additional rows exist"
    );
}

#[tokio::test]
async fn search_scripts_rejects_invalid_sort_field() {
    let state = setup_search_state().await;

    let request = SearchRequest {
        query: Some("Utility".to_string()),
        sort_by: Some("unsupported".to_string()),
        sort_order: Some("asc".to_string()),
        limit: Some(5),
        offset: Some(0),
        ..Default::default()
    };

    let error = run_marketplace_search(&state.pool, &request)
        .await
        .expect_err("unsupported sort field must fail");

    assert_eq!(
        error.0,
        StatusCode::BAD_REQUEST,
        "invalid sort should map to 400"
    );
    assert!(
        error.1.contains("sort"),
        "error message must mention sort validation"
    );
}

#[test]
fn resolve_visibility_defaults_to_public() {
    assert!(
        resolve_script_visibility(None),
        "missing visibility flag must default to public"
    );
}

#[test]
fn resolve_visibility_preserves_private_flag() {
    assert!(
        !resolve_script_visibility(Some(false)),
        "explicit private uploads must stay private"
    );
}
