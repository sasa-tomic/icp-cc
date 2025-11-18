use crate::models::{Account, AccountPublicKey};
use sqlx::SqlitePool;

pub struct SignatureAuditParams<'a> {
    pub audit_id: &'a str,
    pub account_id: Option<&'a str>,
    pub action: &'a str,
    pub payload: &'a str,
    pub signature: &'a str,
    pub public_key: &'a str,
    pub timestamp: i64,
    pub nonce: &'a str,
    pub is_admin_action: bool,
    pub now: &'a str,
}

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
        params: SignatureAuditParams<'_>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO signature_audit (id, account_id, action, payload, signature, public_key, timestamp, nonce, is_admin_action, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
        )
        .bind(params.audit_id)
        .bind(params.account_id)
        .bind(params.action)
        .bind(params.payload)
        .bind(params.signature)
        .bind(params.public_key)
        .bind(params.timestamp)
        .bind(params.nonce)
        .bind(if params.is_admin_action { 1 } else { 0 })
        .bind(params.now)
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

    /// Finds account by ID
    pub async fn find_by_id(&self, account_id: &str) -> Result<Option<Account>, sqlx::Error> {
        let account = sqlx::query_as::<_, Account>(
            r#"
            SELECT id, username, created_at, updated_at
            FROM accounts
            WHERE id = ?
            "#,
        )
        .bind(account_id)
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

    /// Gets count of active keys for an account
    pub async fn count_active_keys(&self, account_id: &str) -> Result<i64, sqlx::Error> {
        let count = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(*)
            FROM account_public_keys
            WHERE account_id = ? AND is_active = 1
            "#,
        )
        .bind(account_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Gets count of all keys (active + inactive) for an account
    pub async fn count_all_keys(&self, account_id: &str) -> Result<i64, sqlx::Error> {
        let count = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(*)
            FROM account_public_keys
            WHERE account_id = ?
            "#,
        )
        .bind(account_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Finds a public key by its ID
    pub async fn find_key_by_id(
        &self,
        key_id: &str,
    ) -> Result<Option<AccountPublicKey>, sqlx::Error> {
        let key = sqlx::query_as::<_, AccountPublicKey>(
            r#"
            SELECT id, account_id, public_key, ic_principal, is_active, added_at, disabled_at, disabled_by_key_id
            FROM account_public_keys
            WHERE id = ?
            "#,
        )
        .bind(key_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(key)
    }

    /// Disables a public key (soft delete)
    pub async fn disable_key(
        &self,
        key_id: &str,
        disabled_by_key_id: &str,
        now: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            UPDATE account_public_keys
            SET is_active = 0, disabled_at = ?, disabled_by_key_id = ?
            WHERE id = ?
            "#,
        )
        .bind(now)
        .bind(disabled_by_key_id)
        .bind(key_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
