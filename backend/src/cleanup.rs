use sqlx::SqlitePool;
use std::time::Duration;
use tokio::time;

/// Background job that cleans up old signature audit records
/// Runs daily and removes records older than 180 days
pub async fn start_audit_cleanup_job(pool: SqlitePool) {
    tracing::info!("Starting signature audit cleanup background job");

    tokio::spawn(async move {
        // Run cleanup once per day
        let mut interval = time::interval(Duration::from_secs(86400)); // 24 hours

        loop {
            interval.tick().await;

            tracing::info!("Running signature audit cleanup...");

            match cleanup_old_audit_records(&pool).await {
                Ok(deleted_count) => {
                    tracing::info!(
                        "Signature audit cleanup completed: {} records deleted",
                        deleted_count
                    );
                }
                Err(e) => {
                    tracing::error!("Signature audit cleanup failed: {}", e);
                }
            }
        }
    });
}

/// Deletes signature audit records older than 180 days
async fn cleanup_old_audit_records(pool: &SqlitePool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        r#"
        DELETE FROM signature_audit
        WHERE datetime(created_at) < datetime('now', '-180 days')
        "#,
    )
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::initialize_database;
    use chrono::Utc;
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup_test_db() -> SqlitePool {
        let pool = SqlitePoolOptions::new().connect(":memory:").await.unwrap();
        initialize_database(&pool).await;
        pool
    }

    #[tokio::test]
    async fn test_cleanup_removes_old_records() {
        let pool = setup_test_db().await;

        // Insert a record that's 91 days old (should be deleted)
        let old_date = Utc::now() - chrono::Duration::days(91);
        let old_record_id = uuid::Uuid::new_v4().to_string();

        sqlx::query(
            r#"
            INSERT INTO signature_audit (id, account_id, action, payload, signature, public_key, timestamp, nonce, is_admin_action, created_at)
            VALUES (?, NULL, 'test_action', 'test_payload', 'test_sig', 'test_key', 0, 'nonce1', 0, ?)
            "#,
        )
        .bind(&old_record_id)
        .bind(old_date.to_rfc3339())
        .execute(&pool)
        .await
        .unwrap();

        // Insert a record that's 30 days old (should be kept)
        let recent_date = Utc::now() - chrono::Duration::days(30);
        let recent_record_id = uuid::Uuid::new_v4().to_string();

        sqlx::query(
            r#"
            INSERT INTO signature_audit (id, account_id, action, payload, signature, public_key, timestamp, nonce, is_admin_action, created_at)
            VALUES (?, NULL, 'test_action', 'test_payload', 'test_sig', 'test_key', 0, 'nonce2', 0, ?)
            "#,
        )
        .bind(&recent_record_id)
        .bind(recent_date.to_rfc3339())
        .execute(&pool)
        .await
        .unwrap();

        // Run cleanup
        let deleted = cleanup_old_audit_records(&pool).await.unwrap();

        // Should have deleted 1 record (the 91-day-old one)
        assert_eq!(deleted, 1);

        // Verify old record is gone
        let old_exists =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM signature_audit WHERE id = ?")
                .bind(&old_record_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(old_exists, 0);

        // Verify recent record still exists
        let recent_exists =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM signature_audit WHERE id = ?")
                .bind(&recent_record_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(recent_exists, 1);
    }

    #[tokio::test]
    async fn test_cleanup_no_old_records() {
        let pool = setup_test_db().await;

        // Insert only recent records
        for i in 0..5 {
            let recent_date = Utc::now() - chrono::Duration::days(i * 10); // 0, 10, 20, 30, 40 days old
            let record_id = uuid::Uuid::new_v4().to_string();

            sqlx::query(
                r#"
                INSERT INTO signature_audit (id, account_id, action, payload, signature, public_key, timestamp, nonce, is_admin_action, created_at)
                VALUES (?, NULL, 'test_action', 'test_payload', 'test_sig', 'test_key', 0, ?, 0, ?)
                "#,
            )
            .bind(&record_id)
            .bind(format!("nonce{}", i))
            .bind(recent_date.to_rfc3339())
            .execute(&pool)
            .await
            .unwrap();
        }

        // Run cleanup
        let deleted = cleanup_old_audit_records(&pool).await.unwrap();

        // Should have deleted 0 records (all are recent)
        assert_eq!(deleted, 0);

        // Verify all 5 records still exist
        let total_count = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM signature_audit")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(total_count, 5);
    }

    #[tokio::test]
    async fn test_cleanup_exactly_180_days() {
        let pool = setup_test_db().await;

        // Insert a record that's exactly 180 days old (should be kept)
        let exactly_180_days = Utc::now() - chrono::Duration::days(180);
        let record_id = uuid::Uuid::new_v4().to_string();

        sqlx::query(
            r#"
            INSERT INTO signature_audit (id, account_id, action, payload, signature, public_key, timestamp, nonce, is_admin_action, created_at)
            VALUES (?, NULL, 'test_action', 'test_payload', 'test_sig', 'test_key', 0, 'nonce1', 0, ?)
            "#,
        )
        .bind(&record_id)
        .bind(exactly_180_days.to_rfc3339())
        .execute(&pool)
        .await
        .unwrap();

        // Run cleanup
        let deleted = cleanup_old_audit_records(&pool).await.unwrap();

        // Should have deleted 0 records (exactly 180 days is kept)
        assert_eq!(deleted, 0);

        // Verify record still exists
        let exists =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM signature_audit WHERE id = ?")
                .bind(&record_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(exists, 1);
    }
}
