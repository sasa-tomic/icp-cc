use crate::models::{Account, AccountPublicKey, SignatureAudit};
use sqlx::SqlitePool;

pub struct AccountRepository {
    pool: SqlitePool,
}

impl AccountRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    /// Creates a new account with an initial public key
    pub async fn create_account(
        &self,
        account_id: &str,
        username: &str,
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO accounts (id, username, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            "#,
        )
        .bind(account_id)
        .bind(username)
        .bind(now)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Adds a public key to an account
    pub async fn add_public_key(
        &self,
        key_id: &str,
        account_id: &str,
        public_key: &str,
        ic_principal: &str,
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO account_public_keys (id, account_id, public_key, ic_principal, is_active, added_at)
            VALUES (?, ?, ?, ?, 1, ?)
            "#,
        )
        .bind(key_id)
        .bind(account_id)
        .bind(public_key)
        .bind(ic_principal)
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Records a signature in the audit trail
    pub async fn record_signature_audit(
        &self,
        audit_id: &str,
        account_id: Option<&str>,
        action: &str,
        payload: &str,
        signature: &str,
        public_key: &str,
        timestamp: i64,
        nonce: &str,
        is_admin_action: bool,
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO signature_audit (id, account_id, action, payload, signature, public_key, timestamp, nonce, is_admin_action, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(audit_id)
        .bind(account_id)
        .bind(action)
        .bind(payload)
        .bind(signature)
        .bind(public_key)
        .bind(timestamp)
        .bind(nonce)
        .bind(if is_admin_action { 1 } else { 0 })
        .bind(now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Finds account by username
    pub async fn find_by_username(&self, username: &str) -> Result<Option<Account>, sqlx::Error> {
        let account = sqlx::query_as::<_, Account>(
            r#"
            SELECT id, username, created_at, updated_at
            FROM accounts
            WHERE username = ?
            "#,
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        Ok(account)
    }

    /// Finds public key by the key value
    pub async fn find_public_key_by_value(
        &self,
        public_key: &str,
    ) -> Result<Option<AccountPublicKey>, sqlx::Error> {
        let key = sqlx::query_as::<_, AccountPublicKey>(
            r#"
            SELECT id, account_id, public_key, ic_principal, is_active, added_at, disabled_at, disabled_by_key_id
            FROM account_public_keys
            WHERE public_key = ?
            "#,
        )
        .bind(public_key)
        .fetch_optional(&self.pool)
        .await?;

        Ok(key)
    }

    /// Gets all public keys for an account
    pub async fn get_account_keys(
        &self,
        account_id: &str,
    ) -> Result<Vec<AccountPublicKey>, sqlx::Error> {
        let keys = sqlx::query_as::<_, AccountPublicKey>(
            r#"
            SELECT id, account_id, public_key, ic_principal, is_active, added_at, disabled_at, disabled_by_key_id
            FROM account_public_keys
            WHERE account_id = ?
            ORDER BY added_at ASC
            "#,
        )
        .bind(account_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(keys)
    }
}
