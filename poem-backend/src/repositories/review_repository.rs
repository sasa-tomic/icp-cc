use crate::models::Review;
use sqlx::SqlitePool;

pub struct ReviewRepository {
    pool: SqlitePool,
}

impl ReviewRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn find_by_script(
        &self,
        script_id: &str,
        limit: i32,
        offset: i32,
    ) -> Result<Vec<Review>, sqlx::Error> {
        sqlx::query_as::<_, Review>(
            "SELECT id, script_id, user_id, rating, comment, created_at, updated_at
             FROM reviews WHERE script_id = ?1 ORDER BY created_at DESC LIMIT ?2 OFFSET ?3",
        )
        .bind(script_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
    }

    pub async fn count_by_script(&self, script_id: &str) -> Result<i32, sqlx::Error> {
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM reviews WHERE script_id = ?1")
            .bind(script_id)
            .fetch_one(&self.pool)
            .await?;
        Ok(count as i32)
    }

    pub async fn count_by_script_and_user(
        &self,
        script_id: &str,
        user_id: &str,
    ) -> Result<i64, sqlx::Error> {
        sqlx::query_scalar("SELECT COUNT(*) FROM reviews WHERE script_id = ?1 AND user_id = ?2")
            .bind(script_id)
            .bind(user_id)
            .fetch_one(&self.pool)
            .await
    }

    pub async fn create(
        &self,
        id: &str,
        script_id: &str,
        user_id: &str,
        rating: i32,
        comment: Option<&str>,
        timestamp: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO reviews (id, script_id, user_id, rating, comment, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        )
        .bind(id)
        .bind(script_id)
        .bind(user_id)
        .bind(rating)
        .bind(comment)
        .bind(timestamp)
        .bind(timestamp)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn get_average_rating(&self, script_id: &str) -> Result<Option<f64>, sqlx::Error> {
        sqlx::query_scalar("SELECT AVG(rating) FROM reviews WHERE script_id = ?1")
            .bind(script_id)
            .fetch_one(&self.pool)
            .await
    }
}
