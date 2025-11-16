use crate::models::{Script, SearchRequest, SearchResultPayload, SCRIPT_COLUMNS};
use sqlx::SqlitePool;

pub struct ScriptRepository {
    pool: SqlitePool,
}

impl ScriptRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn find_by_id(&self, id: &str) -> Result<Option<Script>, sqlx::Error> {
        let sql = format!("SELECT {} FROM scripts WHERE id = ?1", SCRIPT_COLUMNS);
        sqlx::query_as::<_, Script>(&sql)
            .bind(id)
            .fetch_optional(&self.pool)
            .await
    }

    pub async fn find_all(
        &self,
        limit: i32,
        offset: i32,
        category: Option<String>,
        include_private: bool,
    ) -> Result<Vec<Script>, sqlx::Error> {
        let category_filter = if let Some(cat) = category {
            format!(" AND category = '{}'", cat)
        } else {
            String::new()
        };

        let privacy_filter = if include_private {
            String::new()
        } else {
            " AND is_public = 1".to_string()
        };

        let sql = format!(
            "SELECT {} FROM scripts WHERE 1=1{}{} ORDER BY created_at DESC LIMIT {} OFFSET {}",
            SCRIPT_COLUMNS, category_filter, privacy_filter, limit, offset
        );

        sqlx::query_as::<_, Script>(&sql)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn count_public(&self) -> Result<i64, sqlx::Error> {
        sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
            .fetch_one(&self.pool)
            .await
    }

    pub async fn count_by_id(&self, id: &str) -> Result<i64, sqlx::Error> {
        sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE id = ?1")
            .bind(id)
            .fetch_one(&self.pool)
            .await
    }

    pub async fn create(
        &self,
        id: &str,
        title: &str,
        description: &str,
        category: &str,
        lua_source: &str,
        author_name: &str,
        author_id: &str,
        author_principal: Option<&str>,
        author_public_key: Option<&str>,
        upload_signature: Option<&str>,
        version: &str,
        price: f64,
        is_public: bool,
        compatibility: Option<&str>,
        tags_json: Option<&str>,
        timestamp: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO scripts (
                id, title, description, category, lua_source, author_name, author_id,
                author_principal, author_public_key, upload_signature, version, price,
                is_public, compatibility, tags, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
            "#,
        )
        .bind(id)
        .bind(title)
        .bind(description)
        .bind(category)
        .bind(lua_source)
        .bind(author_name)
        .bind(author_id)
        .bind(author_principal)
        .bind(author_public_key)
        .bind(upload_signature)
        .bind(version)
        .bind(price)
        .bind(is_public)
        .bind(compatibility)
        .bind(tags_json)
        .bind(timestamp)
        .bind(timestamp)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn update(
        &self,
        id: &str,
        title: Option<&str>,
        description: Option<&str>,
        category: Option<&str>,
        lua_source: Option<&str>,
        version: Option<&str>,
        price: Option<f64>,
        is_public: Option<bool>,
        tags_json: Option<&str>,
        updated_at: &str,
    ) -> Result<(), sqlx::Error> {
        let mut updates = vec!["updated_at = ?"];
        let mut query_str = String::from("UPDATE scripts SET ");

        if title.is_some() {
            updates.push("title = ?");
        }
        if description.is_some() {
            updates.push("description = ?");
        }
        if category.is_some() {
            updates.push("category = ?");
        }
        if lua_source.is_some() {
            updates.push("lua_source = ?");
        }
        if version.is_some() {
            updates.push("version = ?");
        }
        if price.is_some() {
            updates.push("price = ?");
        }
        if is_public.is_some() {
            updates.push("is_public = ?");
        }
        if tags_json.is_some() {
            updates.push("tags = ?");
        }

        query_str.push_str(&updates.join(", "));
        query_str.push_str(" WHERE id = ?");

        let mut query = sqlx::query(&query_str).bind(updated_at);

        if let Some(t) = title {
            query = query.bind(t);
        }
        if let Some(d) = description {
            query = query.bind(d);
        }
        if let Some(c) = category {
            query = query.bind(c);
        }
        if let Some(l) = lua_source {
            query = query.bind(l);
        }
        if let Some(v) = version {
            query = query.bind(v);
        }
        if let Some(p) = price {
            query = query.bind(p);
        }
        if let Some(pub_status) = is_public {
            query = query.bind(pub_status);
        }
        if let Some(t) = tags_json {
            query = query.bind(t);
        }

        query.bind(id).execute(&self.pool).await?;
        Ok(())
    }

    pub async fn delete(&self, id: &str) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM scripts WHERE id = ?1")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn publish(&self, id: &str, updated_at: &str) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE scripts SET is_public = 1, updated_at = ?1 WHERE id = ?2")
            .bind(updated_at)
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn update_stats(
        &self,
        script_id: &str,
        rating: f64,
        review_count: i32,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE scripts SET rating = ?1, review_count = ?2 WHERE id = ?3")
            .bind(rating)
            .bind(review_count)
            .bind(script_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn increment_downloads(&self, script_id: &str) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE scripts SET downloads = downloads + 1 WHERE id = ?1")
            .bind(script_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn search(
        &self,
        request: &SearchRequest,
    ) -> Result<SearchResultPayload, (poem::http::StatusCode, String)> {
        use poem::http::StatusCode;

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
            "createdAt" => "created_at",
            "rating" => "rating",
            "downloads" => "downloads",
            "price" => "price",
            "title" => "title",
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
        }

        let mut conditions: Vec<String> = Vec::new();
        let mut condition_binds: Vec<BindValue> = Vec::new();

        conditions.push("is_public = ?".to_string());
        condition_binds.push(BindValue::Text("1".to_string()));

        if let Some(query) = request
            .query
            .as_ref()
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
        {
            let like_pattern = format!("%{}%", query);
            conditions.push("(title LIKE ? OR description LIKE ? OR category LIKE ?)".to_string());
            condition_binds.push(BindValue::Text(like_pattern.clone()));
            condition_binds.push(BindValue::Text(like_pattern.clone()));
            condition_binds.push(BindValue::Text(like_pattern));
        }

        if let Some(cat) = request.category.as_ref().filter(|c| !c.is_empty()) {
            conditions.push("category = ?".to_string());
            condition_binds.push(BindValue::Text(cat.clone()));
        }

        if let Some(min_r) = request.min_rating {
            conditions.push("rating >= ?".to_string());
            condition_binds.push(BindValue::Float(min_r));
        }

        if let Some(max_p) = request.max_price {
            conditions.push("price <= ?".to_string());
            condition_binds.push(BindValue::Float(max_p));
        }

        let where_clause = if conditions.is_empty() {
            "1=1".to_string()
        } else {
            conditions.join(" AND ")
        };

        let count_sql = format!("SELECT COUNT(*) FROM scripts WHERE {}", where_clause);
        let mut count_query = sqlx::query_scalar::<_, i64>(&count_sql);
        for bind in &condition_binds {
            count_query = match bind {
                BindValue::Text(s) => count_query.bind(s),
                BindValue::Float(f) => count_query.bind(f),
            };
        }

        let total = count_query.fetch_one(&self.pool).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to count scripts: {}", e),
            )
        })?;

        let search_sql = format!(
            "SELECT {} FROM scripts WHERE {} ORDER BY {} {} LIMIT {} OFFSET {}",
            SCRIPT_COLUMNS, where_clause, sort_column, sort_order, limit, offset
        );

        let mut query = sqlx::query_as::<_, Script>(&search_sql);
        for bind in &condition_binds {
            query = match bind {
                BindValue::Text(s) => query.bind(s),
                BindValue::Float(f) => query.bind(f),
            };
        }

        let scripts = query.fetch_all(&self.pool).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to fetch scripts: {}", e),
            )
        })?;

        Ok(SearchResultPayload {
            scripts,
            total,
            limit,
            offset,
        })
    }

    pub async fn get_by_category(
        &self,
        category: &str,
        limit: i32,
    ) -> Result<Vec<Script>, sqlx::Error> {
        let sql = format!(
            "SELECT {} FROM scripts WHERE category = ?1 AND is_public = 1 ORDER BY created_at DESC LIMIT ?2",
            SCRIPT_COLUMNS
        );
        sqlx::query_as::<_, Script>(&sql)
            .bind(category)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn get_trending(&self, limit: i32) -> Result<Vec<Script>, sqlx::Error> {
        let sql = format!(
            "SELECT {} FROM scripts WHERE is_public = 1 ORDER BY downloads DESC, rating DESC LIMIT ?1",
            SCRIPT_COLUMNS
        );
        sqlx::query_as::<_, Script>(&sql)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn get_featured(
        &self,
        min_rating: f64,
        min_downloads: i32,
        limit: i32,
    ) -> Result<Vec<Script>, sqlx::Error> {
        let sql = format!(
            "SELECT {} FROM scripts WHERE is_public = 1 AND rating >= ?1 AND downloads >= ?2 ORDER BY rating DESC, downloads DESC LIMIT ?3",
            SCRIPT_COLUMNS
        );
        sqlx::query_as::<_, Script>(&sql)
            .bind(min_rating)
            .bind(min_downloads)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn get_compatible(
        &self,
        compatibility: &str,
        limit: i32,
    ) -> Result<Vec<Script>, sqlx::Error> {
        let sql = format!(
            "SELECT {} FROM scripts WHERE is_public = 1 AND (compatibility IS NULL OR compatibility LIKE ?1) ORDER BY created_at DESC LIMIT ?2",
            SCRIPT_COLUMNS
        );
        let pattern = format!("%{}%", compatibility);
        sqlx::query_as::<_, Script>(&sql)
            .bind(pattern)
            .bind(limit)
            .fetch_all(&self.pool)
            .await
    }

    pub async fn get_marketplace_stats(&self) -> Result<(i64, i64, f64), sqlx::Error> {
        let scripts_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM scripts WHERE is_public = 1")
                .fetch_one(&self.pool)
                .await?;

        let total_downloads: i64 = sqlx::query_scalar(
            "SELECT COALESCE(SUM(downloads), 0) FROM scripts WHERE is_public = 1",
        )
        .fetch_one(&self.pool)
        .await?;

        let avg_rating: Option<f64> = sqlx::query_scalar(
            "SELECT AVG(rating) FROM scripts WHERE is_public = 1 AND rating > 0",
        )
        .fetch_one(&self.pool)
        .await?;

        Ok((scripts_count, total_downloads, avg_rating.unwrap_or(0.0)))
    }
}
