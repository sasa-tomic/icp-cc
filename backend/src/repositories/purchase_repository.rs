use crate::models::{NewPurchase, Purchase};
use sqlx::SqlitePool;

/// Purchases ledger repository (provider-agnostic payment integration).
///
/// One row in `purchases` = one entitlement: a successful payment (via any
/// provider — stub, ICPay, future Stripe, etc.) that grants `account_id`
/// access to the paid bundle of `script_id`. The `UNIQUE(account_id,
/// script_id)` constraint (see migration 006) makes redelivery idempotent —
/// [`PurchaseRepository::create_or_ignore`] issues `INSERT ... ON
/// CONFLICT(account_id, script_id) DO NOTHING`, so a duplicate delivery or
/// a repeat stub purchase is a no-op rather than an error.
///
/// `Clone` is cheap (the underlying `SqlitePool` is a `Pool<SqliteConnection>`
/// held behind an `Arc`; cloning it just bumps the refcount). The Phase K
/// providers each hold their own `PurchaseRepository` constructed from the
/// same shared pool.
#[derive(Clone)]
pub struct PurchaseRepository {
    pool: SqlitePool,
}

impl PurchaseRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    /// Idempotent insert. Returns `Ok(true)` when a row was inserted, `Ok(false)`
    /// when the `(account_id, script_id)` entitlement already existed (so a
    /// redelivered webhook is a clean no-op). Any other DB error is surfaced.
    pub async fn create_or_ignore(&self, purchase: &NewPurchase) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            r#"
            INSERT INTO purchases (
                id, account_id, script_id, icpay_intent_id, icpay_transaction_id,
                usd_amount, currency, status, paid_at, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, script_id) DO NOTHING
            "#,
        )
        .bind(&purchase.id)
        .bind(&purchase.account_id)
        .bind(&purchase.script_id)
        .bind(&purchase.icpay_intent_id)
        .bind(&purchase.icpay_transaction_id)
        .bind(purchase.usd_amount)
        .bind(&purchase.currency)
        .bind(&purchase.status)
        .bind(&purchase.paid_at)
        .bind(&purchase.created_at)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Looks up the entitlement row for `(account_id, script_id)`, if any.
    pub async fn find_by_account_and_script(
        &self,
        account_id: &str,
        script_id: &str,
    ) -> Result<Option<Purchase>, sqlx::Error> {
        sqlx::query_as::<_, Purchase>(
            r#"
            SELECT id, account_id, script_id, icpay_intent_id, icpay_transaction_id,
                   usd_amount, currency, status, paid_at, created_at
            FROM purchases
            WHERE account_id = ? AND script_id = ?
            "#,
        )
        .bind(account_id)
        .bind(script_id)
        .fetch_optional(&self.pool)
        .await
    }

    /// `true` iff `account_id` is entitled to `script_id` (a purchase row
    /// exists). This is the hot path called by the entitlement gate in
    /// `get_script` / `POST /scripts/:id/download`.
    pub async fn exists_for_account_and_script(
        &self,
        account_id: &str,
        script_id: &str,
    ) -> Result<bool, sqlx::Error> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM purchases WHERE account_id = ? AND script_id = ?",
        )
        .bind(account_id)
        .bind(script_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::initialize_database;
    use crate::models::NewPurchase;
    use sqlx::sqlite::SqlitePoolOptions;

    async fn setup() -> PurchaseRepository {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        initialize_database(&pool).await;
        PurchaseRepository::new(pool)
    }

    fn new_purchase(account: &str, script: &str) -> NewPurchase {
        let now = chrono::Utc::now().to_rfc3339();
        NewPurchase {
            id: uuid::Uuid::new_v4().to_string(),
            account_id: account.to_string(),
            script_id: script.to_string(),
            icpay_intent_id: Some("intent-test".to_string()),
            icpay_transaction_id: Some("tx-test".to_string()),
            usd_amount: 9.99,
            currency: "USD".to_string(),
            status: "completed".to_string(),
            paid_at: now.clone(),
            created_at: now,
        }
    }

    #[tokio::test]
    async fn create_or_ignore_inserts_and_returns_true_on_first_call() {
        let repo = setup().await;
        let inserted = repo
            .create_or_ignore(&new_purchase("acct-1", "script-1"))
            .await
            .unwrap();
        assert!(inserted, "first insert must return true");
    }

    #[tokio::test]
    async fn create_or_ignore_is_idempotent_on_duplicate() {
        let repo = setup().await;
        let first = repo
            .create_or_ignore(&new_purchase("acct-1", "script-1"))
            .await
            .unwrap();
        let second = repo
            .create_or_ignore(&new_purchase("acct-1", "script-1"))
            .await
            .unwrap();
        assert!(first, "first insert returns true");
        assert!(
            !second,
            "second insert of same (account, script) must be a no-op, NOT an error"
        );
    }

    #[tokio::test]
    async fn create_or_ignore_allows_same_script_different_account() {
        let repo = setup().await;
        // The UNIQUE constraint is on (account_id, script_id), so two accounts
        // CAN independently purchase the same script.
        let a = repo
            .create_or_ignore(&new_purchase("acct-1", "script-1"))
            .await
            .unwrap();
        let b = repo
            .create_or_ignore(&new_purchase("acct-2", "script-1"))
            .await
            .unwrap();
        assert!(a);
        assert!(b);
    }

    #[tokio::test]
    async fn find_by_account_and_script_returns_some_when_present() {
        let repo = setup().await;
        repo.create_or_ignore(&new_purchase("acct-1", "script-1"))
            .await
            .unwrap();
        let row = repo
            .find_by_account_and_script("acct-1", "script-1")
            .await
            .unwrap()
            .expect("row must exist after insert");
        assert_eq!(row.account_id, "acct-1");
        assert_eq!(row.script_id, "script-1");
        assert!((row.usd_amount - 9.99).abs() < f64::EPSILON);
        assert_eq!(row.status, "completed");
        assert_eq!(row.currency, "USD");
    }

    #[tokio::test]
    async fn find_by_account_and_script_returns_none_when_absent() {
        let repo = setup().await;
        let row = repo
            .find_by_account_and_script("ghost", "ghost-script")
            .await
            .unwrap();
        assert!(row.is_none(), "no row must exist for unknown keys");
    }

    #[tokio::test]
    async fn exists_for_account_and_script_true_after_insert_false_otherwise() {
        let repo = setup().await;
        assert!(
            !repo
                .exists_for_account_and_script("acct-1", "script-1")
                .await
                .unwrap(),
            "no row yet → false"
        );
        repo.create_or_ignore(&new_purchase("acct-1", "script-1"))
            .await
            .unwrap();
        assert!(
            repo.exists_for_account_and_script("acct-1", "script-1")
                .await
                .unwrap(),
            "row inserted → true"
        );
        // Different account for same script → false (independent entitlements).
        assert!(
            !repo
                .exists_for_account_and_script("acct-2", "script-1")
                .await
                .unwrap(),
            "different account for same script → false"
        );
    }
}
