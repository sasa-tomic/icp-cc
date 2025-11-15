use poem::{
    delete, get, handler, listener::TcpListener, middleware::Cors, post, put,
    web::{Data, Json, Path, Query},
    EndpointExt, Route, Server, http::StatusCode, IntoResponse, Response,
};
use serde::{Deserialize, Serialize};
use sqlx::{sqlite::SqlitePool, FromRow};
use std::{env, net::TcpListener as StdTcpListener, sync::Arc};

#[derive(Debug, Serialize, Deserialize, FromRow)]
struct Script {
    id: String,
    title: String,
    description: String,
    category: String,
    lua_source: String,
    author_name: String,
    is_public: bool,
    rating: f64,
    downloads: i32,
    review_count: i32,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Deserialize)]
struct ScriptsQuery {
    limit: Option<i32>,
    offset: Option<i32>,
    category: Option<String>,
    #[serde(rename = "includePrivate")]
    include_private: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct CreateScriptRequest {
    title: String,
    description: String,
    category: String,
    lua_source: String,
    author_name: String,
    author_id: Option<String>,
    author_principal: Option<String>,
    author_public_key: Option<String>,
    upload_signature: Option<String>,
    signature: Option<String>,
    timestamp: Option<String>,
    version: Option<String>,
    price: Option<f64>,
    is_public: Option<bool>,
    tags: Option<Vec<String>>,
    action: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UpdateScriptRequest {
    title: Option<String>,
    description: Option<String>,
    category: Option<String>,
    lua_source: Option<String>,
    version: Option<String>,
    price: Option<f64>,
    is_public: Option<bool>,
    tags: Option<Vec<String>>,
    signature: Option<String>,
    timestamp: Option<String>,
    script_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct DeleteScriptRequest {
    script_id: Option<String>,
    author_principal: Option<String>,
    signature: Option<String>,
    timestamp: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SearchQuery {
    q: String,
    limit: Option<i32>,
}

struct AppState {
    pool: SqlitePool,
}

#[handler]
async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "ICP Marketplace API (Rust + Poem) is running",
        "environment": env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

#[handler]
async fn ping() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "message": "pong",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

#[handler]
async fn get_scripts(
    Query(params): Query<ScriptsQuery>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    let limit = params.limit.unwrap_or(20);
    let offset = params.offset.unwrap_or(0);

    let query = if let Some(category) = params.category {
        sqlx::query_as::<_, Script>(
            "SELECT id, title, description, category, lua_source, author_name, is_public,
                    rating, downloads, review_count, created_at, updated_at
             FROM scripts
             WHERE category = ?1 AND is_public = 1
             ORDER BY created_at DESC
             LIMIT ?2 OFFSET ?3"
        )
        .bind(category)
        .bind(limit)
        .bind(offset)
    } else {
        sqlx::query_as::<_, Script>(
            "SELECT id, title, description, category, lua_source, author_name, is_public,
                    rating, downloads, review_count, created_at, updated_at
             FROM scripts
             WHERE is_public = 1
             ORDER BY created_at DESC
             LIMIT ?1 OFFSET ?2"
        )
        .bind(limit)
        .bind(offset)
    };

    match query.fetch_all(&state.pool).await {
        Ok(scripts) => {
            let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
                .fetch_one(&state.pool)
                .await
                .unwrap_or(0);

            Json(serde_json::json!({
                "success": true,
                "data": {
                    "scripts": scripts,
                    "total": total,
                    "hasMore": (offset + limit) < total as i32
                }
            }))
            .into_response()
        }
        Err(e) => {
            tracing::error!("Failed to get scripts: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get scripts"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_script(
    Path(script_id): Path<String>,
    Data(state): Data<&Arc<AppState>>,
) -> Response {
    match sqlx::query_as::<_, Script>(
        "SELECT id, title, description, category, lua_source, author_name, is_public,
                rating, downloads, review_count, created_at, updated_at
         FROM scripts
         WHERE id = ?1 AND is_public = 1"
    )
    .bind(&script_id)
    .fetch_optional(&state.pool)
    .await
    {
        Ok(Some(script)) => Json(serde_json::json!({
            "success": true,
            "data": script
        }))
        .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "success": false,
                "error": "Script not found"
            })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!("Failed to get script: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get script"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_scripts_count(Data(state): Data<&Arc<AppState>>) -> Response {
    match sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
        .fetch_one(&state.pool)
        .await
    {
        Ok(count) => Json(serde_json::json!({
            "success": true,
            "data": { "count": count }
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to get count: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to get count"
                })),
            )
                .into_response()
        }
    }
}

#[handler]
async fn get_marketplace_stats(Data(state): Data<&Arc<AppState>>) -> Response {
    let scripts_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
        .fetch_one(&state.pool)
        .await
        .unwrap_or(0);

    let total_downloads: i64 =
        sqlx::query_scalar("SELECT COALESCE(SUM(downloads), 0) FROM scripts WHERE is_public = 1")
            .fetch_one(&state.pool)
            .await
            .unwrap_or(0);

    let avg_rating: Option<f64> =
        sqlx::query_scalar("SELECT AVG(rating) FROM scripts WHERE is_public = 1 AND rating > 0")
            .fetch_one(&state.pool)
            .await
            .ok();

    Json(serde_json::json!({
        "success": true,
        "data": {
            "totalScripts": scripts_count,
            "totalDownloads": total_downloads,
            "averageRating": avg_rating.unwrap_or(0.0),
            "timestamp": chrono::Utc::now().to_rfc3339()
        }
    }))
    .into_response()
}

#[handler]
async fn reset_database(Data(state): Data<&Arc<AppState>>) -> Response {
    if env::var("ENVIRONMENT").unwrap_or_default() != "development" {
        return (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "success": false,
                "error": "Database reset only available in development"
            })),
        )
            .into_response();
    }

    match sqlx::query("DELETE FROM scripts")
        .execute(&state.pool)
        .await
    {
        Ok(_) => Json(serde_json::json!({
            "success": true,
            "message": "Database reset successfully"
        }))
        .into_response(),
        Err(e) => {
            tracing::error!("Failed to reset database: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Failed to reset database"
                })),
            )
                .into_response()
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    // Load environment variables
    dotenv::dotenv().ok();

    // Database setup
    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite:./data/dev.db".to_string());

    tracing::info!("Connecting to database: {}", database_url);

    let pool = SqlitePool::connect(&database_url)
        .await
        .expect("Failed to connect to database");

    // Run migrations
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS scripts (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            category TEXT NOT NULL,
            lua_source TEXT NOT NULL,
            author_name TEXT NOT NULL,
            is_public INTEGER DEFAULT 1,
            rating REAL DEFAULT 0.0,
            downloads INTEGER DEFAULT 0,
            review_count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        "#,
    )
    .execute(&pool)
    .await
    .expect("Failed to create scripts table");

    tracing::info!("Database initialized successfully");

    let state = Arc::new(AppState { pool });

    // Build app
    let app = Route::new()
        .at("/api/v1/health", get(health_check))
        .at("/api/v1/ping", get(ping))
        .at("/api/v1/scripts", get(get_scripts))
        .at("/api/v1/scripts/count", get(get_scripts_count))
        .at("/api/v1/scripts/:id", get(get_script))
        .at("/api/v1/marketplace-stats", get(get_marketplace_stats))
        .at("/api/dev/reset-database", post(reset_database))
        .with(Cors::new())
        .data(state);

    // Start server
    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("127.0.0.1:{}", port);

    tracing::info!("Starting server on http://{}", addr);

    // Bind once to get the actual address (important for port 0 -> random port)
    let std_listener = StdTcpListener::bind(&addr)
        .expect("Failed to bind to address");
    let actual_addr = std_listener.local_addr()
        .expect("Failed to get local address");

    // Log the actual listening address for external tools to parse
    tracing::info!("listening addr=socket://{}", actual_addr);

    // Close the std listener since we just needed it for the address
    drop(std_listener);

    // Now bind with Poem's listener
    let listener = TcpListener::bind(actual_addr);

    Server::new(listener).run(app).await
}
